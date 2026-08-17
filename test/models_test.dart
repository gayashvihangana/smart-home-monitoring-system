import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home/data/models/device.dart';

/// Pure-Dart tests for the parsing and derived-state rules the three clients
/// must agree on. No Firebase, so they run instantly with no credentials.
void main() {
  group('DeviceStatus', () {
    test('parses the wire values', () {
      expect(DeviceStatus.parse('ON'), DeviceStatus.on);
      expect(DeviceStatus.parse('ERROR'), DeviceStatus.error);
      expect(DeviceStatus.parse('DISCONNECTED'), DeviceStatus.disconnected);
      expect(DeviceStatus.parse('OFF'), DeviceStatus.off);
    });

    test('falls back to OFF for junk rather than throwing', () {
      // Three independent clients write this node; a malformed value must not
      // take the whole device list down.
      expect(DeviceStatus.parse(null), DeviceStatus.off);
      expect(DeviceStatus.parse('nonsense'), DeviceStatus.off);
      expect(DeviceStatus.parse(42), DeviceStatus.off);
    });

    test('only ON and OFF are controllable', () {
      expect(DeviceStatus.on.isControllable, isTrue);
      expect(DeviceStatus.off.isControllable, isTrue);
      expect(DeviceStatus.error.isControllable, isFalse);
      expect(DeviceStatus.disconnected.isControllable, isFalse);
    });
  });

  group('Device.effectiveStatus', () {
    test('presence beats status — offline reads DISCONNECTED even when ON', () {
      final device = Device.fromMap(
        'outletLiving',
        {'type': 'outlet', 'status': 'ON', 'name': 'Outlet'},
        online: false,
      );
      expect(device.status, DeviceStatus.on);
      expect(device.effectiveStatus, DeviceStatus.disconnected);
    });

    test('online devices report their stored status', () {
      final device = Device.fromMap(
        'outletLiving',
        {'type': 'outlet', 'status': 'ON'},
        online: true,
      );
      expect(device.effectiveStatus, DeviceStatus.on);
    });
  });

  group('multi-switch', () {
    Device gangBox(List<String> states) => Device.fromMap('gangHallway', {
          'type': 'multiswitch',
          'status': 'OFF',
          'channels': {
            for (var i = 0; i < states.length; i++)
              '$i': {'label': 'Ch$i', 'state': states[i]},
          },
        });

    test('reads ON if any channel is on', () {
      expect(gangBox(['OFF', 'ON', 'OFF']).isOn, isTrue);
    });

    test('reads OFF only when every channel is off', () {
      expect(gangBox(['OFF', 'OFF', 'OFF']).isOn, isFalse);
    });

    test('channels are ordered by index, not map iteration order', () {
      final device = Device.fromMap('gang', {
        'type': 'multiswitch',
        'channels': {
          '2': {'label': 'Third', 'state': 'OFF'},
          '0': {'label': 'First', 'state': 'OFF'},
          '1': {'label': 'Second', 'state': 'OFF'},
        },
      });
      expect(device.channels.map((c) => c.label), ['First', 'Second', 'Third']);
    });

    test('parses channels delivered as a List, not just a Map', () {
      // seed.js writes the keys 0, 1, 2. Firebase reconstructs contiguous
      // integer keys as a List, so this is the shape the REAL database returns —
      // and handling only the Map case renders every gang box as "0/0 on".
      final device = Device.fromMap('gangHallway', {
        'type': 'multiswitch',
        'status': 'OFF',
        'channels': [
          {'label': 'Ceiling Light', 'state': 'OFF'},
          {'label': 'Wall Light', 'state': 'ON'},
          {'label': 'Exhaust Fan', 'state': 'OFF'},
        ],
      });

      expect(device.channels, hasLength(3));
      expect(device.channels.map((c) => c.label),
          ['Ceiling Light', 'Wall Light', 'Exhaust Fan']);
      expect(device.channels.map((c) => c.index), [0, 1, 2]);
      expect(device.isOn, isTrue, reason: 'one channel is on');
    });

    test('skips the null holes in a sparsely-keyed List', () {
      // Deleting channel 1 leaves keys 0 and 2, which Firebase may still deliver
      // as a List — with a null where the removed channel was.
      final device = Device.fromMap('gang', {
        'type': 'multiswitch',
        'channels': [
          {'label': 'First', 'state': 'OFF'},
          null,
          {'label': 'Third', 'state': 'ON'},
        ],
      });

      expect(device.channels.map((c) => c.label), ['First', 'Third']);
      expect(device.channels.map((c) => c.index), [0, 2]);
    });
  });

  group('hazard cutoff countdown', () {
    test('counts down from the configured limit', () {
      final startedTenSecondsAgo =
          DateTime.now().millisecondsSinceEpoch - 10000;
      final device = Device.fromMap('ironLaundry', {
        'type': 'hazard',
        'status': 'ON',
        'config': {'maxOnDurationSec': 30},
        'runtime': {'onSince': startedTenSecondsAgo},
      });
      expect(device.secondsUntilCutoff, closeTo(20, 1));
    });

    test('never goes negative once the limit has passed', () {
      final device = Device.fromMap('ironLaundry', {
        'type': 'hazard',
        'status': 'ON',
        'config': {'maxOnDurationSec': 30},
        'runtime': {
          'onSince': DateTime.now().millisecondsSinceEpoch - 999000,
        },
      });
      expect(device.secondsUntilCutoff, 0);
    });

    test('is null when the device is off or not armed', () {
      final off = Device.fromMap('ironLaundry', {
        'type': 'hazard',
        'status': 'OFF',
        'config': {'maxOnDurationSec': 30},
      });
      expect(off.secondsUntilCutoff, isNull);

      final notArmed = Device.fromMap('ironLaundry', {
        'type': 'hazard',
        'status': 'ON',
        'config': {'maxOnDurationSec': 30},
      });
      expect(notArmed.secondsUntilCutoff, isNull);
    });

    test('is null for non-hazard devices', () {
      final bulb = Device.fromMap('bulbPorch', {'type': 'bulb', 'status': 'ON'});
      expect(bulb.secondsUntilCutoff, isNull);
    });
  });

  group('serialisation', () {
    test('toMap never includes runtime, which is server-owned', () {
      final device = Device.fromMap('ironLaundry', {
        'type': 'hazard',
        'status': 'ON',
        'config': {'maxOnDurationSec': 30},
        'runtime': {'onSince': 1234567890},
      });
      expect(device.onSince, 1234567890);
      // Security rules reject client writes to runtime, so a payload containing
      // it would fail the whole update.
      expect(device.toMap().containsKey('runtime'), isFalse);
    });

    test('handles numbers arriving as double', () {
      // Firebase returns whole numbers as int or double depending on how they
      // were written by whichever client wrote them.
      final device = Device.fromMap('d', {
        'type': 'outlet',
        'cell': {'x': 3.0, 'y': 5.0},
      });
      expect(device.cell, const GridCell(3, 5));
    });
  });

  group('UsageDay', () {
    test('converts seconds to hours for charting', () {
      final day = UsageDay.fromMap('2026-08-14', {
        'onSeconds': 5400,
        'toggleCount': 3,
      });
      expect(day.onHours, 1.5);
    });
  });
}
