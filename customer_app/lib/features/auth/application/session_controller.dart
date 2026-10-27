import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../../profile/models/customer_profile.dart';
import '../data/auth_repository.dart';
import '../models/app_user.dart';

enum SessionStatus { unknown, signedOut, signedIn }

class SessionState {
  const SessionState._(this.status, this.user);

  const SessionState.unknown() : this._(SessionStatus.unknown, null);

  const SessionState.signedOut() : this._(SessionStatus.signedOut, null);

  const SessionState.signedIn(AppUser user) : this._(SessionStatus.signedIn, user);

  final SessionStatus status;
  final AppUser? user;

  /// Signed in, but the profile still needs a name (the signup step).
  bool get needsProfile => status == SessionStatus.signedIn && (user?.needsProfile ?? false);
}

/// Owns sign-in state. The router listens to this to decide which screen to show.
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState.unknown();

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  TokenStorage get _tokens => ref.read(tokenStorageProvider);

  /// Called from the splash screen. Restores a saved session if its tokens still work.
  ///
  /// Rethrows network errors and leaves the state unknown, so the splash screen can offer a
  /// retry instead of signing out someone whose session is fine but who is offline.
  ///
  /// [minimumWait] holds the result back until it completes, so the splash animation can finish.
  Future<void> restore({Future<void>? minimumWait}) async {
    final access = await _tokens.readAccessToken();
    if (access == null) {
      await minimumWait;
      state = const SessionState.signedOut();
      return;
    }

    try {
      final user = await _auth.me();
      await minimumWait;
      state = SessionState.signedIn(user);
    } on ApiException catch (error) {
      if (error.isNetworkError) rethrow;
      if (error.isUnauthorized) await _tokens.clear();
      await minimumWait;
      state = const SessionState.signedOut();
    }
  }

  Future<void> verifyOtp({required String phone, required String code}) async {
    final result = await _auth.verifyOtp(phone: phone, code: code);
    await _tokens.save(access: result.access, refresh: result.refresh);
    state = SessionState.signedIn(result.user);
  }

  /// Keeps the user's name, email and so on in step with the profile screens.
  void applyProfile(CustomerProfile profile) {
    final user = state.user;
    if (user == null) return;
    state = SessionState.signedIn(AppUser(
      id: user.id,
      phone: user.phone,
      firstName: profile.firstName,
      lastName: profile.lastName,
      email: profile.email,
    ));
  }

  Future<void> signOut() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh != null) {
      try {
        await _auth.logout(refresh);
      } on ApiException {
        // The server session can't be reached or is already invalid. Signing out locally still proceeds.
      }
    }
    await _tokens.clear();
    // Saved places belong to the signed-in rider, so the next person on this phone starts empty.
    await ref.read(recentPlacesProvider.notifier).clear();
    state = const SessionState.signedOut();
  }

  Future<List<String>> deletionBlockers() => _auth.deletionBlockers();

  /// Deletes the account on the server, then clears everything stored for it on this phone.
  Future<void> deleteAccount() async {
    await _auth.deleteAccount();
    await _tokens.clear();
    await ref.read(recentPlacesProvider.notifier).clear();
    state = const SessionState.signedOut();
  }

  /// Called by the API client when the refresh token has expired.
  Future<void> expire() async {
    await _tokens.clear();
    state = const SessionState.signedOut();
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
