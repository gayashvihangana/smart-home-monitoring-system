/// An in-memory [HomeRepository], seeded with the same data as `tools/seed.js`.
///
/// This is not a stub that returns empty lists. It holds the data in **wire
/// shape** — the nested `Map<String, Object?>` structure the database actually
/// stores — and parses it through the same `Device.fromMap` the Firebase
/// repository uses. So the models, the parsing, and every screen are exercised
/// exactly as they will be against the live database; only the transport differs.
///
/// It exists because `firebase/database.rules.json` denies every read until an
/// account's UID is written into `homes/<id>/meta/members`, which requires
/// Firebase console access. Flip `kUseFirebase` in `app/config.dart` to run
/// against this instead and keep building.
///
/// Three behaviours are deliberately simulated rather than faked away:
///   * writes take ~150 ms, so an optimistic toggle is visibly optimistic
///   * [failNextWrite] makes the next write throw, so revert-on-failure can be
///     demonstrated rather than merely claimed
///   * hazard cutoffs actually fire, mirroring `worker/lib/cutoff.js`
library;

import 'dart:async';

import 'home_repository.dart';
import 'models/device.dart';

class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository() {
    _seed();
  }

  /// Round trip for a write. Long enough to see, short enough not to annoy.
  static const Duration writeLatency = Duration(milliseconds: 150);

  /// Arm this and the next write throws. The UI should roll its optimistic
  /// update back and surface the error rather than silently diverging from the
  /// database.
  bool failNextWrite = false;

  final _changes = StreamController<void>.broadcast();
  final _cutoffTimers = <String, Timer>{};

  late Map<String, Object?> _floors;
  late Map<String, Object?> _devices;
  late Map<String, bool> _presence;
  late Map<String, Object?> _alerts;
  late Map<String, Object?> _usage;

  void dispose() {
    for (final timer in _cutoffTimers.values) {
      timer.cancel();
    }
    _cutoffTimers.clear();
    _changes.close();
  }

  // --- streams --------------------------------------------------------------

  /// Emits the current value immediately, then again after every mutation.
  ///
  /// Firebase behaves the same way — `onValue` fires once with the existing data
  /// on subscribe — so screens written against this need no changes later.
  ///
  /// Written with an explicit controller rather than an `async*` generator on
  /// purpose: a generator would `yield` the initial value and only then await its
  /// way to subscribing to `_changes`, and any mutation landing in that gap would
  /// be dropped. Subscribing inside `onListen` closes the window.
  Stream<T> _watch<T>(T Function() read) {
    late final StreamController<T> controller;
    StreamSubscription<void>? subscription;

    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        subscription = _changes.stream.listen((_) => controller.add(read()));
      },
      onCancel: () async => subscription?.cancel(),
    );

    return controller.stream;
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<List<Floor>> floors() => _watch(_readFloors);

  List<Floor> _readFloors() {
    final list = _floors.entries
        .map((e) => Floor.fromMap(e.key, e.value))
        .toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  @override
  Stream<List<Device>> devices({String? floorId}) =>
      _watch(() => _readDevices(floorId));

  List<Device> _readDevices(String? floorId) {
    final list = _devices.entries
        .map((e) => Device.fromMap(e.key, e.value,
            online: _presence[e.key] ?? true))
        .where((d) => floorId == null || d.floorId == floorId)
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Stream<Device?> device(String deviceId) => _watch(() {
        final raw = _devices[deviceId];
        if (raw == null) return null;
        return Device.fromMap(deviceId, raw,
            online: _presence[deviceId] ?? true);
      });

  @override
  Stream<List<Alert>> alerts({int limit = 50}) => _watch(() {
        final list = _alerts.entries
            .map((e) => Alert.fromMap(e.key, e.value))
            .toList();
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list.length > limit ? list.sublist(0, limit) : list;
      });

  @override
  Stream<List<UsageDay>> usage(String deviceId, {int days = 7}) => _watch(() {
        final perDay = _usage[deviceId];
        if (perDay is! Map) return <UsageDay>[];
        final list = perDay.entries
            .map((e) => UsageDay.fromMap(e.key.toString(), e.value))
            .toList();
        list.sort((a, b) => a.date.compareTo(b.date));
        return list.length > days ? list.sublist(list.length - days) : list;
      });

  @override
  Stream<Map<String, List<UsageDay>>> allUsage({int days = 7}) => _watch(() {
        final result = <String, List<UsageDay>>{};
        _usage.forEach((deviceId, perDay) {
          if (perDay is! Map) return;
          final list = perDay.entries
              .map((e) => UsageDay.fromMap(e.key.toString(), e.value))
              .toList();
          list.sort((a, b) => a.date.compareTo(b.date));
          result[deviceId] =
              list.length > days ? list.sublist(list.length - days) : list;
        });
        return result;
      });

  // --- writes ---------------------------------------------------------------

  /// Every write goes through here, so latency and the failure switch apply
  /// uniformly and no code path can accidentally be instantaneous.
  Future<void> _write(void Function() mutate) async {
    await Future<void>.delayed(writeLatency);
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Simulated write failure');
    }
    mutate();
    _notify();
  }

  Map<String, Object?> _deviceMap(String deviceId) {
    final raw = _devices[deviceId];
    return raw is Map<String, Object?> ? raw : <String, Object?>{};
  }

  void _stampProvenance(Map<String, Object?> device) {
    device['lastChangedBy'] = 'app';
    device['lastChangedAt'] = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Future<void> setStatus(String deviceId, DeviceStatus status) {
    return _write(() {
      final device = _deviceMap(deviceId);
      device['status'] = status.wire;
      _stampProvenance(device);
      _applyHazardRuntime(deviceId, device, status);
    });
  }

  @override
  Future<void> setChannel(String deviceId, int channel, DeviceStatus state) {
    return _write(() {
      final device = _deviceMap(deviceId);
      final channels = device['channels'];
      if (channels is! Map) return;
      final entry = channels['$channel'];
      if (entry is! Map<String, Object?>) return;
      entry['state'] = state.wire;
      entry['lastChangedAt'] = DateTime.now().millisecondsSinceEpoch;
      _stampProvenance(device);
    });
  }

  @override
  Future<void> upsertDevice(Device device) {
    return _write(() {
      final map = Map<String, Object?>.from(device.toMap());
      // Preserve server-owned runtime, which toMap() correctly omits.
      final existing = _devices[device.id];
      if (existing is Map && existing['runtime'] != null) {
        map['runtime'] = existing['runtime'];
      }
      _stampProvenance(map);
      _devices[device.id] = map;
      _presence.putIfAbsent(device.id, () => true);
    });
  }

  @override
  Future<void> deleteDevice(String deviceId) {
    return _write(() {
      _devices.remove(deviceId);
      _presence.remove(deviceId);
      _usage.remove(deviceId);
      _cutoffTimers.remove(deviceId)?.cancel();
    });
  }

  @override
  Future<void> moveDevice(String deviceId, GridCell cell) {
    return _write(() {
      final device = _deviceMap(deviceId);
      device['cell'] = cell.toMap();
      _stampProvenance(device);
    });
  }

  @override
  Future<void> upsertFloor(Floor floor) {
    return _write(() {
      _floors[floor.id] = floor.toMap();
    });
  }

  @override
  Future<void> deleteFloor(String floorId) {
    return _write(() {
      // Same rule as the Firebase repository: devices standing on a deleted
      // floor would become orphans no screen renders and nobody can remove.
      _devices.removeWhere((id, raw) {
        final belongs = raw is Map && raw['floorId'] == floorId;
        if (belongs) {
          _presence.remove(id);
          _usage.remove(id);
          _cutoffTimers.remove(id)?.cancel();
        }
        return belongs;
      });
      _floors.remove(floorId);
    });
  }

  @override
  Future<void> setSchedule(String deviceId, DeviceSchedule schedule) {
    return _write(() {
      final device = _deviceMap(deviceId);
      device['schedule'] = schedule.toMap();
      _stampProvenance(device);
    });
  }

  @override
  Future<void> setHazardConfig(String deviceId, int maxOnDurationSec) {
    return _write(() {
      final device = _deviceMap(deviceId);
      device['config'] = {'maxOnDurationSec': maxOnDurationSec};
      _stampProvenance(device);
    });
  }

  @override
  Future<void> markAlertRead(String alertId) {
    return _write(() {
      final alert = _alerts[alertId];
      if (alert is Map<String, Object?>) alert['read'] = true;
    });
  }

  // --- simulated safety worker ---------------------------------------------
  // Mirrors worker/lib/cutoff.js. Against the real database this is the Node
  // worker's job and the app must never do it — but with kUseFirebase false
  // there is no worker, and a hazard countdown that never fires would misrepresent
  // the system on screen.

  void _applyHazardRuntime(
      String deviceId, Map<String, Object?> device, DeviceStatus status) {
    if (device['type'] != 'hazard') return;

    _cutoffTimers.remove(deviceId)?.cancel();

    if (status != DeviceStatus.on) {
      device.remove('runtime');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    device['runtime'] = {'onSince': now};

    final config = device['config'];
    final limit = config is Map ? config['maxOnDurationSec'] : null;
    if (limit is! int) return;

    _cutoffTimers[deviceId] = Timer(Duration(seconds: limit), () {
      _cutoffTimers.remove(deviceId);
      final target = _deviceMap(deviceId);
      if (target['status'] != 'ON') return;
      target['status'] = 'OFF';
      target['lastChangedBy'] = 'worker';
      target['lastChangedAt'] = DateTime.now().millisecondsSinceEpoch;
      target.remove('runtime');

      _alerts['fakeCutoff${DateTime.now().millisecondsSinceEpoch}'] = {
        'deviceId': deviceId,
        'deviceName': target['name'],
        'reason': 'MAX_DURATION_EXCEEDED',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'read': false,
        'limitSec': limit,
        'heldForSec': limit,
      };
      _notify();
    });
  }

  // --- seed data ------------------------------------------------------------

  void _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;

    _floors = {
      'floorGround': {
        'name': 'Ground Floor',
        'order': 0,
        'planAsset': 'assets/plans/ground.png',
        'grid': {'cols': 10, 'rows': 8},
      },
      'floorFirst': {
        'name': 'First Floor',
        'order': 1,
        'planAsset': 'assets/plans/first.png',
        'grid': {'cols': 10, 'rows': 8},
      },
      'floorRoof': {
        'name': 'Roof Terrace',
        'order': 2,
        'planAsset': 'assets/plans/roof.png',
        'grid': {'cols': 10, 'rows': 8},
      },
    };

    _devices = {
      'outletLiving': {
        'floorId': 'floorGround',
        'name': 'Living Room Outlet',
        'type': 'outlet',
        'cell': {'x': 2, 'y': 3},
        'status': 'OFF',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
      },
      'outletKitchen': {
        'floorId': 'floorGround',
        'name': 'Kitchen Outlet',
        'type': 'outlet',
        'cell': {'x': 7, 'y': 2},
        'status': 'ON',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
      },
      'gangHallway': {
        'floorId': 'floorGround',
        'name': 'Hallway Gang Box',
        'type': 'multiswitch',
        'cell': {'x': 4, 'y': 5},
        'status': 'OFF',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
        'channels': {
          '0': {'label': 'Ceiling Light', 'state': 'OFF', 'lastChangedAt': now},
          '1': {'label': 'Wall Light', 'state': 'OFF', 'lastChangedAt': now},
          '2': {'label': 'Exhaust Fan', 'state': 'OFF', 'lastChangedAt': now},
        },
      },
      'gangBedroom': {
        'floorId': 'floorFirst',
        'name': 'Bedroom Switch Panel',
        'type': 'multiswitch',
        'cell': {'x': 3, 'y': 2},
        'status': 'ON',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
        'channels': {
          '0': {'label': 'Main Light', 'state': 'ON', 'lastChangedAt': now},
          '1': {'label': 'Bedside', 'state': 'OFF', 'lastChangedAt': now},
        },
      },
      'ironLaundry': {
        'floorId': 'floorFirst',
        'name': 'Clothes Iron',
        'type': 'hazard',
        'cell': {'x': 6, 'y': 6},
        'status': 'OFF',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
        'config': {'maxOnDurationSec': 30},
      },
      // Seeded in ERROR rather than OFF. seed.js writes OFF, but against the
      // real database the simulator is what produces ERROR, and with no
      // simulator running here that status chip would never be seen.
      'heaterBath': {
        'floorId': 'floorFirst',
        'name': 'Water Heater',
        'type': 'hazard',
        'cell': {'x': 8, 'y': 4},
        'status': 'ERROR',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
        'config': {'maxOnDurationSec': 300},
      },
      'bulbPorch': {
        'floorId': 'floorGround',
        'name': 'Porch Light',
        'type': 'bulb',
        'cell': {'x': 1, 'y': 7},
        'status': 'OFF',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
        'schedule': {
          'enabled': true,
          'onAt': '18:30',
          'offAt': '23:00',
          'days': [1, 2, 3, 4, 5, 6, 7],
          'tz': 'Asia/Colombo',
        },
      },
      'bulbGarden': {
        'floorId': 'floorRoof',
        'name': 'Garden Light',
        'type': 'bulb',
        'cell': {'x': 5, 'y': 3},
        'status': 'OFF',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
        'schedule': {
          'enabled': true,
          'onAt': '19:00',
          'offAt': '22:30',
          'days': [5, 6, 7],
          'tz': 'Asia/Colombo',
        },
      },
      'camFront': {
        'floorId': 'floorGround',
        'name': 'Front Door Camera',
        'type': 'camera',
        'cell': {'x': 0, 'y': 4},
        'status': 'ON',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
        'snapshotUri': 'https://picsum.photos/seed/frontdoor/640/360',
        'streamUri': 'https://example.com/mock/stream/frontdoor.m3u8',
      },
      'camBack': {
        'floorId': 'floorRoof',
        'name': 'Backyard Camera',
        'type': 'camera',
        'cell': {'x': 9, 'y': 1},
        'status': 'ON',
        'lastChangedAt': now,
        'lastChangedBy': 'seed',
        'snapshotUri': 'https://picsum.photos/seed/backyard/640/360',
        'streamUri': 'https://example.com/mock/stream/backyard.m3u8',
      },
    };

    // Dart infers the nested literals above as Map<String, Object>, which is a
    // subtype of Map<String, Object?> and so passes an `is` check — but writing a
    // null into one at runtime would throw. Re-wrapping each device makes the
    // mutable top level genuinely Map<String, Object?>.
    _devices = <String, Object?>{
      for (final entry in _devices.entries)
        entry.key: Map<String, Object?>.from(entry.value as Map),
    };

    // seed.js writes every device offline, because presence belongs to the
    // hardware and the simulator claims it on connect. Here there is no
    // simulator, so most devices are online and one is not — that single offline
    // camera is what puts the DISCONNECTED chip on screen. Note that its stored
    // status is ON: the point of the derivation is that presence wins anyway.
    _presence = {
      for (final id in _devices.keys) id: true,
      'camBack': false,
    };

    _usage = _buildUsage(now);
    _alerts = _buildAlerts(now);
  }

  /// Reimplements the generator in `tools/seed.js` exactly, including its
  /// FNV-1a hash, so the fake and the real database draw the same charts and a
  /// screenshot taken in either mode is defensible.
  Map<String, Object?> _buildUsage(int now) {
    const typicalOnSeconds = {
      'outlet': 6 * 3600,
      'multiswitch': 5 * 3600,
      'hazard': 20 * 60,
      'bulb': 4.5 * 3600,
      'camera': 24 * 3600,
    };

    final usage = <String, Object?>{};
    _devices.forEach((deviceId, raw) {
      final type = (raw as Map)['type']?.toString() ?? 'outlet';
      final perDay = <String, Object?>{};
      for (var daysAgo = 13; daysAgo >= 0; daysAgo--) {
        final day = DateTime.fromMillisecondsSinceEpoch(
            now - daysAgo * 86400000);
        final key = day.toUtc().toIso8601String().substring(0, 10);
        final r = _pseudoRandom('$deviceId:$key');
        final base = typicalOnSeconds[type] ?? 3600;
        final weekend =
            (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday)
                ? 1.2
                : 1.0;
        perDay[key] = {
          'onSeconds': (base * (0.6 + r * 0.8) * weekend).round(),
          'toggleCount': (2 + r * 10).round().clamp(1, 100),
        };
      }
      usage[deviceId] = perDay;
    });
    return usage;
  }

  /// FNV-1a, masked to 32 bits to match JavaScript's `Math.imul`.
  double _pseudoRandom(String seed) {
    var h = 2166136261;
    for (var i = 0; i < seed.length; i++) {
      h ^= seed.codeUnitAt(i);
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return (h % 1000) / 1000;
  }

  Map<String, Object?> _buildAlerts(int now) {
    final alerts = <String, Object?>{};
    const daysAgo = [2, 5, 9];
    for (var i = 0; i < daysAgo.length; i++) {
      alerts['seedAlert$i'] = {
        'deviceId': 'ironLaundry',
        'deviceName': 'Clothes Iron',
        'reason': 'MAX_DURATION_EXCEEDED',
        'ts': now - daysAgo[i] * 86400000,
        // The most recent one is unread, so the dashboard's AlertBanner and the
        // unread badge are both exercised without waiting for a live cutoff.
        'read': i != 0,
        'limitSec': 30,
        'heldForSec': 31,
      };
    }
    return alerts;
  }
}
