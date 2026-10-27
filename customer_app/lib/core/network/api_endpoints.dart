/// Paths relative to Env.apiBaseUrl (which ends in /api/v1/).
class ApiEndpoints {
  const ApiEndpoints._();

  static const sendOtp = 'auth/send-otp/';
  static const verifyOtp = 'auth/verify-otp/';
  static const refresh = 'auth/refresh/';
  static const logout = 'auth/logout/';
  static const me = 'auth/me/';
  static const deleteAccount = 'auth/delete-account/';
  static const customerProfile = 'customers/profile/';
  static const quickPlaces = 'customers/quick-places/';
  static const rideEstimate = 'rides/estimate/';
  static const rides = 'rides/';

  static String ride(String id) => 'rides/$id/';
  static String rideCancel(String id) => 'rides/$id/cancel/';
  static String rideTracking(String id) => 'rides/$id/tracking/';
  static String rideRating(String id) => 'rides/$id/rating/';
  static String ridePayment(String id) => 'rides/$id/payment/';

  static String payment(String id) => 'payments/$id/';

  static const notifications = 'notifications/';
  static String notificationRead(int id) => 'notifications/$id/read/';

  static const supportTickets = 'support/tickets/';
}
