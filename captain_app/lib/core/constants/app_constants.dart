class AppConstants {
  const AppConstants._();

  static const Duration requestTimeout = Duration(seconds: 15);
  static const int otpLength = 6;
  static const String defaultCountryCode = '+91';

  /// How often the home screen asks for new offers and the active ride.
  static const Duration pollInterval = Duration(seconds: 4);

  /// Locations older than 30 seconds are ignored by matching, so report well inside that.
  static const Duration locationInterval = Duration(seconds: 10);
}
