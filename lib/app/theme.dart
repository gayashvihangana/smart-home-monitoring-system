/// Theme and the status palette.
///
/// The four status colours are a cross-client contract, not a styling choice:
/// the Flutter app and the web simulator are shown side by side in the demo, and
/// a device that is green in one and grey in the other reads as a sync bug. They
/// are defined here once and nowhere else.
library;

import 'package:flutter/material.dart';

import '../data/models/device.dart';

/// ON green · OFF grey · ERROR red · DISCONNECTED amber.
///
/// Moved here verbatim from `main.dart`, where it lived while the app was a
/// single-file harness. `simulator/style.css` uses the same six hex digits.
Color statusColour(DeviceStatus status) => switch (status) {
      DeviceStatus.on => const Color(0xFF4CAF50),
      DeviceStatus.off => const Color(0xFF9E9E9E),
      DeviceStatus.error => const Color(0xFFF44336),
      DeviceStatus.disconnected => const Color(0xFFFFB300),
    };

/// Colour alone is not an accessible signal, so every status also carries a
/// distinct glyph. DISCONNECTED gets a slashed icon because "unreachable" and
/// "switched off" are the pair a user is most likely to confuse.
IconData statusIcon(DeviceStatus status) => switch (status) {
      DeviceStatus.on => Icons.check_circle,
      DeviceStatus.off => Icons.circle_outlined,
      DeviceStatus.error => Icons.error,
      DeviceStatus.disconnected => Icons.cloud_off,
    };

String statusLabel(DeviceStatus status) => switch (status) {
      DeviceStatus.on => 'On',
      DeviceStatus.off => 'Off',
      DeviceStatus.error => 'Error',
      DeviceStatus.disconnected => 'Offline',
    };

IconData deviceIcon(DeviceType type) => switch (type) {
      DeviceType.outlet => Icons.power,
      DeviceType.multiswitch => Icons.toggle_on_outlined,
      DeviceType.hazard => Icons.local_fire_department,
      DeviceType.bulb => Icons.lightbulb_outline,
      DeviceType.camera => Icons.videocam_outlined,
    };

ThemeData buildTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
    useMaterial3: true,
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}
