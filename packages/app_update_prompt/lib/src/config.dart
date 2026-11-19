class UpdateConfig {
  const UpdateConfig({
    required this.policyUrl,
    this.appStoreId,
    this.androidPackage,
    this.autoStartFlexible = true,
    this.forParents = false,
    this.throttle = const Duration(hours: 12),
    this.dismissFor = const Duration(days: 3),
    this.storefront,
  });

  /// `https://raw.githubusercontent.com/airdropfi/app-downloads/main/<app>/min.json`
  final String policyUrl;

  /// Numeric App Store id ("6797240519"). Without it Apple builds are never
  /// prompted (an app that is not on the store yet).
  final String? appStoreId;

  /// Android package, for the Play fallback link.
  final String? androidPackage;

  /// Play: start the flexible download on its own when an update exists.
  /// Kids apps set this false: the parent starts it from the banner.
  final bool autoStartFlexible;

  /// Parent-facing copy on the blocking screen (Kids apps).
  final bool forParents;

  /// Minimum gap between two checks (launch and resume share it).
  final Duration throttle;

  /// How long "Later" hides the banner for the same version.
  final Duration dismissFor;

  /// Two-letter App Store country; null uses the device region, then "us".
  final String? storefront;
}
