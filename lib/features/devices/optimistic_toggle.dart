/// The optimistic write protocol, in one function.
///
/// A toggle has to feel instant, but the database is the authority and it is
/// milliseconds away at best. The compromise is to show the user's intent
/// immediately and reconcile when the write returns:
///
///   1. record the intended status, so the tile renders it over the stream value
///   2. issue the write
///   3. on success, drop the intent — the stream has already emitted the real
///      value and takes over with no visible change
///   4. on failure, drop the intent (the switch snaps back to the truth) and say
///      so, because a control that silently does nothing is worse than one that
///      visibly fails
///
/// Step 4 is the part that matters. Optimistic UI without a revert is not
/// optimistic, it is wrong — it leaves the screen claiming something about the
/// house that is not true.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/device.dart';
import '../../data/providers.dart';

Future<void> optimisticToggle({
  required WidgetRef ref,
  required BuildContext context,
  required String pendingKey,
  required DeviceStatus target,
  required Future<void> Function() write,
  required String description,
}) async {
  final pending = ref.read(pendingTogglesProvider.notifier);
  // Both captured before the await. Afterwards this widget may already be gone —
  // the sheet closed, the device removed from the list — and reading anything off
  // a dead context throws. The messenger belongs to the enclosing Scaffold, so it
  // outlives the tile and can still show the failure.
  final messenger = ScaffoldMessenger.of(context);
  final errorColour = Theme.of(context).colorScheme.error;

  pending.mark(pendingKey, target);
  try {
    await write();
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: errorColour,
          content: Text(
            "Couldn't switch $description "
            '${target == DeviceStatus.on ? 'on' : 'off'}. Nothing changed.',
          ),
        ),
      );
  } finally {
    pending.clear(pendingKey);
  }
}
