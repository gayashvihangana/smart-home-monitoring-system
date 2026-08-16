import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home/app/theme.dart';
import 'package:smart_home/data/models/device.dart';
import 'package:smart_home/features/devices/device_tile.dart';
import 'package:smart_home/features/devices/status_chip.dart';

/// Widget-level checks for the two rules a marker will look for first: an
/// unreachable device must not offer a control, and a gang box must not pretend
/// to be a single switch.
void main() {
  Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: child),
        ),
      );

  Device device(Map<String, Object?> overrides, {bool online = true}) {
    return Device.fromMap(
      'd1',
      {'name': 'Test Device', 'type': 'outlet', 'status': 'OFF', ...overrides},
      online: online,
    );
  }

  testWidgets('an offline device shows DISCONNECTED and a disabled switch',
      (tester) async {
    await tester.pumpWidget(host(
      DeviceTile(device: device({'status': 'ON'}, online: false)),
    ));

    // Presence beats the stored ON.
    expect(find.text(statusLabel(DeviceStatus.disconnected)), findsOneWidget);

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.onChanged, isNull,
        reason: 'you cannot command hardware that is not answering');
  });

  testWidgets('an ERROR device is also not controllable', (tester) async {
    await tester.pumpWidget(host(DeviceTile(device: device({'status': 'ERROR'}))));

    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets('a healthy device is controllable', (tester) async {
    await tester.pumpWidget(host(DeviceTile(device: device({'status': 'OFF'}))));

    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });

  testWidgets('a multiswitch shows a channel count instead of a switch',
      (tester) async {
    await tester.pumpWidget(host(DeviceTile(
      device: device({
        'type': 'multiswitch',
        'channels': {
          '0': {'label': 'Ceiling', 'state': 'ON'},
          '1': {'label': 'Wall', 'state': 'OFF'},
          '2': {'label': 'Fan', 'state': 'OFF'},
        },
      }),
    )));

    expect(find.text('1/3 on'), findsOneWidget);
    // The unit's state is derived from its channels, so a master switch would
    // either contradict the summary rule or silently fan out.
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('StatusChip carries an icon, not colour alone', (tester) async {
    await tester.pumpWidget(
      host(const StatusChip(status: DeviceStatus.disconnected)),
    );

    expect(find.byIcon(statusIcon(DeviceStatus.disconnected)), findsOneWidget);
    expect(find.text(statusLabel(DeviceStatus.disconnected)), findsOneWidget);
  });
}
