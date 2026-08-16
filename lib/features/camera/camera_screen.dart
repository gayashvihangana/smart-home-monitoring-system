/// Security camera view — mock snapshots and a mock stream URI, as the spec
/// permits.
///
/// There is no real video decoding here and the report says so. What is real is
/// the part that would still be real with a physical camera: the snapshot is
/// re-fetched on a timer, every load has an explicit loading and error branch,
/// and the device's own presence still governs whether the feed is claimed to be
/// live. A camera that is offline must not show a stale frame with a LIVE badge
/// over it — that is worse than showing nothing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../data/models/device.dart';
import '../../data/providers.dart';
import '../devices/status_chip.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  Timer? _refresh;

  /// Appended to the snapshot URL as `?t=`. Without it the image is served from
  /// the Flutter image cache forever and the "live" feed is a single frozen
  /// frame — the cache key is the URL, so the URL has to change.
  int _cacheBuster = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() => _cacheBuster = DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider(widget.deviceId)).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(device?.name ?? 'Camera'),
        actions: [
          if (device != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: StatusChip(status: device.effectiveStatus, dense: true),
              ),
            ),
        ],
      ),
      body: device == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Viewfinder(
                  device: device,
                  cacheBuster: _cacheBuster,
                  onTap: () => _openFullScreen(context, device),
                ),
                const SizedBox(height: 16),
                _Meta(device: device),
              ],
            ),
    );
  }

  static void _openFullScreen(BuildContext context, Device device) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenCamera(device: device),
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.device,
    required this.cacheBuster,
    required this.onTap,
  });

  final Device device;
  final int cacheBuster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = device.effectiveStatus == DeviceStatus.on;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (device.snapshotUri != null)
                CameraSnapshot(
                  uri: device.snapshotUri!,
                  cacheBuster: cacheBuster,
                )
              else
                const Center(
                  child: Text('No snapshot endpoint configured',
                      style: TextStyle(color: Colors.white70)),
                ),
              Positioned(
                top: 10,
                left: 10,
                child: _Badge(
                  // Presence decides this, not the stored status. A camera the
                  // house cannot reach is not live no matter what the database
                  // last recorded.
                  label: live ? 'LIVE' : 'OFFLINE',
                  colour: statusColour(device.effectiveStatus),
                ),
              ),
              const Positioned(
                bottom: 10,
                right: 10,
                child: Icon(Icons.fullscreen, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The snapshot itself, with both branches the spec asks for.
///
/// `loadingBuilder` and `errorBuilder` are not decoration: this is a network
/// image on a phone that may be on mobile data or behind a captive portal, and
/// the default behaviour for a failed `Image.network` is a bare exception box.
class CameraSnapshot extends StatelessWidget {
  const CameraSnapshot({
    super.key,
    required this.uri,
    required this.cacheBuster,
  });

  final String uri;
  final int cacheBuster;

  @override
  Widget build(BuildContext context) {
    final separator = uri.contains('?') ? '&' : '?';

    return Image.network(
      '$uri${separator}t=$cacheBuster',
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: progress.expectedTotalBytes == null
                ? null
                : progress.cumulativeBytesLoaded /
                    progress.expectedTotalBytes!,
          ),
        );
      },
      errorBuilder: (context, error, _) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, color: Colors.white54, size: 40),
            SizedBox(height: 8),
            Text('Snapshot unavailable',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 8, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final changed = device.lastChangedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Endpoints', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _Row(label: 'Snapshot', value: device.snapshotUri ?? '—'),
        _Row(label: 'Stream', value: device.streamUri ?? '—'),
        _Row(
          label: 'Last change',
          value: changed == null
              ? '—'
              : '${DateFormat('d MMM, HH:mm').format(
                  DateTime.fromMillisecondsSinceEpoch(changed),
                )} by ${device.lastChangedBy ?? 'unknown'}',
        ),
        const SizedBox(height: 16),
        Text(
          'Mock endpoints. The spec permits mock snapshots and mock URI '
          'streams; no video is decoded and the stream URI is not played. '
          'Stated as a limitation in the report.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen view, kept landscape-friendly by just letting the image fill.
class _FullScreenCamera extends StatefulWidget {
  const _FullScreenCamera({required this.device});

  final Device device;

  @override
  State<_FullScreenCamera> createState() => _FullScreenCameraState();
}

class _FullScreenCameraState extends State<_FullScreenCamera> {
  Timer? _refresh;
  int _cacheBuster = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() => _cacheBuster = DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final live = device.effectiveStatus == DeviceStatus.on;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (device.snapshotUri != null)
            InteractiveViewer(
              maxScale: 4,
              child: CameraSnapshot(
                uri: device.snapshotUri!,
                cacheBuster: _cacheBuster,
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _Badge(
                    label: live ? 'LIVE' : 'OFFLINE',
                    colour: statusColour(device.effectiveStatus),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
