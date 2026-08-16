# Floor Representation

> **DRAFT — read this before you submit it.** Every claim below is true of the code
> in `lib/features/floors/`, but you will be asked *"why did you do it this way?"* in
> the viva about your own section. Read the two files it describes, then rewrite any
> sentence you would not say out loud unprompted.

## The problem

A house is a physical space; a phone is a rectangle of unknown size. The system has to
let a user say *"the iron is in the laundry, on the first floor"* and have that mean the
same thing on a 6-inch phone, a tablet, in landscape, and inside the web simulator
running on a laptop. Getting that mapping wrong makes every other feature unreliable,
because a control the user cannot confidently locate is a control they will not trust.

## The grid abstraction

The central decision is that **a device's position is a pair of integer grid indices,
never a pixel coordinate.**

Each floor carries its own grid in the database:

```jsonc
"floors": {
  "floorGround": {
    "name": "Ground Floor",
    "order": 0,
    "planAsset": "assets/plans/ground.png",
    "grid": { "cols": 10, "rows": 8 }
  }
}
```

and each device stores only which cell it occupies:

```jsonc
"devices": {
  "ironLaundry": { "floorId": "floorFirst", "cell": { "x": 6, "y": 6 }, … }
}
```

Pixels were rejected deliberately. A device pinned at `(240, 175)` on the phone it was
placed on lands in the wrong room on any screen of a different size, and the plan image
itself is scaled to fit the available width. Storing `cell: {x: 6, y: 6}` and
multiplying by the *current* cell size at paint time makes placement
resolution-independent for free. The same property is what lets the web simulator lay
out the identical house from the identical numbers with `left: calc(x * 10%)` — the two
clients never exchange coordinates, only agree on the grid.

The grid is fixed at **10 × 8** across all floors, so the aspect ratio is 1.25 and the
plan images are authored to match.

## Rendering

`FloorPlanView` (`lib/features/floors/floor_plan_view.dart`) composes four layers inside
an `AspectRatio` locked to `cols / rows`:

1. the plan image, `BoxFit.contain`, with an `errorBuilder` — `planAsset` is a free-text
   path in the database, so a typo there is a data problem and must not crash the screen;
2. a `CustomPainter` drawing the interior grid lines (the outer edge is the image
   boundary already, so painting it again only thickens an existing wall);
3. a transparent tap layer, which reports empty cells for placement;
4. one `Positioned` marker per device at `cell.x * cellWidth, cell.y * cellHeight`.

The aspect ratio is tied to the **grid**, not to the image. If a replacement floor plan
has different proportions it is letterboxed rather than stretched, because shearing the
image would slide the drawn grid away from the walls underneath it.

`LayoutBuilder` supplies the current dimensions, so `cellWidth` is recomputed on every
layout pass — rotation and split-screen are handled with no extra code.

## Interaction

Devices are repositioned by dragging a marker. `Draggable` is configured with
`pointerDragAnchorStrategy` so that the reported drop coordinate is the fingertip
itself, rather than the top-left corner of a floating widget whose size the drop handler
would otherwise have to subtract back out; the global position is converted through the
plan's `RenderBox` and floor-divided by the cell size. The hovered cell is highlighted
during the drag so the target is visible before the finger lifts.

Cell occupancy is enforced in the UI rather than in the schema. The database would
happily store two devices in one cell, but they would render on top of each other and
the lower one would be permanently unreachable.

The plan sits inside an `InteractiveViewer`. On a typical phone a 10 × 8 grid gives cells
roughly 35 px wide against a fingertip of about 45 px, so pinch-zoom is an accessibility
requirement, not a flourish.

Each marker is coloured by the device's **effective** status, so `DISCONNECTED` (derived
from presence) is visible directly on the floor plan.

## Limitations

- The three bundled plans are placeholders authored for this submission; a production
  system would let a user import their own image and calibrate the grid to it.
- The grid is fixed at 10 × 8. The schema already carries `cols` and `rows` per floor and
  the rendering code reads them, so variable grids are a UI affordance away — but no
  screen currently edits those values.
- Placement is one device per cell. A real room can hold two sockets on one wall.
- There is no rotation or free-form placement within a cell; a device sits at the centre
  of the cell it occupies.
