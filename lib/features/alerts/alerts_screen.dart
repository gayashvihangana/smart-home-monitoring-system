/// Safety alerts raised by the server-side worker.
///
/// The spec asks for "push of an alert" when a max_on_duration is breached. The
/// worker pushes to `homes/<id>/alerts`, and this screen streams that node — so
/// the alert reaches the user whether or not a push notification was delivered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/device.dart';
import '../../data/providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final repo = ref.read(homeRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Safety alerts')),
      body: alerts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load alerts: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No alerts. Nothing has overrun.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final alert = list[i];
              return ListTile(
                leading: Icon(
                  alert.isCutoff ? Icons.local_fire_department : Icons.warning,
                  color: const Color(0xFFF44336),
                ),
                title: Text(alert.deviceName),
                subtitle: Text(_describe(alert)),
                trailing: alert.read
                    ? null
                    : TextButton(
                        onPressed: () => repo.markAlertRead(alert.id),
                        child: const Text('Mark read'),
                      ),
                tileColor: alert.read
                    ? null
                    : Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
              );
            },
          );
        },
      ),
    );
  }

  static String _describe(Alert alert) {
    final when = DateFormat('d MMM, HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(alert.timestamp));

    if (!alert.isCutoff) return '${alert.reason} · $when';

    final held = alert.heldForSec;
    final limit = alert.limitSec;
    if (held == null || limit == null) {
      return 'Automatically switched off · $when';
    }
    return 'Ran ${held}s against a ${limit}s limit — '
        'automatically switched off · $when';
  }
}

/// Banner for the dashboard, so a cutoff is visible without opening the alerts
/// screen. Renders nothing when there is nothing to report.
class AlertBanner extends ConsumerWidget {
  const AlertBanner({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadAlertCountProvider);
    if (unread == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  unread == 1
                      ? '1 device was automatically switched off for safety'
                      : '$unread devices were automatically switched off for safety',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}
