/// The home screen: every device in the house, filterable by floor.
///
/// A flat list rather than the floor-plan grid. The grid is the richer view and
/// it is coming, but a list is the one presentation that stays usable when a
/// floor plan image is missing, a device has no cell assigned, or the phone is
/// held in landscape — so it remains the fallback rather than being replaced.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/device.dart';
import '../../data/providers.dart';
import '../alerts/alerts_screen.dart';
import '../reports/reports_screen.dart';
import 'device_tile.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // devicesProvider, not allDevicesProvider: it already watches
    // selectedFloorProvider and pushes the filter down to the repository.
    final devices = ref.watch(devicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Home'),
        actions: [
          IconButton(
            tooltip: 'Usage reports',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
          ),
          _AlertsAction(onTap: () => _openAlerts(context)),
          const _AccountMenu(),
        ],
      ),
      body: Column(
        children: [
          AlertBanner(onTap: () => _openAlerts(context)),
          const _FloorFilter(),
          const Divider(height: 1),
          Expanded(
            child: devices.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(error: error),
              data: (list) => list.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => DeviceTile(device: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static void _openAlerts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AlertsScreen()),
    );
  }
}

/// Floor selector. "All" is first and is the default, because the question a
/// user opens this app to answer is usually "did I leave anything on?", which is
/// a whole-house question.
class _FloorFilter extends ConsumerWidget {
  const _FloorFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floors = ref.watch(floorsProvider).value ?? const <Floor>[];
    if (floors.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(selectedFloorProvider);

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final entry in <(String?, String)>[
            (null, 'All floors'),
            ...floors.map((f) => (f.id, f.name)),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ChoiceChip(
                label: Text(entry.$2),
                selected: selected == entry.$1,
                onSelected: (_) => ref
                    .read(selectedFloorProvider.notifier)
                    .select(entry.$1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Alerts button carrying the unread count, so a safety cutoff is visible from
/// the app bar without opening anything.
class _AlertsAction extends ConsumerWidget {
  const _AlertsAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadAlertCountProvider);

    return IconButton(
      tooltip: 'Safety alerts',
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

/// Account menu. The UID is here for a practical reason: the security rules key
/// off `homes/<id>/meta/members/<uid>`, so whoever seeds the database needs this
/// exact string, and reading it off the phone beats digging through the console.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;

    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) async {
        if (value == 'uid' && user != null) {
          await Clipboard.setData(ClipboardData(text: user.uid));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('UID copied to clipboard')),
            );
          }
        } else if (value == 'signOut') {
          await ref.read(authServiceProvider).signOut();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(user?.email ?? 'Not signed in'),
        ),
        if (user != null)
          PopupMenuItem(
            value: 'uid',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Copy my UID'),
              subtitle: Text(
                user.uid,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        const PopupMenuItem(
          value: 'signOut',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_outlined, size: 48),
            SizedBox(height: 12),
            Text('No devices on this floor.', textAlign: TextAlign.center),
            SizedBox(height: 4),
            Text(
              'If the whole house is empty, the database has not been seeded — '
              'run tools/seed.js.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Permission denied is by far the most likely error here and it has a specific
/// cause, so it gets a specific explanation rather than a raw exception dump.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final denied = error.toString().toLowerCase().contains('permission');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              denied ? 'This account cannot read this home' : 'Could not load devices',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'The security rules only allow members of the home. Copy your '
                      'UID from the account menu and have it added to '
                      'homes/home1/meta/members, then re-seed.'
                  : '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
