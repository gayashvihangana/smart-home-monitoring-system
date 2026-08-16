/// One device on the dashboard.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/device.dart';
import '../../data/providers.dart';
import 'channel_sheet.dart';
import 'optimistic_toggle.dart';
import 'status_chip.dart';

class DeviceTile extends ConsumerWidget {
  const DeviceTile({super.key, required this.device});

  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingKey = PendingToggles.deviceKey(device.id);
    final pending = ref.watch(pendingTogglesProvider)[pendingKey];

    // Presence beats stored status, always — a device nobody can reach is not
    // "off", and showing it as off would invite the user to "turn it on" and
    // watch nothing happen.
    final status = device.effectiveStatus;
    final isMultiswitch = device.type == DeviceType.multiswitch;

    // The pending intent overrides the stream, which is what makes the switch
    // move on the frame the finger lifts instead of one round trip later.
    final shownOn = pending?.isOn ?? device.isOn;
    final colour = statusColour(status);

    return ListTile(
      onTap: isMultiswitch ? () => showChannelSheet(context, device.id) : null,
      leading: CircleAvatar(
        backgroundColor: colour.withValues(alpha: 0.15),
        foregroundColor: colour,
        child: Icon(deviceIcon(device.type)),
      ),
      title: Text(
        device.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            StatusChip(status: status, dense: true),
            const SizedBox(width: 8),
            Expanded(
              child: _Detail(device: device),
            ),
          ],
        ),
      ),
      trailing: isMultiswitch
          ? _ChannelCount(device: device)
          : Switch(
              value: shownOn,
              // ERROR and DISCONNECTED are not actionable. Offering a switch
              // that cannot reach the hardware would be a lie the UI tells.
              onChanged: status.isControllable
                  ? (value) async {
                      final target =
                          value ? DeviceStatus.on : DeviceStatus.off;
                      final repo = ref.read(homeRepositoryProvider);
                      await optimisticToggle(
                        ref: ref,
                        context: context,
                        pendingKey: pendingKey,
                        target: target,
                        description: device.name,
                        write: () => repo.setStatus(device.id, target),
                      );
                    }
                  : null,
            ),
    );
  }
}

/// The one-line explanation under the status chip, chosen per device type
/// because the interesting fact about a hazard is not the interesting fact about
/// a bulb.
class _Detail extends StatelessWidget {
  const _Detail({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;

    if (device.isHazard && device.secondsUntilCutoff != null) {
      return _CutoffCountdown(device: device);
    }

    final text = switch (device.type) {
      DeviceType.hazard when device.maxOnDurationSec != null =>
        'Safety cutoff after ${_duration(device.maxOnDurationSec!)}',
      DeviceType.bulb when device.schedule?.enabled == true =>
        'Scheduled ${device.schedule!.onAt}–${device.schedule!.offAt}',
      DeviceType.camera => 'Snapshot available',
      DeviceType.multiswitch => 'Tap to open channels',
      _ => device.lastChangedBy == null
          ? ''
          : 'Last changed by ${device.lastChangedBy}',
    };

    return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  static String _duration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    return minutes < 60 ? '${minutes}m' : '${minutes ~/ 60}h';
  }
}

/// Live countdown to the server-side safety cutoff.
///
/// Stateful and self-contained so that ticking once a second rebuilds these few
/// words and nothing else — putting the timer higher up would rebuild the whole
/// device list every second for a label most tiles do not show.
///
/// Display only. The cutoff itself runs in the Node worker, so it still fires
/// when this app is closed or the phone is dead.
class _CutoffCountdown extends StatefulWidget {
  const _CutoffCountdown({required this.device});

  final Device device;

  @override
  State<_CutoffCountdown> createState() => _CutoffCountdownState();
}

class _CutoffCountdownState extends State<_CutoffCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.device.secondsUntilCutoff;
    if (remaining == null) {
      return Text(
        'Safety cutoff armed',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final colour = statusColour(
      remaining <= 10 ? DeviceStatus.error : DeviceStatus.on,
    );

    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 14, color: colour),
        const SizedBox(width: 4),
        Text(
          'Auto off in ${remaining}s',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colour, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// A gang box gets a count and a chevron rather than a switch.
///
/// Deliberate: the unit's state is *derived* — ON if any channel is on — so it
/// is not independently settable. A master switch here would either write a
/// status the summary rule immediately contradicts, or silently fan out to
/// channels the user never asked to change.
class _ChannelCount extends StatelessWidget {
  const _ChannelCount({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final on = device.channels.where((c) => c.state.isOn).length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$on/${device.channels.length} on',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}
