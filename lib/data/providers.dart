/// Riverpod wiring for the data layer.
///
/// Screens depend on these providers, never on Firebase directly. StreamProvider
/// maps a database stream to rebuildable UI and disposes the underlying listener
/// automatically when nothing is watching — the alternative is managing
/// StreamSubscription lifecycles by hand in initState/dispose, which leaks
/// listeners as soon as the device list grows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/config.dart';
import '../firebase_options.dart';
import 'auth_service.dart';
import 'fake_home_repository.dart';
import 'home_repository.dart';
import 'models/device.dart';

/// The only place in the app that knows which backend is live. Everything else
/// depends on the [HomeRepository] interface, so flipping [kUseFirebase] changes
/// this line's result and nothing else.
final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  if (!kUseFirebase) {
    final fake = FakeHomeRepository();
    ref.onDispose(fake.dispose);
    return fake;
  }
  return FirebaseHomeRepository(homeId: kHomeId);
});

final authServiceProvider = Provider<AuthService>((ref) {
  if (!kUseFirebase) {
    final fake = FakeAuthService();
    ref.onDispose(fake.dispose);
    return fake;
  }
  return FirebaseAuthService();
});

/// Drives the auth gate in `main.dart`. Firebase restores a persisted session
/// asynchronously, so the initial loading state is real and must be rendered —
/// treating "not yet known" as "signed out" flashes the sign-in screen on every
/// cold start.
final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

final floorsProvider = StreamProvider<List<Floor>>((ref) {
  return ref.watch(homeRepositoryProvider).floors();
});

/// Currently selected floor. Null means "all floors".
///
/// Riverpod 3 removed StateProvider, so this is the Notifier equivalent.
class SelectedFloor extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? floorId) => state = floorId;
}

final selectedFloorProvider =
    NotifierProvider<SelectedFloor, String?>(SelectedFloor.new);

/// Devices on the selected floor.
final devicesProvider = StreamProvider<List<Device>>((ref) {
  final floorId = ref.watch(selectedFloorProvider);
  return ref.watch(homeRepositoryProvider).devices(floorId: floorId);
});

/// Every device regardless of floor — for reports and the alert feed.
final allDevicesProvider = StreamProvider<List<Device>>((ref) {
  return ref.watch(homeRepositoryProvider).devices();
});

/// Devices on one specific floor, independent of the dashboard's selection.
///
/// The floor plan screen shows several floors side by side and must not disturb
/// [selectedFloorProvider] — that one belongs to the dashboard's filter chips,
/// and driving it from here would make the two screens fight over it.
final devicesProviderFor =
    StreamProvider.family<List<Device>, String>((ref, floorId) {
  return ref.watch(homeRepositoryProvider).devices(floorId: floorId);
});

/// A single device.
///
/// Scoped per id so toggling one device rebuilds only its own tile rather than
/// the whole grid.
final deviceProvider = StreamProvider.family<Device?, String>((ref, deviceId) {
  return ref.watch(homeRepositoryProvider).device(deviceId);
});

final alertsProvider = StreamProvider<List<Alert>>((ref) {
  return ref.watch(homeRepositoryProvider).alerts();
});

final unreadAlertCountProvider = Provider<int>((ref) {
  return ref.watch(alertsProvider).maybeWhen(
        data: (alerts) => alerts.where((a) => !a.read).length,
        orElse: () => 0,
      );
});

final usageProvider =
    StreamProvider.family<List<UsageDay>, ({String deviceId, int days})>(
        (ref, args) {
  return ref
      .watch(homeRepositoryProvider)
      .usage(args.deviceId, days: args.days);
});

/// How many days the reports screen is charting.
class ReportRange extends Notifier<int> {
  @override
  int build() => 7;

  void select(int days) => state = days;
}

final reportRangeProvider = NotifierProvider<ReportRange, int>(ReportRange.new);

final allUsageProvider =
    StreamProvider<Map<String, List<UsageDay>>>((ref) {
  final days = ref.watch(reportRangeProvider);
  return ref.watch(homeRepositoryProvider).allUsage(days: days);
});

/// Toggles the user has asked for but the database has not confirmed yet.
///
/// A switch has to move on the frame the finger lifts, but the authoritative
/// value only exists once the write has round-tripped through Firebase. Holding
/// the intent here lets a tile render `pending ?? streamValue`: instant
/// response, the stream silently taking over the moment it agrees, and a visible
/// revert if the write is rejected.
///
/// Deliberately NOT stored on the device model — this is UI state about an
/// in-flight request, not a property of the hardware, and it must never be
/// mistaken for something the database said.
class PendingToggles extends Notifier<Map<String, DeviceStatus>> {
  /// A whole device, keyed by its id.
  static String deviceKey(String deviceId) => deviceId;

  /// One channel of a multi-switch. Channels are toggled independently, so they
  /// need independent pending entries — otherwise tapping one channel would
  /// visually move its siblings.
  static String channelKey(String deviceId, int channel) =>
      '$deviceId/$channel';

  @override
  Map<String, DeviceStatus> build() => const {};

  void mark(String key, DeviceStatus status) =>
      state = {...state, key: status};

  void clear(String key) => state = {...state}..remove(key);
}

final pendingTogglesProvider =
    NotifierProvider<PendingToggles, Map<String, DeviceStatus>>(
        PendingToggles.new);
