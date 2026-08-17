/// Domain models for the Smart Home system.
///
/// These mirror the frozen schema documented in the project plan and implemented
/// by `tools/seed.js`. Parsing is deliberately defensive: the database is written
/// by three independent clients (this app, the web simulator, the Node worker),
/// so a field can legitimately be missing or arrive before its siblings. A model
/// that throws on a partially-written node would make the UI flicker into an
/// error state during perfectly normal writes.
library;

enum DeviceStatus {
  on,
  off,
  error,
  disconnected;

  static DeviceStatus parse(Object? raw) {
    switch (raw?.toString().toUpperCase()) {
      case 'ON':
        return DeviceStatus.on;
      case 'ERROR':
        return DeviceStatus.error;
      case 'DISCONNECTED':
        return DeviceStatus.disconnected;
      default:
        return DeviceStatus.off;
    }
  }

  String get wire => switch (this) {
        DeviceStatus.on => 'ON',
        DeviceStatus.off => 'OFF',
        DeviceStatus.error => 'ERROR',
        DeviceStatus.disconnected => 'DISCONNECTED',
      };

  bool get isOn => this == DeviceStatus.on;

  /// ERROR and DISCONNECTED are not actionable — the device is not answering,
  /// so the UI should not offer a toggle that will silently do nothing.
  bool get isControllable =>
      this == DeviceStatus.on || this == DeviceStatus.off;
}

enum DeviceType {
  outlet,
  multiswitch,
  hazard,
  bulb,
  camera;

  static DeviceType parse(Object? raw) => switch (raw?.toString()) {
        'multiswitch' => DeviceType.multiswitch,
        'hazard' => DeviceType.hazard,
        'bulb' => DeviceType.bulb,
        'camera' => DeviceType.camera,
        _ => DeviceType.outlet,
      };

  String get wire => name;
}

/// Position on a floor's abstract grid.
///
/// Integer cell indices, never pixels — pixel coordinates captured on one phone
/// land in the wrong place on every other screen size.
class GridCell {
  const GridCell(this.x, this.y);

  final int x;
  final int y;

  static GridCell fromMap(Object? raw) {
    final map = _asMap(raw);
    return GridCell(_asInt(map['x']), _asInt(map['y']));
  }

  Map<String, Object?> toMap() => {'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is GridCell && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// One switch inside a multi-switch gang box.
class DeviceChannel {
  const DeviceChannel({
    required this.index,
    required this.label,
    required this.state,
  });

  final int index;
  final String label;
  final DeviceStatus state;

  static DeviceChannel fromMap(String key, Object? raw) {
    final map = _asMap(raw);
    final index = int.tryParse(key) ?? 0;
    return DeviceChannel(
      index: index,
      label: map['label']?.toString() ?? 'Switch ${index + 1}',
      state: DeviceStatus.parse(map['state']),
    );
  }
}

/// Automatic on/off window for a bulb.
class DeviceSchedule {
  const DeviceSchedule({
    required this.enabled,
    required this.onAt,
    required this.offAt,
    required this.days,
    required this.timezone,
  });

  final bool enabled;
  final String onAt; // "HH:mm"
  final String offAt; // "HH:mm"
  final List<int> days; // ISO weekday, 1 = Monday .. 7 = Sunday
  final String timezone;

  static const empty = DeviceSchedule(
    enabled: false,
    onAt: '18:00',
    offAt: '23:00',
    days: [1, 2, 3, 4, 5, 6, 7],
    timezone: 'Asia/Colombo',
  );

  static DeviceSchedule? fromMap(Object? raw) {
    if (raw == null) return null;
    final map = _asMap(raw);
    return DeviceSchedule(
      enabled: map['enabled'] == true,
      onAt: map['onAt']?.toString() ?? '18:00',
      offAt: map['offAt']?.toString() ?? '23:00',
      days: (map['days'] as List?)?.map((d) => _asInt(d)).toList() ??
          const [1, 2, 3, 4, 5, 6, 7],
      timezone: map['tz']?.toString() ?? 'Asia/Colombo',
    );
  }

  Map<String, Object?> toMap() => {
        'enabled': enabled,
        'onAt': onAt,
        'offAt': offAt,
        'days': days,
        'tz': timezone,
      };
}

class Floor {
  const Floor({
    required this.id,
    required this.name,
    required this.order,
    required this.planAsset,
    required this.cols,
    required this.rows,
  });

  final String id;
  final String name;
  final int order;
  final String planAsset;
  final int cols;
  final int rows;

  static Floor fromMap(String id, Object? raw) {
    final map = _asMap(raw);
    final grid = _asMap(map['grid']);
    return Floor(
      id: id,
      name: map['name']?.toString() ?? 'Floor',
      order: _asInt(map['order']),
      planAsset: map['planAsset']?.toString() ?? '',
      cols: _asInt(grid['cols'], fallback: 10),
      rows: _asInt(grid['rows'], fallback: 8),
    );
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'order': order,
        'planAsset': planAsset,
        'grid': {'cols': cols, 'rows': rows},
      };
}

class Device {
  const Device({
    required this.id,
    required this.floorId,
    required this.name,
    required this.type,
    required this.cell,
    required this.status,
    this.channels = const [],
    this.maxOnDurationSec,
    this.onSince,
    this.schedule,
    this.snapshotUri,
    this.streamUri,
    this.lastChangedBy,
    this.lastChangedAt,
    this.online = true,
  });

  final String id;
  final String floorId;
  final String name;
  final DeviceType type;
  final GridCell cell;

  /// Raw status as stored. Prefer [effectiveStatus] for anything user-facing.
  final DeviceStatus status;

  final List<DeviceChannel> channels;
  final int? maxOnDurationSec;

  /// Server-owned: stamped by the safety worker, never written by this app.
  final int? onSince;

  final DeviceSchedule? schedule;
  final String? snapshotUri;
  final String? streamUri;
  final String? lastChangedBy;
  final int? lastChangedAt;

  /// From `presence/<id>/online`, joined in by the repository.
  final bool online;

  static Device fromMap(String id, Object? raw, {bool online = true}) {
    final map = _asMap(raw);
    final runtime = _asMap(map['runtime']);
    final config = _asMap(map['config']);

    // `channels` arrives in one of TWO shapes and both have to be handled.
    //
    // seed.js writes the keys 0, 1, 2. Firebase stores every node as a map, but
    // when a node's keys are integers running contiguously from 0 the SDK
    // reconstructs it as a **List**, not a Map. So the same node parses as a Map
    // when a channel has been deleted (keys 0, 2) and as a List when it has not.
    // Handling only the Map case silently yields zero channels — every
    // multi-switch then renders "0/0 on" against the real database while looking
    // correct against seeded test data.
    final rawChannels = map['channels'];
    final channels = <DeviceChannel>[];
    if (rawChannels is Map) {
      rawChannels.forEach((key, value) {
        if (value != null) {
          channels.add(DeviceChannel.fromMap(key.toString(), value));
        }
      });
    } else if (rawChannels is List) {
      for (var i = 0; i < rawChannels.length; i++) {
        // A List reconstructed from sparse keys carries nulls in the gaps.
        if (rawChannels[i] != null) {
          channels.add(DeviceChannel.fromMap('$i', rawChannels[i]));
        }
      }
    }
    channels.sort((a, b) => a.index.compareTo(b.index));

    return Device(
      id: id,
      floorId: map['floorId']?.toString() ?? '',
      name: map['name']?.toString() ?? id,
      type: DeviceType.parse(map['type']),
      cell: GridCell.fromMap(map['cell']),
      status: DeviceStatus.parse(map['status']),
      channels: channels,
      maxOnDurationSec:
          config['maxOnDurationSec'] == null ? null : _asInt(config['maxOnDurationSec']),
      onSince: runtime['onSince'] == null ? null : _asInt(runtime['onSince']),
      schedule: DeviceSchedule.fromMap(map['schedule']),
      snapshotUri: map['snapshotUri']?.toString(),
      streamUri: map['streamUri']?.toString(),
      lastChangedBy: map['lastChangedBy']?.toString(),
      lastChangedAt: map['lastChangedAt'] == null ? null : _asInt(map['lastChangedAt']),
      online: online,
    );
  }

  /// What the user should actually see.
  ///
  /// DISCONNECTED is derived, never stored: a device nobody can reach is a
  /// different condition from one that was switched off, and presence is the
  /// only thing that knows the difference. Presence therefore wins over status.
  DeviceStatus get effectiveStatus =>
      online ? status : DeviceStatus.disconnected;

  /// A gang box is one entity wrapping N channels, and reads ON if ANY channel
  /// is on. The worker and the simulator apply the same rule, so the three
  /// clients can never disagree about a unit's summary state.
  bool get isOn => type == DeviceType.multiswitch
      ? channels.any((c) => c.state.isOn)
      : status.isOn;

  bool get isHazard => type == DeviceType.hazard;

  /// Seconds until the server-side safety cutoff fires, or null when not armed.
  ///
  /// Display only. The cutoff itself runs in the Node worker, so it still fires
  /// when this app is closed, offline, or the phone is dead.
  int? get secondsUntilCutoff {
    if (!isHazard || !status.isOn) return null;
    final started = onSince;
    final limit = maxOnDurationSec;
    if (started == null || limit == null) return null;
    final elapsed = (DateTime.now().millisecondsSinceEpoch - started) ~/ 1000;
    final remaining = limit - elapsed;
    return remaining < 0 ? 0 : remaining;
  }

  Map<String, Object?> toMap() => {
        'floorId': floorId,
        'name': name,
        'type': type.wire,
        'cell': cell.toMap(),
        'status': status.wire,
        if (channels.isNotEmpty)
          'channels': {
            for (final c in channels)
              c.index.toString(): {'label': c.label, 'state': c.state.wire},
          },
        if (maxOnDurationSec != null)
          'config': {'maxOnDurationSec': maxOnDurationSec},
        if (schedule != null) 'schedule': schedule!.toMap(),
        if (snapshotUri != null) 'snapshotUri': snapshotUri,
        if (streamUri != null) 'streamUri': streamUri,
        // `runtime` is deliberately absent: it is server-owned and the security
        // rules reject any client write to it.
      };
}

class Alert {
  const Alert({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.reason,
    required this.timestamp,
    required this.read,
    this.limitSec,
    this.heldForSec,
  });

  final String id;
  final String deviceId;
  final String deviceName;
  final String reason;
  final int timestamp;
  final bool read;
  final int? limitSec;
  final int? heldForSec;

  static Alert fromMap(String id, Object? raw) {
    final map = _asMap(raw);
    return Alert(
      id: id,
      deviceId: map['deviceId']?.toString() ?? '',
      deviceName: map['deviceName']?.toString() ?? map['deviceId']?.toString() ?? '',
      reason: map['reason']?.toString() ?? 'UNKNOWN',
      timestamp: _asInt(map['ts']),
      read: map['read'] == true,
      limitSec: map['limitSec'] == null ? null : _asInt(map['limitSec']),
      heldForSec: map['heldForSec'] == null ? null : _asInt(map['heldForSec']),
    );
  }

  bool get isCutoff => reason == 'MAX_DURATION_EXCEEDED';
}

/// One device's usage on one calendar day, aggregated server-side by the worker.
class UsageDay {
  const UsageDay({
    required this.date,
    required this.onSeconds,
    required this.toggleCount,
  });

  final String date; // YYYY-MM-DD
  final int onSeconds;
  final int toggleCount;

  static UsageDay fromMap(String date, Object? raw) {
    final map = _asMap(raw);
    return UsageDay(
      date: date,
      onSeconds: _asInt(map['onSeconds']),
      toggleCount: _asInt(map['toggleCount']),
    );
  }

  double get onHours => onSeconds / 3600.0;
}

// --- parsing helpers --------------------------------------------------------
// Firebase returns Map<Object?, Object?>, and numbers arrive as either int or
// double depending on how they were written. Normalising once here keeps the
// casts out of every model.

Map<String, Object?> _asMap(Object? raw) {
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

int _asInt(Object? raw, {int fallback = 0}) {
  if (raw is int) return raw;
  if (raw is double) return raw.round();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}
