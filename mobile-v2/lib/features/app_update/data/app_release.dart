/// One APK of a release.
class ReleaseFile {
  /// Download path on the API host, e.g. /app/download/arm64.
  final String url;
  final String sha256;
  final int size;

  const ReleaseFile({
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory ReleaseFile.fromJson(Map<String, dynamic> json) => ReleaseFile(
    url: json['url'] as String,
    sha256: json['sha256'] as String,
    size: (json['size'] as num).toInt(),
  );
}

/// The latest published version of the app (GET /api/v1/app/version).
class AppRelease {
  final String version;

  /// The build number. Every APK of the release has it as its Android
  /// version code (docs/10, D19); higher is newer.
  final int build;

  /// Apps below this build must update before they can sync.
  final int minBuild;

  /// Offered to phones whose bucket is below this (0 to 100).
  final int rolloutPercent;

  /// What is new, by language code: "en", and "sw" when written.
  final Map<String, String> notes;

  /// By phone type: arm64 (most phones), armv7 (older), x86_64 (emulators).
  final Map<String, ReleaseFile> files;

  const AppRelease({
    required this.version,
    required this.build,
    required this.minBuild,
    this.rolloutPercent = 100,
    this.notes = const {},
    required this.files,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
    version: json['version'] as String,
    build: (json['build'] as num).toInt(),
    minBuild: (json['min_build'] as num?)?.toInt() ?? 0,
    rolloutPercent: (json['rollout_percent'] as num?)?.toInt() ?? 100,
    notes: {
      for (final e in (json['notes'] as Map<String, dynamic>? ?? {}).entries)
        if (e.value is String) e.key: e.value as String,
    },
    files: {
      for (final e in (json['files'] as Map<String, dynamic>? ?? {}).entries)
        e.key: ReleaseFile.fromJson(e.value as Map<String, dynamic>),
    },
  );

  /// The notes in [languageCode], or in English when not written in it.
  String notesIn(String languageCode) =>
      notes[languageCode] ?? notes['en'] ?? '';
}

/// The version installed on this phone. The build is Android's version
/// code as it is: Salio's APKs carry no processor-type offset.
class InstalledApp {
  final String version;
  final int build;

  const InstalledApp({required this.version, required this.build});
}
