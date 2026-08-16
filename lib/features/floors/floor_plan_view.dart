/// The floor plan with its abstract grid overlay.
///
/// This is the core of the "floor representation" requirement, and the whole
/// design rests on one decision: **a device's position is an integer cell index,
/// never a pixel coordinate.**
///
/// Pixels would be wrong. The plan image is rendered at whatever size the screen
/// gives it — a 6" phone, a tablet, landscape, a split-screen window — so a
/// device pinned at (240, 175) on the device it was placed on lands somewhere
/// else on every other one. Storing `cell: {x: 3, y: 5}` and multiplying by the
/// *current* cell size at paint time makes placement resolution-independent for
/// free, and it is also what lets the web simulator render the same house from
/// the same numbers using `left: calc(x * 10%)`.
///
/// The grid is `cols × rows` from the floor record (10 × 8, frozen in the
/// schema), so the aspect ratio is fixed at 1.25 and the plan image is never
/// distorted relative to the grid drawn on top of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/device.dart';
import '../../data/providers.dart';

class FloorPlanView extends ConsumerStatefulWidget {
  const FloorPlanView({
    super.key,
    required this.floor,
    required this.devices,
    this.onDeviceTap,
    this.onEmptyCellTap,
  });

  final Floor floor;
  final List<Device> devices;
  final void Function(Device device)? onDeviceTap;
  final void Function(GridCell cell)? onEmptyCellTap;

  @override
  ConsumerState<FloorPlanView> createState() => _FloorPlanViewState();
}

class _FloorPlanViewState extends ConsumerState<FloorPlanView> {
  /// Anchors the coordinate conversion. A drop reports a *global* position, and
  /// this is the render object it has to be measured against.
  final _planKey = GlobalKey();

  /// The cell currently hovered during a drag, so the target is visible before
  /// the finger lifts. Purely presentational.
  GridCell? _hoveredCell;

  GridCell? _cellAt(Offset globalPosition) {
    final box = _planKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final local = box.globalToLocal(globalPosition);
    final cellWidth = box.size.width / widget.floor.cols;
    final cellHeight = box.size.height / widget.floor.rows;

    return GridCell(
      (local.dx / cellWidth).floor().clamp(0, widget.floor.cols - 1),
      (local.dy / cellHeight).floor().clamp(0, widget.floor.rows - 1),
    );
  }

  Future<void> _move(Device device, GridCell cell) async {
    if (device.cell == cell) return;

    final messenger = ScaffoldMessenger.of(context);
    // Occupancy is a UI rule, not a schema rule — the database would happily
    // hold two devices in one cell, but they would render on top of each other
    // and the lower one would be unreachable.
    final occupied = widget.devices.any(
      (d) => d.id != device.id && d.cell == cell,
    );
    if (occupied) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That cell is already taken.')),
      );
      return;
    }

    try {
      await ref.read(homeRepositoryProvider).moveDevice(device.id, cell);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't move ${device.name}: $error")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final floor = widget.floor;

    return AspectRatio(
      // Locked to the grid, not to the image. If a replacement plan image has a
      // different aspect ratio it gets letterboxed by BoxFit.contain rather than
      // shearing the grid away from the walls underneath it.
      aspectRatio: floor.cols / floor.rows,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / floor.cols;
          final cellHeight = constraints.maxHeight / floor.rows;

          return DragTarget<Device>(
            onMove: (details) {
              final cell = _cellAt(details.offset);
              if (cell != _hoveredCell) setState(() => _hoveredCell = cell);
            },
            onLeave: (_) => setState(() => _hoveredCell = null),
            onAcceptWithDetails: (details) {
              final cell = _cellAt(details.offset);
              setState(() => _hoveredCell = null);
              if (cell != null) _move(details.data, cell);
            },
            builder: (context, _, _) {
              return Stack(
                key: _planKey,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      floor.planAsset,
                      fit: BoxFit.contain,
                      // A missing plan asset must not take the screen down —
                      // planAsset is a free-text path in the database and a
                      // typo there is a data problem, not a crash.
                      errorBuilder: (context, _, _) => ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const Center(
                          child: Text('Floor plan image missing'),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridPainter(
                        cols: floor.cols,
                        rows: floor.rows,
                        colour: Theme.of(context).colorScheme.outline,
                        highlight: _hoveredCell,
                        highlightColour:
                            Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  // Tap layer for empty cells, underneath the markers so a tap
                  // on a device reaches the device.
                  if (widget.onEmptyCellTap != null)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final cell = _cellAt(details.globalPosition);
                          if (cell == null) return;
                          final taken =
                              widget.devices.any((d) => d.cell == cell);
                          if (!taken) widget.onEmptyCellTap!(cell);
                        },
                      ),
                    ),
                  for (final device in widget.devices)
                    Positioned(
                      left: device.cell.x * cellWidth,
                      top: device.cell.y * cellHeight,
                      width: cellWidth,
                      height: cellHeight,
                      child: _DeviceMarker(
                        device: device,
                        size: cellWidth < cellHeight ? cellWidth : cellHeight,
                        onTap: () => widget.onDeviceTap?.call(device),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// A device pinned to its cell.
///
/// Draggable with [pointerDragAnchorStrategy] so the feedback widget's origin is
/// the finger itself. That makes the drop coordinate exactly the pointer
/// position, instead of the top-left corner of a floating widget whose size the
/// drop handler would otherwise have to compensate for.
class _DeviceMarker extends StatelessWidget {
  const _DeviceMarker({
    required this.device,
    required this.size,
    required this.onTap,
  });

  final Device device;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final marker = _MarkerBody(device: device, size: size);

    return Draggable<Device>(
      data: device,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        // Re-centre the visual on the finger; the *data* anchor stays at the
        // pointer, which is what the cell maths wants.
        offset: Offset(-size / 2, -size / 2),
        child: Opacity(
          opacity: 0.9,
          child: _MarkerBody(device: device, size: size, dragging: true),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: marker),
      child: GestureDetector(onTap: onTap, child: marker),
    );
  }
}

class _MarkerBody extends StatelessWidget {
  const _MarkerBody({
    required this.device,
    required this.size,
    this.dragging = false,
  });

  final Device device;
  final double size;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final status = device.effectiveStatus;
    final colour = statusColour(status);
    final diameter = size * 0.62;

    return Center(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: colour,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dragging ? 0.4 : 0.25),
              blurRadius: dragging ? 10 : 4,
              offset: Offset(0, dragging ? 4 : 2),
            ),
          ],
        ),
        child: Icon(
          deviceIcon(device.type),
          size: diameter * 0.6,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.cols,
    required this.rows,
    required this.colour,
    required this.highlightColour,
    this.highlight,
  });

  final int cols;
  final int rows;
  final Color colour;
  final Color highlightColour;
  final GridCell? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / cols;
    final cellHeight = size.height / rows;

    final line = Paint()
      ..color = colour.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    // Interior lines only — the outer edge is the image boundary and drawing
    // over it just thickens the wall that is already there.
    for (var i = 1; i < cols; i++) {
      final dx = i * cellWidth;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), line);
    }
    for (var j = 1; j < rows; j++) {
      final dy = j * cellHeight;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), line);
    }

    final cell = highlight;
    if (cell != null) {
      final rect = Rect.fromLTWH(
        cell.x * cellWidth,
        cell.y * cellHeight,
        cellWidth,
        cellHeight,
      );
      canvas.drawRect(
        rect,
        Paint()..color = highlightColour.withValues(alpha: 0.25),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = highlightColour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cols != cols ||
      old.rows != rows ||
      old.colour != colour ||
      old.highlight != highlight;
}
