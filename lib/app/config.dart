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
const bool kUseFirebase = true;
