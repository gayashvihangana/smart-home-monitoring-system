/// The seam between the UI and Firebase.
///
/// Nothing outside `lib/data/` imports `firebase_database`. Every screen talks to
/// this interface, which is why the whole app could move to a different backend
/// by rewriting one file.
library;

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'models/device.dart';

abstract class HomeRepository {
  Stream<List<Floor>> floors();

  /// All devices, or just one floor's. Presence is joined in, so every emitted
  /// [Device] already knows whether its hardware is reachable.
  Stream<List<Device>> devices({String? floorId});

  Stream<Device?> device(String deviceId);

  Stream<List<Alert>> alerts({int limit = 50});

  Stream<List<UsageDay>> usage(String deviceId, {int days = 7});

  /// Usage for every device, keyed by device id.
  ///
  /// One subscription rather than one per device: the ranked list needs all of
  /// them at once, and N listeners on sibling paths would open N times the
  /// traffic for data that arrives in a single node anyway.
  Stream<Map<String, List<UsageDay>>> allUsage({int days = 7});

  Future<void> setStatus(String deviceId, DeviceStatus status);

  Future<void> setChannel(String deviceId, int channel, DeviceStatus state);

  Future<void> upsertDevice(Device device);

  Future<void> deleteDevice(String deviceId);

  Future<void> moveDevice(String deviceId, GridCell cell);

  Future<void> upsertFloor(Floor floor);

  Future<void> deleteFloor(String floorId);

  Future<void> setSchedule(String deviceId, DeviceSchedule schedule);

  Future<void> setHazardConfig(String deviceId, int maxOnDurationSec);

  Future<void> markAlertRead(String alertId);
}

class FirebaseHomeRepository implements HomeRepository {
  FirebaseHomeRepository({
    required this.homeId,
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance;

  final String homeId;
  final FirebaseDatabase _db;

  DatabaseReference get _home => _db.ref('homes/$homeId');
  DatabaseReference get _devices => _home.child('devices');
  DatabaseReference get _presence => _db.ref('presence');

  // --- reads ----------------------------------------------------------------

  @override
  Stream<List<Floor>> floors() {
    return _home.child('floors').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <Floor>[];
      final list = raw.entries
          .map((e) => Floor.fromMap(e.key.toString(), e.value))
          .toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  /// Devices joined with presence.
  ///
  /// Two independent streams have to become one, because a device's visible
  /// state depends on both. Rather than nesting listeners — which would rebuild
  /// the device list every time any heartbeat ticked — each stream keeps its own
  /// latest snapshot and emissions are recombined from whichever fired.
  @override
  Stream<List<Device>> devices({String? floorId}) {
    final controller = StreamController<List<Device>>.broadcast();

    Map<Object?, Object?> latestDevices = {};
    Map<String, bool> latestPresence = {};
    var hasDevices = false;

    void emit() {
      if (!hasDevices || controller.isClosed) return;
      final list = latestDevices.entries.map((entry) {
        final id = entry.key.toString();
        return Device.fromMap(id, entry.value,
            online: latestPresence[id] ?? true);
      }).where((d) {
        return floorId == null || d.floorId == floorId;
      }).toList();

      list.sort((a, b) => a.name.compareTo(b.name));
      controller.add(list);
    }

    // Scoped to this home's devices, never the database root — listening higher
    // up would re-serialise the whole tree on every toggle anywhere.
    final devicesSub = _devices.onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        latestDevices = raw is Map ? raw : {};
        hasDevices = true;
        emit();
      },
      onError: controller.addError,
    );

    final presenceSub = _presence.onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        latestPresence = {};
        if (raw is Map) {
          raw.forEach((key, value) {
            if (value is Map) {
              latestPresence[key.toString()] = value['online'] != false;
            }
          });
        }
        emit();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await devicesSub.cancel();
      await presenceSub.cancel();
    };

    return controller.stream;
  }

  @override
  Stream<Device?> device(String deviceId) {
    return devices().map((list) {
      for (final d in list) {
        if (d.id == deviceId) return d;
      }
      return null;
    });
  }

  @override
  Stream<List<Alert>> alerts({int limit = 50}) {
    return _home.child('alerts').orderByChild('ts').limitToLast(limit).onValue.map(
      (event) {
        final raw = event.snapshot.value;
        if (raw is! Map) return <Alert>[];
        final list = raw.entries
            .map((e) => Alert.fromMap(e.key.toString(), e.value))
            .toList();
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      },
    );
  }

  @override
  Stream<List<UsageDay>> usage(String deviceId, {int days = 7}) {
    return _home
        .child('usageDaily')
        .child(deviceId)
        .limitToLast(days)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <UsageDay>[];
      final list = raw.entries
          .map((e) => UsageDay.fromMap(e.key.toString(), e.value))
          .toList();
      list.sort((a, b) => a.date.compareTo(b.date));
      return list;
    });
  }

  @override
  Stream<Map<String, List<UsageDay>>> allUsage({int days = 7}) {
    return _home.child('usageDaily').onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return <String, List<UsageDay>>{};

      final result = <String, List<UsageDay>>{};
      raw.forEach((deviceId, perDay) {
        if (perDay is! Map) return;
        final list = perDay.entries
            .map((e) => UsageDay.fromMap(e.key.toString(), e.value))
            .toList();
        list.sort((a, b) => a.date.compareTo(b.date));
        // Trim client-side: the node holds the full history and the caller only
        // ever charts a window of it.
        result[deviceId.toString()] =
            list.length > days ? list.sublist(list.length - days) : list;
      });
      return result;
    });
  }

  // --- writes ---------------------------------------------------------------

  /// Stamped on every write so it is always provable which client caused a
  /// change — the app, the simulator, the worker, or the scheduler.
  Map<String, Object?> _provenance() => {
        'lastChangedBy': 'app',
        'lastChangedAt': ServerValue.timestamp,
      };

  @override
  Future<void> setStatus(String deviceId, DeviceStatus status) {
    // A plain update is last-write-wins, which is correct for a switch: the most
    // recent human intent should win. A transaction here would be wrong — it
    // would resolve races in favour of whoever retried, not whoever acted last.
    return _devices.child(deviceId).update({
      'status': status.wire,
      ..._provenance(),
    });
  }

  @override
  Future<void> setChannel(String deviceId, int channel, DeviceStatus state) {
    // One multi-path update, so a channel and its unit's provenance can never be
    // observed out of step by a listener.
    return _devices.child(deviceId).update({
      'channels/$channel/state': state.wire,
      'channels/$channel/lastChangedAt': ServerValue.timestamp,
      ..._provenance(),
    });
  }

  @override
  Future<void> upsertDevice(Device device) {
    return _devices.child(device.id).update({
      ...device.toMap(),
      ..._provenance(),
    });
  }

  @override
  Future<void> deleteDevice(String deviceId) async {
    await _devices.child(deviceId).remove();
    await _presence.child(deviceId).remove();
  }

  @override
  Future<void> moveDevice(String deviceId, GridCell cell) {
    return _devices.child(deviceId).update({
      'cell': cell.toMap(),
      ..._provenance(),
    });
  }

  @override
  Future<void> upsertFloor(Floor floor) {
    return _home.child('floors').child(floor.id).update(floor.toMap());
  }

  /// Removing a floor removes the devices standing on it — otherwise they become
  /// orphans that no screen renders and nobody can delete.
  @override
  Future<void> deleteFloor(String floorId) async {
    final snapshot = await _devices.orderByChild('floorId').equalTo(floorId).get();
    final raw = snapshot.value;
    if (raw is Map) {
      for (final key in raw.keys) {
        await deleteDevice(key.toString());
      }
    }
    await _home.child('floors').child(floorId).remove();
  }

  @override
  Future<void> setSchedule(String deviceId, DeviceSchedule schedule) {
    return _devices.child(deviceId).update({
      'schedule': schedule.toMap(),
      ..._provenance(),
    });
  }

  @override
  Future<void> setHazardConfig(String deviceId, int maxOnDurationSec) {
    return _devices.child(deviceId).update({
      'config/maxOnDurationSec': maxOnDurationSec,
      ..._provenance(),
    });
  }

  @override
  Future<void> markAlertRead(String alertId) {
    return _home.child('alerts').child(alertId).update({'read': true});
  }
}
