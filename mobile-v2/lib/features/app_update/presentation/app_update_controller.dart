import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/app_info.dart';
import '../data/app_release.dart';
import '../data/app_update_service.dart';
import '../data/install_bucket.dart';

final _log = Logger('app_update');

final appUpdateServiceProvider = Provider<AppUpdateService>(
  (ref) =>
      AppUpdateService.forServer(ref.watch(appEnvironmentProvider).apiBaseUrl),
);

/// The version installed on this phone.
final installedAppProvider = FutureProvider<InstalledApp>((ref) async {
  final info = await ref.watch(packageInfoProvider.future);
  return InstalledApp(
    version: info.version,
    build: int.tryParse(info.buildNumber) ?? 0,
  );
});

/// This phone's type, as release files are named (see [currentAbi]).
final deviceAbiProvider = Provider<String?>((ref) => currentAbi());

/// This phone's fixed place in staged rollouts, 0 to 99.
final installBucketProvider = FutureProvider<int>(
  (ref) async => InstallBucket(await getApplicationSupportDirectory()).read(),
);

final appUpdateProvider = NotifierProvider<AppUpdateController, AppUpdateState>(
  AppUpdateController.new,
);

enum UpdateStep {
  /// Nothing in progress.
  idle,
  downloading,

  /// Downloaded; the user taps Restart to install it.
  readyToInstall,

  /// Handed to Android, which closes the app when the update is in place.
  installing,

  /// The user must first allow Salio to install updates.
  needsPermission,
  failed,
}

/// Why the last step failed, for the screens to put in words.
enum UpdateError {
  /// A check the user asked for could not reach the server.
  checkFailed,
  stopped,
  damaged,
  unavailable,

  /// Android would not start the install.
  couldNotStart,

  /// Android started the install and refused it; see `androidMessage`.
  refused,
}

class AppUpdateState {
  final InstalledApp? installed;
  final AppRelease? latest;

  /// This phone's type; null when no APK is published for it.
  final String? abi;

  /// This phone's rollout bucket, 0 to 99; null until read.
  final int? bucket;
  final bool checking;
  final UpdateStep step;

  /// Downloading by itself on Wi-Fi: nothing is shown until it is ready.
  final bool quiet;
  final int received;
  final int total;
  final UpdateError? error;

  /// Android's own words when it refused the install.
  final String? androidMessage;

  /// The last check was asked for by the user and found nothing newer.
  final bool confirmedUpToDate;

  /// The user chose "Later" for this version (until the app restarts).
  final bool dismissed;

  const AppUpdateState({
    this.installed,
    this.latest,
    this.abi,
    this.bucket,
    this.checking = false,
    this.step = UpdateStep.idle,
    this.quiet = false,
    this.received = 0,
    this.total = 0,
    this.error,
    this.androidMessage,
    this.confirmedUpToDate = false,
    this.dismissed = false,
  });

  bool get _newer {
    final i = installed, l = latest;
    return i != null && l != null && l.build > i.build;
  }

  /// This version may no longer sync: it must update first. Applies to every
  /// phone, whatever the rollout. The ledger keeps working (docs/10, D12).
  bool get required => _newer && installed!.build < latest!.minBuild;

  /// A newer version this phone can install and is offered: in the rollout,
  /// or required.
  bool get available {
    final l = latest;
    if (!_newer || l == null || !l.files.containsKey(abi)) return false;
    if (required) return true;
    final b = bucket;
    return b != null && inRollout(b, l.rolloutPercent);
  }

  double? get progress => total > 0 ? received / total : null;

  AppUpdateState copyWith({
    InstalledApp? installed,
    AppRelease? latest,
    bool clearLatest = false,
    String? abi,
    int? bucket,
    bool? checking,
    UpdateStep? step,
    bool? quiet,
    int? received,
    int? total,
    UpdateError? error,
    String? androidMessage,
    bool clearError = false,
    bool? confirmedUpToDate,
    bool? dismissed,
  }) => AppUpdateState(
    installed: installed ?? this.installed,
    latest: clearLatest ? null : latest ?? this.latest,
    abi: abi ?? this.abi,
    bucket: bucket ?? this.bucket,
    checking: checking ?? this.checking,
    step: step ?? this.step,
    quiet: quiet ?? this.quiet,
    received: received ?? this.received,
    total: total ?? this.total,
    error: clearError ? null : error ?? this.error,
    androidMessage: clearError ? null : androidMessage ?? this.androidMessage,
    confirmedUpToDate: confirmedUpToDate ?? this.confirmedUpToDate,
    dismissed: dismissed ?? this.dismissed,
  );
}

/// Checks for new versions (at start, on return to the app, and when asked)
/// and installs them. From DairyGo, with three changes for Salio:
///
/// - a staged rollout offers a release only to phones in its share;
/// - a required update stops syncing, never the app (the sync controller
///   reads [AppUpdateState.required]);
/// - a download that drops carries on by itself while it is still making
///   progress, so a slow connection, or a server that cuts long transfers,
///   only makes it take longer.
///
/// On Wi-Fi a new version downloads by itself; once it is ready the user
/// taps Restart and Android swaps the app for the new version. On mobile
/// data the user starts the download (Update), and it installs when done.
class AppUpdateController extends Notifier<AppUpdateState> {
  /// Automatic checks are this far apart; the user can check any time.
  static const checkEvery = Duration(hours: 6);

  /// Attempts at one download in a row, as long as each brings more bytes.
  static const maxResumes = 60;

  /// Wait before resuming a dropped download.
  static const resumeAfter = Duration(seconds: 2);

  DateTime? _lastCheck;
  CancelToken? _cancel;
  String? _apkPath;

  AppUpdateService get _service => ref.read(appUpdateServiceProvider);

  @override
  AppUpdateState build() {
    final results = _service.installer.results.listen(_onInstallResult);
    ref.onDispose(results.cancel);
    return AppUpdateState(abi: ref.read(deviceAbiProvider));
  }

  /// Looks for a newer version. Automatic checks fail silently (the phone
  /// may be offline); a check the user asked for says what happened.
  Future<void> check({bool manual = false}) async {
    // Not while an update is under way (a failed one can be checked again).
    final busy =
        state.step != UpdateStep.idle && state.step != UpdateStep.failed;
    if (state.checking || busy) return;
    final last = _lastCheck;
    if (!manual &&
        last != null &&
        DateTime.now().difference(last) < checkEvery) {
      return;
    }
    state = state.copyWith(
      checking: true,
      clearError: true,
      confirmedUpToDate: false,
    );
    try {
      final installed =
          state.installed ?? await ref.read(installedAppProvider.future);
      final bucket =
          state.bucket ?? await ref.read(installBucketProvider.future);
      final latest = await _service.fetchLatest();
      if (!ref.mounted) return;
      _lastCheck = DateTime.now();
      final found = state.copyWith(
        installed: installed,
        bucket: bucket,
        latest: latest,
        clearLatest: latest == null,
        checking: false,
      );
      unawaited(_service.removeOldDownloads(keepBuild: latest?.build));

      // Decide how to offer it before showing anything, so the offer does
      // not flash up and change a moment later.
      final abi = found.abi;
      if (found.available && latest != null && abi != null) {
        _apkPath = await _service.downloaded(latest, abi);
        if (!ref.mounted) return;
        if (_apkPath != null) {
          state = found.copyWith(step: UpdateStep.readyToInstall);
          return;
        }
        if (await _service.onWifi()) {
          if (!ref.mounted) return;
          state = found;
          unawaited(_download(quiet: true));
          return;
        }
      }
      state = found.copyWith(confirmedUpToDate: manual && !found.available);
    } on Exception catch (e) {
      _log.info('update check failed: $e');
      if (!ref.mounted) return;
      state = state.copyWith(
        checking: false,
        error: manual ? UpdateError.checkFailed : null,
      );
    }
  }

  /// The user asked for the new version: downloads it, then installs it.
  Future<void> update() async {
    if (await _download(quiet: false) != null) await install();
  }

  /// Downloads the new version and returns its file, or null when it did
  /// not finish. A [quiet] download shows nothing until it is ready, and
  /// failing only leaves the usual "new version" offer.
  Future<String?> _download({required bool quiet}) async {
    final release = state.latest;
    final abi = state.abi;
    if (!state.available ||
        release == null ||
        abi == null ||
        state.step == UpdateStep.downloading) {
      return null;
    }
    final cancel = _cancel = CancelToken();
    state = state.copyWith(
      step: UpdateStep.downloading,
      quiet: quiet,
      dismissed: quiet ? null : false,
      received: 0,
      total: release.files[abi]!.size,
      clearError: true,
    );
    var shownPercent = -1;
    UpdateError error;
    var resumes = 0;
    while (true) {
      final before = await _service.partSize(release, abi);
      try {
        final path = await _service.download(
          release,
          abi,
          cancel: cancel,
          onProgress: (received, total) {
            // One update per percent, not per network chunk.
            final percent = total > 0 ? received * 100 ~/ total : 0;
            if (percent == shownPercent || !ref.mounted) return;
            shownPercent = percent;
            state = state.copyWith(received: received, total: total);
          },
        );
        _apkPath = path;
        if (!ref.mounted) return path;
        state = state.copyWith(
          step: UpdateStep.readyToInstall,
          quiet: false,
          // Ready to use: offered again even if the user put the offer off.
          dismissed: false,
        );
        return path;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          if (ref.mounted) {
            state = state.copyWith(step: UpdateStep.idle, quiet: false);
          }
          return null;
        }
        error = UpdateError.stopped;
      } on UpdateException catch (e) {
        error = switch (e.failure) {
          UpdateFailure.stopped => UpdateError.stopped,
          UpdateFailure.damaged => UpdateError.damaged,
          UpdateFailure.unavailable => UpdateError.unavailable,
        };
      }
      // Dropped part way but still moving: carry on from where it stopped.
      final now = await _service.partSize(release, abi);
      final moving = error == UpdateError.stopped && now > before;
      if (!moving || ++resumes > maxResumes || cancel.isCancelled) break;
      await Future<void>.delayed(resumeAfter);
      if (!ref.mounted || cancel.isCancelled) return null;
    }
    if (!ref.mounted) return null;
    state = quiet
        ? state.copyWith(step: UpdateStep.idle, quiet: false)
        : state.copyWith(step: UpdateStep.failed, error: error);
    return null;
  }

  /// Stops a download; what arrived is kept for next time.
  void cancel() => _cancel?.cancel();

  /// Installs the downloaded version ("Restart"), first asking for
  /// permission to install updates when needed. Android closes the app once
  /// the new version is in place, and usually opens it again.
  Future<void> install() async {
    final path = _apkPath;
    if (path == null) return;
    final installer = _service.installer;
    if (!await installer.canInstall()) {
      state = state.copyWith(step: UpdateStep.needsPermission);
      return;
    }
    state = state.copyWith(step: UpdateStep.installing, clearError: true);
    if (!await installer.install(path)) {
      state = state.copyWith(
        step: UpdateStep.failed,
        error: UpdateError.couldNotStart,
      );
    }
  }

  void _onInstallResult(InstallResult result) {
    if (!ref.mounted || state.step != UpdateStep.installing) return;
    switch (result.outcome) {
      case InstallOutcome.confirming:
        break;
      case InstallOutcome.cancelled:
        state = state.copyWith(step: UpdateStep.readyToInstall);
      case InstallOutcome.failed:
        state = state.copyWith(
          step: UpdateStep.failed,
          error: UpdateError.refused,
          androidMessage: result.message,
        );
    }
  }

  /// Opens the switch that lets Salio install updates.
  Future<void> allowInstalls() async {
    await _service.installer.openSettings();
  }

  /// Hides the update bar until the app restarts. A required update cannot
  /// be put off.
  void later() => state = state.copyWith(dismissed: true);

  /// The app came back to the front: continue once installs are allowed,
  /// and look for a newer version now and then.
  Future<void> onResume() async {
    if (state.step == UpdateStep.needsPermission &&
        await _service.installer.canInstall()) {
      await install();
    }
    await check();
  }
}
