/// Entry point.
///
/// Deliberately thin: initialise Firebase, install the Riverpod scope, and hand
/// off to the auth gate. Everything else lives under `features/`.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/config.dart';
import 'app/theme.dart';
import 'data/providers.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/devices/dashboard_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guarded, not unconditional: with kUseFirebase false the app runs entirely on
  // the in-memory fakes, and initialising Firebase would be a pointless network
  // dependency that fails on a machine with no project access.
  if (kUseFirebase) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(const ProviderScope(child: SmartHomeApp()));
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _AuthGate(),
    );
  }
}

/// Decides, in one place, what a user sees based on whether they are signed in.
///
/// The loading branch is not ceremony. Firebase restores a persisted session
/// asynchronously, so there is a real moment where "signed in?" has no answer
/// yet — rendering the sign-in screen during it would flash a login form at
/// someone who is already logged in, on every cold start.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authStateProvider).when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Authentication is unavailable.\n\n$error',
                    textAlign: TextAlign.center),
              ),
            ),
          ),
          data: (user) =>
              user == null ? const SignInScreen() : const DashboardScreen(),
        );
  }
}
