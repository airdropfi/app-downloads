import 'policy.dart';
import 'ports.dart';

enum UpdateKind {
  /// Nothing to show.
  none,

  /// A newer build exists: dismissible banner.
  available,

  /// This build is marked broken by the server: blocking, friendly screen.
  required,
}

/// Play flexible update progress.
enum UpdateStage { idle, downloading, downloaded }

class UpdateStatus {
  const UpdateStatus({
    this.kind = UpdateKind.none,
    this.latestVersion,
    this.policy = UpdatePolicy.empty,
    this.stage = UpdateStage.idle,
  });

  final UpdateKind kind;

  /// Version the banner offers (store version on Apple, policy on Android).
  final String? latestVersion;
  final UpdatePolicy policy;
  final UpdateStage stage;

  static const none = UpdateStatus();

  UpdateStatus copyWith({UpdateKind? kind, UpdateStage? stage}) => UpdateStatus(
    kind: kind ?? this.kind,
    latestVersion: latestVersion,
    policy: policy,
    stage: stage ?? this.stage,
  );
}

/// Pure decision from a policy: is the installed build blocked?
bool isBlocked(UpdatePolicy policy, InstalledApp app) {
  final build = app.build;
  return policy.minSupportedBuild > 0 &&
      build != null &&
      build < policy.minSupportedBuild;
}
