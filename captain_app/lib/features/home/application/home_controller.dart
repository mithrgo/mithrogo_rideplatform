import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../ride/models/ride.dart';
import '../models/home_models.dart';

class HomeState {
  const HomeState({this.status, this.offers = const [], this.activeRide, this.loading = true, this.error});

  final CaptainStatusInfo? status;
  final List<RideOffer> offers;

  /// A ride this captain has accepted and not finished.
  final Ride? activeRide;
  final bool loading;
  final String? error;

  HomeState copyWith({
    CaptainStatusInfo? status,
    List<RideOffer>? offers,
    Ride? activeRide,
    bool clearActiveRide = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return HomeState(
      status: status ?? this.status,
      offers: offers ?? this.offers,
      activeRide: clearActiveRide ? null : (activeRide ?? this.activeRide),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the home screen. While the captain is online it reports the GPS position and polls for
/// ride offers and the active ride (the backend has no push channel yet).
class HomeController extends Notifier<HomeState> {
  Timer? _timer;
  DateTime _lastLocationSent = DateTime.fromMillisecondsSinceEpoch(0);
  int _ticks = 0;
  bool _polling = false;

  @override
  HomeState build() {
    ref.onDispose(() => _timer?.cancel());
    _timer = Timer.periodic(AppConstants.pollInterval, (_) => _tick());
    Future.microtask(refresh);
    return const HomeState();
  }

  Future<void> refresh() async {
    try {
      final status = await ref.read(homeRepositoryProvider).status();
      state = state.copyWith(status: status, loading: false, clearError: true);
      await _pollRides();
    } on ApiException catch (error) {
      state = state.copyWith(loading: false, error: error.message);
    }
  }

  Future<void> _tick() async {
    if (_polling) return;
    _polling = true;
    try {
      _ticks++;
      final online = state.status?.isOnline ?? false;
      if (!online) {
        // Offline: only re-check the status now and then, in case an admin or another device changed it.
        if (_ticks % 8 == 0) await refresh();
        return;
      }
      await _reportLocation();
      await _pollRides();
      if (_ticks % 8 == 0) {
        final status = await ref.read(homeRepositoryProvider).status();
        state = state.copyWith(status: status);
      }
    } on ApiException catch (error) {
      if (!error.isNetworkError) debugPrint('Home poll failed: $error');
    } finally {
      _polling = false;
    }
  }

  Future<void> _pollRides() async {
    final repo = ref.read(homeRepositoryProvider);
    final rides = ref.read(rideRepositoryProvider);
    final offers = (state.status?.isOnline ?? false) ? await repo.offers() : <RideOffer>[];
    final active = (await rides.rides()).where((r) => r.isActive).firstOrNull;
    state = state.copyWith(
      offers: [for (final o in offers) if (o.secondsLeft > 0) o],
      activeRide: active,
      clearActiveRide: active == null,
    );
  }

  Future<void> _reportLocation() async {
    if (DateTime.now().difference(_lastLocationSent) < AppConstants.locationInterval) return;
    try {
      final position = await ref.read(locationServiceProvider).currentPosition();
      await ref.read(homeRepositoryProvider).sendLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            heading: position.heading,
            speed: position.speed,
          );
      _lastLocationSent = DateTime.now();
    } on Exception catch (error) {
      debugPrint('Location report failed: $error');
    }
  }

  /// Returns an error message, or null on success.
  Future<String?> setOnline(bool online) async {
    try {
      final repo = ref.read(homeRepositoryProvider);
      if (online) {
        // The backend matches on the last reported position, so send one before announcing we are online.
        final position = await ref.read(locationServiceProvider).currentPosition();
        await repo.goOnline();
        await repo.sendLocation(latitude: position.latitude, longitude: position.longitude);
        _lastLocationSent = DateTime.now();
      } else {
        await repo.goOffline();
      }
      await refresh();
      return null;
    } catch (error) {
      await refresh();
      return userMessage(error);
    }
  }

  Future<String?> chooseVehicle(String type) async {
    try {
      await ref.read(vehicleRepositoryProvider).chooseForToday(type);
      await refresh();
      return null;
    } catch (error) {
      return userMessage(error);
    }
  }

  Future<String?> accept(RideOffer offer) async {
    try {
      await ref.read(rideRepositoryProvider).accept(offer.rideId);
      await refresh();
      return null;
    } catch (error) {
      await refresh();
      return userMessage(error);
    }
  }

  Future<void> reject(RideOffer offer) async {
    state = state.copyWith(offers: [for (final o in state.offers) if (o.rideId != offer.rideId) o]);
    try {
      await ref.read(rideRepositoryProvider).reject(offer.rideId);
    } on ApiException {
      // The offer may already have expired. Nothing else to do.
    }
  }
}

final homeControllerProvider = NotifierProvider<HomeController, HomeState>(HomeController.new);
