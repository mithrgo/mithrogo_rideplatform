import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_exception.dart';
import '../models/app_user.dart';

enum SessionStatus { unknown, signedOut, signedIn }

class SessionState {
  const SessionState._(this.status, this.user);

  const SessionState.unknown() : this._(SessionStatus.unknown, null);

  const SessionState.signedOut() : this._(SessionStatus.signedOut, null);

  const SessionState.signedIn(AppUser user) : this._(SessionStatus.signedIn, user);

  final SessionStatus status;
  final AppUser? user;
}

/// Owns sign-in state. The router listens to this to decide which screen to show.
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState.unknown();

  /// Called from the splash screen. Restores a saved session if its tokens still work.
  ///
  /// Rethrows network errors and leaves the state unknown, so the splash screen can offer a
  /// retry instead of signing out a captain whose session is fine but who is offline.
  ///
  /// [minimumWait] holds the result back until it completes, so the splash animation can finish.
  Future<void> restore({Future<void>? minimumWait}) async {
    final tokens = ref.read(tokenStorageProvider);
    if (await tokens.readAccessToken() == null) {
      await minimumWait;
      state = const SessionState.signedOut();
      return;
    }

    try {
      final user = await ref.read(authRepositoryProvider).me();
      await minimumWait;
      state = SessionState.signedIn(user);
    } on ApiException catch (error) {
      if (error.isNetworkError) rethrow;
      if (error.isUnauthorized) await tokens.clear();
      await minimumWait;
      state = const SessionState.signedOut();
    }
  }

  Future<void> verifyOtp({required String phone, required String code}) async {
    final result = await ref.read(authRepositoryProvider).verifyOtp(phone: phone, code: code);
    await ref.read(tokenStorageProvider).save(access: result.access, refresh: result.refresh);
    state = SessionState.signedIn(result.user);
  }

  Future<void> signOut() async {
    final tokens = ref.read(tokenStorageProvider);
    final refresh = await tokens.readRefreshToken();
    if (refresh != null) {
      try {
        await ref.read(authRepositoryProvider).logout(refresh);
      } on ApiException {
        // The server can't be reached or the token is already invalid. Signing out locally still proceeds.
      }
    }
    await tokens.clear();
    state = const SessionState.signedOut();
  }

  /// Called by the API client when the refresh token has expired.
  Future<void> expire() async {
    await ref.read(tokenStorageProvider).clear();
    state = const SessionState.signedOut();
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
