/// The one place a device status becomes pixels.
///
/// Every screen uses this rather than colouring text itself, so the four states
/// are guaranteed to look identical wherever they appear — and so changing the
/// palette is a one-file edit that cannot be applied inconsistently.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/device.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});

  final DeviceStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colour = statusColour(status);
    final scale = dense ? 0.85 : 1.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8 * scale,
        vertical: 3 * scale,
      ),
      decoration: BoxDecoration(
        // Tinted rather than solid: a saturated block next to a Switch competes
        // with it for attention, and the chip is the label, not the control.
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Colour alone fails for the ~8% of men with a colour vision
          // deficiency, and green/amber is exactly the pair they lose. The icon
          // carries the same information independently.
          Icon(statusIcon(status), size: 14 * scale, color: colour),
          SizedBox(width: 5 * scale),
          Text(
            statusLabel(status),
            style: TextStyle(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}
