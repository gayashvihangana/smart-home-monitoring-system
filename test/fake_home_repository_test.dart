import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home/data/fake_home_repository.dart';
import 'package:smart_home/data/models/device.dart';

/// The fake is what the UI is developed against while the Firebase project's
/// security rules are still locked down, so it has to behave like the real
/// repository — stream on subscribe, re-emit on write, and fail loudly when told
/// to. If it drifts, every screen built on it is being validated against
/// something that does not exist.
void main() {
  late FakeHomeRepository repo;

  setUp(() => repo = FakeHomeRepository());
  tearDown(() => repo.dispose());

  Device find(List<Device> devices, String id) =>
      devices.firstWhere((d) => d.id == id);

  group('seed data', () {
    test('mirrors tools/seed.js — 3 floors, 10 devices, all 5 types', () async {
      final floors = await repo.floors().first;
      final devices = await repo.devices().first;

      expect(floors.map((f) => f.id),
          ['floorGround', 'floorFirst', 'floorRoof']);
      // Ordered by `order`, not map iteration order.
      expect(floors.map((f) => f.name).first, 'Ground Floor');

      expect(devices, hasLength(10));
      expect(devices.map((d) => d.type).toSet(), DeviceType.values.toSet());
    });

    test('floors carry the frozen 10x8 grid and the plan asset paths', () async {
      final floors = await repo.floors().first;

      for (final floor in floors) {
        expect(floor.cols, 10);
        expect(floor.rows, 8);
        expect(floor.planAsset, startsWith('assets/plans/'));
        expect(floor.planAsset, endsWith('.png'));
      }
    });

    test('every status chip is reachable from the seed', () async {
      final devices = await repo.devices().first;
      final statuses = devices.map((d) => d.effectiveStatus).toSet();

      // Without all four present, three of the four colours would never be seen
      // during development and a broken one would ship unnoticed.
      expect(statuses, containsAll(DeviceStatus.values));
    });

    test('presence overrides stored status, as the real join does', () async {
      final devices = await repo.devices().first;
      final camera = find(devices, 'camBack');

      expect(camera.online, isFalse);
      expect(camera.status, DeviceStatus.on);
      expect(camera.effectiveStatus, DeviceStatus.disconnected);
    });
  });

  group('filtering', () {
    test('devices(floorId:) returns only that floor', () async {
      final ground = await repo.devices(floorId: 'floorGround').first;

      expect(ground, isNotEmpty);
      expect(ground.every((d) => d.floorId == 'floorGround'), isTrue);
      expect(ground.length, lessThan(10));
    });
  });

  group('writes', () {
    test('setStatus is pushed to listeners, not just stored', () async {
      final seen = repo
          .devices()
          .map((list) => find(list, 'outletLiving').status);

      final expectation = expectLater(
        seen,
        emitsInOrder([DeviceStatus.off, DeviceStatus.on]),
      );

      await repo.setStatus('outletLiving', DeviceStatus.on);
      await expectation;
    });

    test('setStatus stamps provenance so the source is always provable',
        () async {
      await repo.setStatus('outletLiving', DeviceStatus.on);
      final device = find(await repo.devices().first, 'outletLiving');

      expect(device.lastChangedBy, 'app');
      expect(device.lastChangedAt, isNotNull);
    });

    test('setChannel moves one channel and leaves its siblings alone', () async {
      await repo.setChannel('gangHallway', 1, DeviceStatus.on);
      final gang = find(await repo.devices().first, 'gangHallway');

      expect(gang.channels.map((c) => c.state.isOn), [false, true, false]);
      // The unit reads ON because one channel is — the rule all three clients
      // implement independently.
      expect(gang.isOn, isTrue);
    });
  });

  group('failNextWrite', () {
    test('throws and leaves the stored state untouched', () async {
      repo.failNextWrite = true;

      await expectLater(
        repo.setStatus('outletLiving', DeviceStatus.on),
        throwsA(isA<StateError>()),
      );

      final device = find(await repo.devices().first, 'outletLiving');
      expect(device.status, DeviceStatus.off,
          reason: 'a rejected write must not be applied locally');
    });

    test('disarms itself, so only one write fails', () async {
      repo.failNextWrite = true;
      await expectLater(
        repo.setStatus('outletLiving', DeviceStatus.on),
        throwsA(isA<StateError>()),
      );

      await repo.setStatus('outletLiving', DeviceStatus.on);
      expect(find(await repo.devices().first, 'outletLiving').status,
          DeviceStatus.on);
    });
  });

  group('hazard runtime', () {
    test('turning a hazard on arms the countdown', () async {
      await repo.setStatus('ironLaundry', DeviceStatus.on);
      final iron = find(await repo.devices().first, 'ironLaundry');

      expect(iron.onSince, isNotNull);
      expect(iron.secondsUntilCutoff, closeTo(30, 1));
    });

    test('turning it off again disarms it', () async {
      await repo.setStatus('ironLaundry', DeviceStatus.on);
      await repo.setStatus('ironLaundry', DeviceStatus.off);
      final iron = find(await repo.devices().first, 'ironLaundry');

      expect(iron.onSince, isNull);
      expect(iron.secondsUntilCutoff, isNull);
    });
  });

  group('usage', () {
    test('allUsage trims to the requested window', () async {
      final week = await repo.allUsage(days: 7).first;
      final fortnight = await repo.allUsage(days: 14).first;

      expect(week['outletLiving'], hasLength(7));
      expect(fortnight['outletLiving'], hasLength(14));
      // Trimmed from the end, so the window is the most recent days.
      expect(week['outletLiving']!.last.date, fortnight['outletLiving']!.last.date);
    });

    test('usage is deterministic, so charts do not change between runs', () async {
      final first = await repo.usage('outletLiving').first;
      final other = FakeHomeRepository();
      addTearDown(other.dispose);
      final second = await other.usage('outletLiving').first;

      expect(first.map((d) => d.onSeconds), second.map((d) => d.onSeconds));
    });
  });

  group('alerts', () {
    test('seeds one unread alert so the dashboard banner is exercised',
        () async {
      final alerts = await repo.alerts().first;

      expect(alerts, hasLength(3));
      expect(alerts.where((a) => !a.read), hasLength(1));
      // Newest first.
      expect(alerts.first.timestamp,
          greaterThan(alerts.last.timestamp));
      expect(alerts.first.isCutoff, isTrue);
    });

    test('markAlertRead clears it', () async {
      final unread = (await repo.alerts().first).firstWhere((a) => !a.read);
      await repo.markAlertRead(unread.id);

      expect((await repo.alerts().first).where((a) => !a.read), isEmpty);
    });
  });
}
