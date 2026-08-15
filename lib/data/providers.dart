/// Riverpod wiring for the data layer.
///
/// Screens depend on these providers, never on Firebase directly. StreamProvider
/// maps a database stream to rebuildable UI and disposes the underlying listener
/// automatically when nothing is watching — the alternative is managing
/// StreamSubscription lifecycles by hand in initState/dispose, which leaks
/// listeners as soon as the device list grows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';
import 'home_repository.dart';
import 'models/device.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return FirebaseHomeRepository(homeId: kHomeId);
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
