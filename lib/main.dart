/// Entry point.
///
/// NOTE FOR MEMBER A: the screen below is a temporary harness, not the app UI.
/// It exists to prove the data layer streams and writes correctly, and to give
/// you something running to build on. Replace `_DataLayerHarness` with the real
/// dashboard — the Firebase setup and ProviderScope above it are the parts worth
/// keeping.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/models/device.dart';
import 'data/providers.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: SmartHomeApp()));
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const _DataLayerHarness(),
    );
  }
}

/// Status colours, fixed across the whole project so the app and the web
/// simulator never disagree on screen.
Color statusColour(DeviceStatus status) => switch (status) {
      DeviceStatus.on => const Color(0xFF4CAF50),
      DeviceStatus.off => const Color(0xFF9E9E9E),
      DeviceStatus.error => const Color(0xFFF44336),
      DeviceStatus.disconnected => const Color(0xFFFFB300),
    };

class _DataLayerHarness extends ConsumerWidget {
  const _DataLayerHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(allDevicesProvider);
    final unread = ref.watch(unreadAlertCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data layer harness'),
        actions: [
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(
                label: Text('$unread alerts'),
                backgroundColor: statusColour(DeviceStatus.error),
                labelStyle: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No devices. Run tools/seed.js.'))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _DeviceRow(device: list[i]),
              ),
      ),
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  const _DeviceRow({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(homeRepositoryProvider);
    final status = device.effectiveStatus;
    final cutoff = device.secondsUntilCutoff;

    return ListTile(
      leading: CircleAvatar(backgroundColor: statusColour(status), radius: 8),
      title: Text(device.name),
      subtitle: Text(
        [
          device.type.wire,
          status.wire,
          if (device.channels.isNotEmpty) '${device.channels.length} channels',
          if (cutoff != null) 'cutoff in ${cutoff}s',
          if (device.lastChangedBy != null) 'by ${device.lastChangedBy}',
        ].join(' · '),
      ),
      trailing: Switch(
        value: device.isOn,
        // ERROR and DISCONNECTED are not actionable — the device is not
        // answering, so offering a toggle would be a lie.
        onChanged: status.isControllable
            ? (value) => repo.setStatus(
                  device.id,
                  value ? DeviceStatus.on : DeviceStatus.off,
                )
            : null,
      ),
    );
  }
}
