/// Multi-floor view: pick a floor, see its plan with devices placed on the grid.
///
/// Floors are ordered by their `order` field rather than by key, because the
/// storey order of a building is real information the database has to carry —
/// map iteration order is arbitrary and would shuffle "Ground / First / Roof"
/// into nonsense.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/device.dart';
import '../../data/providers.dart';
import '../camera/camera_screen.dart';
import '../devices/channel_sheet.dart';
import '../devices/device_editor_sheet.dart';
import 'floor_plan_view.dart';

/// The plan images bundled with the app.
///
/// A fixed list rather than a file picker: the images must be declared in
/// `pubspec.yaml` to exist in the bundle at all, so offering arbitrary paths
/// would let a user create a floor whose plan can never load.
const planAssetChoices = <(String, String)>[
  ('assets/plans/ground.png', 'Ground'),
  ('assets/plans/first.png', 'Upper storey'),
  ('assets/plans/roof.png', 'Roof / terrace'),
];

class FloorsScreen extends ConsumerWidget {
  const FloorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floors = ref.watch(floorsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Floor plans'),
        actions: [
          IconButton(
            tooltip: 'Manage floors',
            icon: const Icon(Icons.layers_outlined),
            onPressed: () => _openFloorManager(context),
          ),
        ],
      ),
      body: floors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Could not load floors.\n\n$error',
                textAlign: TextAlign.center),
          ),
        ),
        data: (list) {
          if (list.isEmpty) return const _NoFloors();
          return _FloorPager(floors: list);
        },
      ),
    );
  }

  static void _openFloorManager(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FloorManagerScreen()),
    );
  }
}

class _FloorPager extends ConsumerStatefulWidget {
  const _FloorPager({required this.floors});

  final List<Floor> floors;

  @override
  ConsumerState<_FloorPager> createState() => _FloorPagerState();
}

class _FloorPagerState extends ConsumerState<_FloorPager> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // Clamped because a floor can be deleted from under this screen while it is
    // open — the stream then emits a shorter list and the old index dangles.
    final index = _index.clamp(0, widget.floors.length - 1);
    final floor = widget.floors[index];
    final devices = ref.watch(devicesProviderFor(floor.id));

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: widget.floors.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ChoiceChip(
                label: Text(widget.floors[i].name),
                selected: i == index,
                onSelected: (_) => setState(() => _index = i),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: devices.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (list) => _PlanBody(floor: floor, devices: list),
          ),
        ),
      ],
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.floor, required this.devices});

  final Floor floor;
  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Pinch-zoom, because a 10x8 grid on a phone gives cells about 35px
        // wide and a fingertip is roughly 45px. Without zoom the corner cells
        // are genuinely hard to hit.
        InteractiveViewer(
          maxScale: 4,
          child: Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: FloorPlanView(
              floor: floor,
              devices: devices,
              onDeviceTap: (device) => _openDevice(context, device),
              onEmptyCellTap: (cell) => showDeviceEditor(
                context,
                floorId: floor.id,
                cell: cell,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${floor.cols} × ${floor.rows} grid · ${devices.length} devices · '
          'drag a marker to move it, tap an empty cell to add',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  static void _openDevice(BuildContext context, Device device) {
    switch (device.type) {
      case DeviceType.multiswitch:
        showChannelSheet(context, device.id);
      case DeviceType.camera:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CameraScreen(deviceId: device.id)),
        );
      default:
        showDeviceEditor(context, floorId: device.floorId, existing: device);
    }
  }
}

class _NoFloors extends ConsumerWidget {
  const _NoFloors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('No floors yet.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FloorManagerScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add a floor'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- management

/// Add, rename, reorder and delete floors.
class FloorManagerScreen extends ConsumerWidget {
  const FloorManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floors = ref.watch(floorsProvider).value ?? const <Floor>[];
    final repo = ref.read(homeRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage floors')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, nextOrder: floors.length),
        icon: const Icon(Icons.add),
        label: const Text('Add floor'),
      ),
      body: ReorderableListView.builder(
        itemCount: floors.length,
        padding: const EdgeInsets.only(bottom: 88),
        // onReorderItem, not the deprecated onReorder: it already compensates
        // for the item having been removed at oldIndex, so newIndex is the
        // final position and needs no manual -1 adjustment.
        onReorderItem: (oldIndex, newIndex) async {
          final reordered = [...floors];
          reordered.insert(newIndex, reordered.removeAt(oldIndex));
          // Rewrite every `order` rather than just the two that moved: the
          // values have to stay a dense 0..n-1 sequence or a later insert can
          // collide and two floors end up sorting equal.
          for (var i = 0; i < reordered.length; i++) {
            final floor = reordered[i];
            if (floor.order == i) continue;
            await repo.upsertFloor(
              Floor(
                id: floor.id,
                name: floor.name,
                order: i,
                planAsset: floor.planAsset,
                cols: floor.cols,
                rows: floor.rows,
              ),
            );
          }
        },
        itemBuilder: (context, i) {
          final floor = floors[i];
          return ListTile(
            key: ValueKey(floor.id),
            leading: SizedBox(
              width: 56,
              height: 44,
              child: Image.asset(
                floor.planAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
              ),
            ),
            title: Text(floor.name),
            subtitle: Text('Order ${floor.order} · ${floor.cols}×${floor.rows}'),
            onTap: () => _edit(context, ref, existing: floor),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, floor),
                ),
                const Icon(Icons.drag_handle),
              ],
            ),
          );
        },
      ),
    );
  }

  static Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Floor floor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${floor.name}?'),
        // Stated plainly because it is not obvious and it is not undoable:
        // the repository deletes the floor's devices with it, otherwise they
        // become orphans no screen renders and nobody can remove.
        content: const Text(
          'Every device standing on this floor is deleted with it. '
          'This cannot be undone.',
        ),
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

    if (confirmed == true) {
      await ref.read(homeRepositoryProvider).deleteFloor(floor.id);
    }
  }

  static Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    Floor? existing,
    int nextOrder = 0,
  }) async {
    final nameController =
        TextEditingController(text: existing?.name ?? '');
    var asset = existing?.planAsset ?? planAssetChoices.first.$1;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Add floor' : 'Edit floor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Floor name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Plan image'),
              ),
              const SizedBox(height: 8),
              for (final choice in planAssetChoices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => setState(() => asset = choice.$1),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 38,
                          child: Image.asset(choice.$1, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(choice.$2)),
                        Icon(
                          asset == choice.$1
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final name = nameController.text.trim();
    nameController.dispose();
    if (saved != true || name.isEmpty) return;

    await ref.read(homeRepositoryProvider).upsertFloor(
          Floor(
            id: existing?.id ??
                'floor${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            order: existing?.order ?? nextOrder,
            planAsset: asset,
            // The grid is frozen at 10x8 across the project — the app, the
            // seed script and the simulator all assume it.
            cols: existing?.cols ?? 10,
            rows: existing?.rows ?? 8,
          ),
        );
  }
}
