/// Authentication, behind the same kind of interface as [HomeRepository].
///
/// `firebase_auth` types do not leave this file. The UI sees [AppUser] and
/// [AuthFailure], which is what lets the sign-in screen be developed and tested
/// before anyone has Firebase console access.
///
/// Auth is not optional decoration here. `firebase/database.rules.json` gates
/// every read and write on `auth != null` AND membership of
/// `homes/<id>/meta/members/<uid>`, so without a signed-in user whose UID has
/// been enrolled, the app can see nothing at all.
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;

/// The signed-in user, reduced to what any screen actually needs.
class AppUser {
  const AppUser({required this.uid, this.email});

  final String uid;
  final String? email;

  @override
  bool operator ==(Object other) => other is AppUser && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}

/// A sign-in failure already translated into something worth showing a user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<void> signIn({required String email, required String password});

  Future<void> register({required String email, required String password});

  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb.FirebaseAuth? auth})
      : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  static AppUser? _toAppUser(fb.User? user) =>
      user == null ? null : AppUser(uid: user.uid, email: user.email);

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<void> signIn({required String email, required String password}) {
    return _guard(() => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  @override
  Future<void> register({required String email, required String password}) {
    return _guard(() => _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  @override
  Future<void> signOut() => _auth.signOut();

  /// Firebase's error codes are not user-facing text, and one of them —
  /// `operation-not-allowed` — is the specific failure that occurs when nobody
  /// has switched Email/Password on in the console yet. It gets a message that
  /// says what to actually do about it.
  Future<void> _guard(Future<fb.UserCredential> Function() action) async {
    try {
      await action();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'invalid-email' => 'That does not look like an email address.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Wrong email or password.',
        'email-already-in-use' =>
          'That email is already registered — sign in instead.',
        'weak-password' => 'Password must be at least 6 characters.',
        'operation-not-allowed' =>
          'Email/password sign-in is not enabled for this Firebase project yet.',
        'network-request-failed' =>
          'No connection to Firebase. Check the network and try again.',
        'too-many-requests' => 'Too many attempts. Wait a moment and retry.',
        _ => 'Sign-in failed (${e.code}).',
      });
    }
  }
}

/// Accepts any plausible credentials and invents a stable UID for them.
///
/// The UID is derived from the email rather than random so that a hot restart
/// does not look like a different person signed in.
class FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _current;

  @override
  Future<void> signIn({required String email, required String password}) =>
      _authenticate(email, password);

  @override
  Future<void> register({required String email, required String password}) =>
      _authenticate(email, password);

  /// Validates rather than waving everything through, so the sign-in screen's
  /// error path is reachable without Firebase.
  Future<void> _authenticate(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final trimmed = email.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      throw const AuthFailure('That does not look like an email address.');
    }
    if (password.length < 6) {
      throw const AuthFailure('Password must be at least 6 characters.');
    }

    _current = AppUser(uid: 'fake-${trimmed.hashCode.toUnsigned(32)}', email: trimmed);
    _controller.add(_current);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}
