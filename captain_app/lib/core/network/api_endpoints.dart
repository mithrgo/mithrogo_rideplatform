/// Paths relative to Env.apiBaseUrl (which ends in /api/v1/).
class ApiEndpoints {
  const ApiEndpoints._();

  static const sendOtp = 'auth/send-otp/';
  static const verifyOtp = 'auth/verify-otp/';
  static const refresh = 'auth/refresh/';
  static const logout = 'auth/logout/';
  static const me = 'auth/me/';

  static const profile = 'captains/profile/';
  static const status = 'captains/status/';
  static const online = 'captains/status/online/';
  static const offline = 'captains/status/offline/';
  static const location = 'captains/location/';
  static const kyc = 'captains/kyc/';
  static const kycDocuments = 'captains/kyc/documents/';
  static const vehicles = 'captains/vehicles/';
  static const vehicleOfDay = 'captains/vehicle-of-day/';
  static const earnings = 'captains/earnings/';

  static const offers = 'captains/offers/';
  static const rides = 'captains/rides/';
  static String ride(String id) => 'captains/rides/$id/';
  static String rideAction(String id, String action) => 'captains/rides/$id/$action/';

  static const subscription = 'captains/subscription/';
  static const plans = 'captains/subscription/plans/';
  static const switchPlan = 'captains/subscription/plan/';
  static const dues = 'captains/subscription/dues/';
  static const wallet = 'captains/wallet/';
  static const walletPayPlan = 'captains/wallet/pay-plan/';
  static const walletPayDues = 'captains/wallet/pay-dues/';
}
