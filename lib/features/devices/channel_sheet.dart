/// Channel controls for a multi-switch.
///
/// A gang box is one physical unit with N independently addressable switches, so
/// it gets one tile on the dashboard and its channels live one level down. The
/// alternative — flattening every channel into the device list — would misreport
/// the house as having more devices than it has.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/device.dart';
import '../../data/providers.dart';
import '../../app/theme.dart';
import 'optimistic_toggle.dart';
import 'status_chip.dart';

Future<void> showChannelSheet(BuildContext context, String deviceId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ChannelSheet(deviceId: deviceId),
  );
}

class _ChannelSheet extends ConsumerWidget {
  const _ChannelSheet({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, not passed in: the sheet stays open while the worker, the
    // simulator or another phone changes these channels, and it should show that
    // happening rather than a snapshot from when it opened.
    final device = ref.watch(deviceProvider(deviceId)).value;
    final pending = ref.watch(pendingTogglesProvider);

    if (device == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('This device is no longer available.')),
      );
    }

    final reachable = device.effectiveStatus.isControllable;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    device.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StatusChip(status: device.effectiveStatus),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _summary(device),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            for (final channel in device.channels)
              _ChannelRow(
                deviceId: deviceId,
                channel: channel,
                enabled: reachable,
                pending: pending[
                    PendingToggles.channelKey(deviceId, channel.index)],
              ),
            if (!reachable) ...[
              const SizedBox(height: 12),
              Text(
                device.online
                    ? 'This unit is reporting a fault, so its channels cannot be switched.'
                    : 'This unit is offline. Channels cannot be switched until it reconnects.',
                style: TextStyle(color: statusColour(device.effectiveStatus)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _summary(Device device) {
    final on = device.channels.where((c) => c.state.isOn).length;
    return '$on of ${device.channels.length} channels on · '
        'the unit reads ON if any one of them is';
  }
}

class _ChannelRow extends ConsumerWidget {
  const _ChannelRow({
    required this.deviceId,
    required this.channel,
    required this.enabled,
    required this.pending,
  });

  final String deviceId;
  final DeviceChannel channel;
  final bool enabled;
  final DeviceStatus? pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pending intent wins over the stream until the write settles.
    final shown = pending ?? channel.state;

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(channel.label),
      subtitle: Text('Channel ${channel.index}'),
      value: shown.isOn,
      onChanged: enabled
          ? (value) async {
              final target = value ? DeviceStatus.on : DeviceStatus.off;
              final repo = ref.read(homeRepositoryProvider);
              await optimisticToggle(
                ref: ref,
                context: context,
                pendingKey:
                    PendingToggles.channelKey(deviceId, channel.index),
                target: target,
                description: channel.label,
                write: () =>
                    repo.setChannel(deviceId, channel.index, target),
              );
            }
          : null,
    );
  }
}
