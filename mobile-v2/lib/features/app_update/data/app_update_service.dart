import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'app_release.dart';

/// Why an update could not be downloaded. Screens say it in the user's
/// language.
enum UpdateFailure {
  /// The connection dropped; what arrived is kept and the download goes on
  /// from there.
  stopped,

  /// The file did not match its checksum and was thrown away.
  damaged,

  /// No APK for this phone type in the release.
  unavailable,
}

class UpdateException implements Exception {
  final UpdateFailure failure;

  const UpdateException(this.failure);

  @override
  String toString() => 'UpdateException(${failure.name})';
}

/// The phone type this app was built for, as release files are named, or
/// null on phones no APK is published for.
String? currentAbi() => switch (Abi.current()) {
  Abi.androidArm64 => 'arm64',
  Abi.androidArm => 'armv7',
  Abi.androidX64 => 'x86_64',
  _ => null,
};

/// How an install ended, as Android reported it.
enum InstallOutcome {
  /// Android is showing its confirm screen.
  confirming,

  /// The user closed the confirm screen without updating.
  cancelled,
  failed,
}

class InstallResult {
  final InstallOutcome outcome;

  /// Android's reason, when it failed.
  final String? message;

  const InstallResult(this.outcome, [this.message]);
}

/// Android's installer, reached through MainActivity.kt. From DairyGo.
class UpdateInstaller {
  static const _channel = MethodChannel('salio/app_update');
  static final _results = StreamController<InstallResult>.broadcast();
  static var _listening = false;

  /// The app's private folder for downloaded updates.
  Future<String> updatesDir() async =>
      (await _channel.invokeMethod<String>('updatesDir'))!;

  /// Whether the user allowed Salio to install updates.
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  /// Opens the "Install unknown apps" switch for Salio.
  Future<bool> openSettings() async =>
      await _channel.invokeMethod<bool>('openInstallSettings') ?? false;

  /// Starts installing [path] over this app. When it succeeds Android closes
  /// the app (and usually opens the new version); otherwise [results] says
  /// what happened. Returns false when the install could not start.
  Future<bool> install(String path) async =>
      await _channel.invokeMethod<bool>('install', {'path': path}) ?? false;

  /// What Android said about installs started with [install].
  Stream<InstallResult> get results {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'installStatus') return;
        final args = Map<String, Object?>.from(call.arguments as Map);
        final outcome = switch (args['status']) {
          'confirming' => InstallOutcome.confirming,
          'cancelled' => InstallOutcome.cancelled,
          'failed' => InstallOutcome.failed,
          _ => null, // installed: this is already the new version
        };
        if (outcome != null) {
          _results.add(InstallResult(outcome, args['message'] as String?));
        }
      });
    }
    return _results.stream;
  }
}

/// Finds and downloads new versions of the app. From DairyGo.
///
/// Downloads continue where they stopped (a 20 MB file takes about half an
/// hour at 100 kbps, and connections drop), and every file is checked
/// against the release's SHA-256 before it is installed. Android then checks
/// it is signed with the same key as the installed app.
class AppUpdateService {
  final Dio _dio;
  final UpdateInstaller installer;

  AppUpdateService(this._dio, this.installer);

  /// A client of its own: no sign-in (an outdated app may not be able to
  /// sign in), and a timeout between received chunks rather than for the
  /// whole file.
  factory AppUpdateService.forServer(Uri origin) => AppUpdateService(
    Dio(
      BaseOptions(
        baseUrl: origin.toString(),
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    ),
    UpdateInstaller(),
  );

  /// The latest release, or null when none is published.
  Future<AppRelease?> fetchLatest() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/v1/app/version');
      return AppRelease.fromJson(res.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Whether the phone is on Wi-Fi (or a cable), where an update can be
  /// downloaded without asking: mobile data costs the shop money.
  Future<bool> onWifi() async {
    try {
      final links = await Connectivity().checkConnectivity();
      return links.contains(ConnectivityResult.wifi) ||
          links.contains(ConnectivityResult.ethernet);
    } on Exception {
      return false;
    }
  }

  static String _fileName(AppRelease r, String abi) =>
      'Salio-${r.build}-$abi.apk';

  /// The already downloaded and checked APK of [release] for [abi], if any.
  Future<String?> downloaded(AppRelease release, String abi) async {
    final file = release.files[abi];
    if (file == null) return null;
    final done = File(
      '${await installer.updatesDir()}/${_fileName(release, abi)}',
    );
    return done.existsSync() && await _matches(done, file) ? done.path : null;
  }

  /// Downloads [release]'s APK for [abi] and returns its path, reporting
  /// bytes received so far out of the total. Throws [UpdateException].
  Future<String> download(
    AppRelease release,
    String abi, {
    CancelToken? cancel,
    void Function(int received, int total)? onProgress,
  }) async {
    final file = release.files[abi];
    if (file == null) {
      throw const UpdateException(UpdateFailure.unavailable);
    }
    final dir = await installer.updatesDir();
    final done = File('$dir/${_fileName(release, abi)}');
    final part = File('${done.path}.part');

    // Downloaded before (the installer was closed, or the app restarted).
    if (done.existsSync() && await _matches(done, file)) {
      onProgress?.call(file.size, file.size);
      return done.path;
    }

    var start = part.existsSync() ? await part.length() : 0;
    if (start > file.size) {
      await part.delete();
      start = 0;
    }
    if (start < file.size) {
      final res = await _dio.get<ResponseBody>(
        file.url,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          // Continue from the saved part, unless the file on the server
          // changed (then the whole file comes back with 200).
          headers: start > 0
              ? {'Range': 'bytes=$start-', 'If-Range': '"${file.sha256}"'}
              : null,
        ),
      );
      if (res.statusCode != 206) start = 0;
      final sink = part.openWrite(
        mode: start > 0 ? FileMode.append : FileMode.write,
      );
      var received = start;
      onProgress?.call(received, file.size);
      try {
        await for (final chunk in res.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, file.size);
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        // A connection that drops mid-file: keep what arrived.
      } finally {
        await sink.close();
      }
    }

    // The connection closed early: keep what arrived for next time.
    if (await part.length() < file.size) {
      throw const UpdateException(UpdateFailure.stopped);
    }
    if (!await _matches(part, file)) {
      await part.delete();
      throw const UpdateException(UpdateFailure.damaged);
    }
    await part.rename(done.path);
    return done.path;
  }

  /// How much of [release]'s APK for [abi] is already on the phone.
  Future<int> partSize(AppRelease release, String abi) async {
    final part = File(
      '${await installer.updatesDir()}/${_fileName(release, abi)}.part',
    );
    return part.existsSync() ? part.length() : 0;
  }

  Future<bool> _matches(File f, ReleaseFile expected) async {
    if (await f.length() != expected.size) return false;
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString() == expected.sha256;
  }

  /// Deletes downloads of other versions (installed or replaced).
  Future<void> removeOldDownloads({int? keepBuild}) async {
    try {
      final dir = Directory(await installer.updatesDir());
      await for (final f in dir.list()) {
        final keep = keepBuild != null && f.path.contains('/Salio-$keepBuild-');
        if (f is File && !keep) await f.delete();
      }
    } on Exception {
      // Best effort: a leftover file is only disk space.
    }
  }
}
