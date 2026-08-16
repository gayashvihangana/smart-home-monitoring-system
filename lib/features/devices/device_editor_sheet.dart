/// Create or edit a device, including the per-type configuration.
///
/// One sheet handles all five types rather than five screens, because the fields
/// that differ are a small tail on a common head (name, type, cell) and the
/// per-type parts are mutually exclusive — only one of them is ever on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/device.dart';
import '../../data/providers.dart';

Future<void> showDeviceEditor(
  BuildContext context, {
  required String floorId,
  GridCell? cell,
  Device? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      // Lifts the sheet above the keyboard; without it the name field is under
      // the keyboard on a short phone and cannot be seen while typing.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _DeviceEditor(
        floorId: floorId,
        cell: cell ?? existing?.cell ?? const GridCell(0, 0),
        existing: existing,
      ),
    ),
  );
}

class _DeviceEditor extends ConsumerStatefulWidget {
  const _DeviceEditor({
    required this.floorId,
    required this.cell,
    this.existing,
  });

  final String floorId;
  final GridCell cell;
  final Device? existing;

  @override
  ConsumerState<_DeviceEditor> createState() => _DeviceEditorState();
}

class _DeviceEditorState extends ConsumerState<_DeviceEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');

  late DeviceType _type = widget.existing?.type ?? DeviceType.outlet;
  late int _channelCount = widget.existing?.channels.length.clamp(2, 5) ?? 3;
  late int _maxOnDurationSec = widget.existing?.maxOnDurationSec ?? 30;
  late DeviceSchedule _schedule =
      widget.existing?.schedule ?? DeviceSchedule.empty;

  bool _busy = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Channel labels are preserved across a count change where they exist, so
  /// bumping a 2-gang box to 3 does not wipe the two names already entered.
  List<DeviceChannel> _buildChannels() {
    final previous = widget.existing?.channels ?? const <DeviceChannel>[];
    return [
      for (var i = 0; i < _channelCount; i++)
        DeviceChannel(
          index: i,
          label: i < previous.length ? previous[i].label : 'Switch ${i + 1}',
          state: i < previous.length ? previous[i].state : DeviceStatus.off,
        ),
    ];
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the device a name.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final navigator = Navigator.of(context);
    final device = Device(
      id: widget.existing?.id ??
          '${_type.wire}${DateTime.now().millisecondsSinceEpoch}',
      floorId: widget.floorId,
      name: name,
      type: _type,
      cell: widget.cell,
      status: widget.existing?.status ?? DeviceStatus.off,
      channels: _type == DeviceType.multiswitch
          ? _buildChannels()
          : const <DeviceChannel>[],
      maxOnDurationSec:
          _type == DeviceType.hazard ? _maxOnDurationSec : null,
      schedule: _type == DeviceType.bulb ? _schedule : null,
      // Mock endpoints, as the spec allows. Seeded per device id so two cameras
      // do not show the same picture.
      snapshotUri: _type == DeviceType.camera
          ? widget.existing?.snapshotUri ??
              'https://picsum.photos/seed/${name.hashCode.toUnsigned(16)}/640/360'
          : null,
      streamUri: _type == DeviceType.camera
          ? widget.existing?.streamUri ??
              'https://example.com/mock/stream/${name.hashCode.toUnsigned(16)}.m3u8'
          : null,
    );

    try {
      await ref.read(homeRepositoryProvider).upsertDevice(device);
      navigator.pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _delete() async {
    final device = widget.existing;
    if (device == null) return;

    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${device.name}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(homeRepositoryProvider).deleteDevice(device.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isNew ? 'Add device' : 'Edit device',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.grid_4x4, size: 16),
                  label: Text('cell ${widget.cell.x}, ${widget.cell.y}'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Type', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final type in DeviceType.values)
                  ChoiceChip(
                    avatar: Icon(deviceIcon(type), size: 18),
                    label: Text(_typeLabel(type)),
                    selected: _type == type,
                    onSelected:
                        _busy ? null : (_) => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ..._typeFields(theme),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (!_isNew) ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isNew ? 'Add device' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _typeFields(ThemeData theme) {
    switch (_type) {
      case DeviceType.multiswitch:
        return [
          Text('Channels', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'One gang box, N individually addressable switches. '
            'The unit reads ON if any one channel is on.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final n in const [2, 3, 5])
                ChoiceChip(
                  label: Text('$n'),
                  selected: _channelCount == n,
                  onSelected:
                      _busy ? null : (_) => setState(() => _channelCount = n),
                ),
            ],
          ),
        ];

      case DeviceType.hazard:
        return [
          Text('Maximum active duration', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Enforced server-side by the safety worker, so it still fires when '
            'this app is closed. Short values here are for the demo — '
            'production values would be minutes.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final seconds in const [30, 60, 300, 900])
                ChoiceChip(
                  label: Text(_durationLabel(seconds)),
                  selected: _maxOnDurationSec == seconds,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _maxOnDurationSec = seconds),
                ),
            ],
          ),
        ];

      case DeviceType.bulb:
        return [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatic schedule'),
            subtitle: const Text('The worker turns the bulb on and off'),
            value: _schedule.enabled,
            onChanged: _busy
                ? null
                : (value) => setState(() => _schedule = _copySchedule(
                      _schedule,
                      enabled: value,
                    )),
          ),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'On at',
                  value: _schedule.onAt,
                  enabled: !_busy && _schedule.enabled,
                  onChanged: (v) => setState(
                      () => _schedule = _copySchedule(_schedule, onAt: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  label: 'Off at',
                  value: _schedule.offAt,
                  enabled: !_busy && _schedule.enabled,
                  onChanged: (v) => setState(
                      () => _schedule = _copySchedule(_schedule, offAt: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Days', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(_dayLabel(day)),
                  selected: _schedule.days.contains(day),
                  onSelected: !_busy && _schedule.enabled
                      ? (selected) {
                          final days = [..._schedule.days];
                          if (selected) {
                            days.add(day);
                          } else {
                            days.remove(day);
                          }
                          days.sort();
                          setState(() =>
                              _schedule = _copySchedule(_schedule, days: days));
                        }
                      : null,
                ),
            ],
          ),
        ];

      case DeviceType.camera:
        return [
          Text(
            'Mock snapshot and stream endpoints are generated automatically, '
            'as the spec permits. Open the device from the floor plan to view it.',
            style: theme.textTheme.bodySmall,
          ),
        ];

      case DeviceType.outlet:
        return [
          Text(
            'A simple binary node — on or off, nothing to configure.',
            style: theme.textTheme.bodySmall,
          ),
        ];
    }
  }

  static DeviceSchedule _copySchedule(
    DeviceSchedule base, {
    bool? enabled,
    String? onAt,
    String? offAt,
    List<int>? days,
  }) {
    return DeviceSchedule(
      enabled: enabled ?? base.enabled,
      onAt: onAt ?? base.onAt,
      offAt: offAt ?? base.offAt,
      days: days ?? base.days,
      timezone: base.timezone,
    );
  }

  static String _typeLabel(DeviceType type) => switch (type) {
        DeviceType.outlet => 'Outlet',
        DeviceType.multiswitch => 'Multi-switch',
        DeviceType.hazard => 'Hazard',
        DeviceType.bulb => 'Bulb',
        DeviceType.camera => 'Camera',
      };

  static String _durationLabel(int seconds) =>
      seconds < 60 ? '${seconds}s' : '${seconds ~/ 60} min';

  static String _dayLabel(int isoWeekday) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][isoWeekday - 1];
}

/// A "HH:mm" field backed by the platform time picker.
///
/// The stored format is always 24-hour `HH:mm` regardless of the phone's locale,
/// because the Node worker parses this string and a 12-hour value would not
/// match the security rules' regex.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled
          ? () async {
              final parts = value.split(':');
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: int.tryParse(parts.first) ?? 18,
                  minute: int.tryParse(parts.last) ?? 0,
                ),
              );
              if (picked == null) return;
              onChanged('${picked.hour.toString().padLeft(2, '0')}:'
                  '${picked.minute.toString().padLeft(2, '0')}');
            }
          : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
