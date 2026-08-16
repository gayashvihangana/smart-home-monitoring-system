/// Build-time switches.
///
/// There is exactly one of these and it is read in exactly one place —
/// `data/providers.dart`, where the repository and auth service are constructed.
/// Everything else in the app depends on the `HomeRepository` and `AuthService`
/// interfaces and cannot tell which implementation it received.
library;

/// Whether this build talks to the real Firebase project.
///
/// Set to `false` to run the whole app against [FakeHomeRepository] and
/// [FakeAuthService] with no network, no credentials, and no Firebase console
/// access. That is not a toy mode: the fake is seeded from the same data as
/// `tools/seed.js`, so every screen renders exactly what it will render against
/// the live database.
///
/// It exists because `firebase/database.rules.json` denies all reads until an
/// account's UID has been written into `homes/<id>/meta/members`, which needs
/// someone with console access. Development does not have to wait for that.
///
/// Defaults to the real backend, and is overridable at build time so switching
/// does not mean editing tracked source:
///
///     flutter run --dart-define=USE_FIREBASE=false
///
/// That matters for the demo — the offline run has to be reproducible from a
/// command, not from an uncommitted local edit somebody has to remember to undo.
const bool kUseFirebase =
    bool.fromEnvironment('USE_FIREBASE', defaultValue: true);
