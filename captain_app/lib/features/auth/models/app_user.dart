/// The signed-in captain account, as returned by auth/verify-otp/ and auth/me/.
class AppUser {
  const AppUser({required this.id, required this.phone, required this.firstName});

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'].toString(),
      phone: json['phone'] as String,
      firstName: (json['first_name'] as String?) ?? '',
    );
  }

  final String id;
  final String phone;
  final String firstName;
}
