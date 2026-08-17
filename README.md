# Smart Home Monitoring & Control System

SCS 3311 — Mobile Application Design & Development, mini-project.

A real-time smart home monitoring and control system: a Flutter mobile client, a
Firebase Realtime Database, a server-side safety worker, and a web-based hardware
simulator standing in for physical appliances.

## Deliverables

| | |
|---|---|
| **APK download** | [app-release.apk](https://drive.google.com/file/d/1vaMeyKVl-bVuVnc9wcazxotYLbXrx9R4/view?usp=sharing) |
| **Live simulator** | https://smart-home-monitoring-sy-75fd9.web.app |
| **Demo video** | _(link — Member C)_ |
| **Technical report** | `docs/technical-report.md` |

The linked APK is built with `--dart-define=USE_FIREBASE=false` so it can be
installed and explored without a Firebase account: it runs against an in-memory
repository holding the same data `tools/seed.js` writes. Every screen behaves
identically — only the transport differs. Live cross-client synchronisation with
the simulator is shown in the demo video and is reproduced by building without
that flag, once an account UID has been added to `homes/home1/meta/members`.

## Team

| Member | Responsibility | Report section |
|---|---|---|
| Gayash Vihangana | Backend, sync layer, safety worker, usage reporting | The synchronising mechanism |
| Shashindu Kalshan Akalanka Waduthanthee | Mobile client, floor plans, grid overlay, device control, camera | Floor representation |
| Isum Uthsara | Hardware simulator, presence, report and video production | Simulator operations |

## Architecture

```
┌─────────────────┐   write toggles    ┌──────────────────────┐
│  Flutter App    │ ─────────────────► │  Firebase Realtime   │
│                 │ ◄───────────────── │  Database            │
└─────────────────┘   realtime stream  └──────────┬───────────┘
                                                  │
┌─────────────────┐   reflects state              │
│  Web Simulator  │ ◄─────────────────────────────┤
│                 │ ─────────────────────────────►│
└─────────────────┘   switch press / fault        │
                                                  │
┌─────────────────┐   watch + cutoff + alert      │
│  Safety Worker  │ ◄─────────────────────────────┘
│  (Node.js)      │ ──── flips state to OFF ──────►
└─────────────────┘
```

The app and the simulator never talk to each other. They agree only on the
database schema, which is why either can be built and demonstrated independently.

## Repository layout

| Path | Contents | Owner |
|---|---|---|
| `lib/` | Flutter mobile client | A |
| `worker/` | Node safety worker — cutoff, schedules, usage aggregation | B |
| `tools/` | Database seeding script | B |
| `firebase/` | Realtime Database security rules | B |
| `simulator/` | Web hardware simulator (plain HTML/CSS/JS) | C |
| `docs/` | Technical report | all |

## Setup

### Mobile app

Requires Flutter 3.47+ (Dart 3.13). **The Android toolchain needs JDK 17–21** —
Gradle 9.3.1 / AGP 9.1.0 fail with unrelated-looking Kotlin errors on JDK 22+. If
your default JDK is newer, point Flutter at Android Studio's bundled runtime:

```bash
flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
```

Then:

```bash
flutter pub get
flutter run
```

`lib/firebase_options.dart` is committed, so no `flutterfire configure` is needed
to build. Reading real data does need an account: the security rules only admit
UIDs listed under `homes/home1/meta/members`, so register in the app, then have
that UID added to `.env` as `OWNER_UID` or `MEMBER_UIDS` and re-seed (see
`tools/seed.js`).

To run without any Firebase access at all — against an in-memory repository
seeded with the same data as `tools/seed.js` — pass:

```bash
flutter run --dart-define=USE_FIREBASE=false
```

Every screen behaves identically; only the transport differs. Useful for UI work
and for demonstrating the app on a machine that has not been granted project
access.

### Safety worker

Needs a Firebase service-account key, which is deliberately **not** in this
repository. Copy `.env.example` to `.env` and fill in both values, then:

```bash
cd worker
npm install
npm start
```

### Simulator

No build step and no dependencies, but it does need credentials. The simulator
signs in as its own device account — the rules gate hardware exactly as they gate
people — so copy the template and fill in the password:

```bash
cd simulator
cp sim-credentials.example.js sim-credentials.js
python -m http.server 8000
```

That account's UID must also be in `MEMBER_UIDS` in `.env` and the database
re-seeded, or sign-in succeeds and every read still returns permission denied.

### Seeding the database

```bash
cd tools
npm install
node seed.js          # add --reset to wipe first
```

Creates three floors and ten devices covering all five device types, plus two
weeks of usage history.

## Device types

| Type | Behaviour |
|---|---|
| `outlet` | Simple binary power supply |
| `multiswitch` | One gang box with N individually addressable channels |
| `hazard` | Fire-risk appliance with a maximum active duration, enforced server-side |
| `bulb` | Automatic on/off over a preset schedule window |
| `camera` | Mock snapshot / stream URIs |

Device status is one of `ON`, `OFF`, `ERROR`, `DISCONNECTED`. `DISCONNECTED` is
derived from `presence/<deviceId>/online` rather than stored on the device — a
device that cannot be reached is a different condition from one that was switched
off.

## Safety cutoff

If a hazard device stays on past its `maxOnDurationSec`, the worker flips the
database state to `OFF` and pushes an alert. It runs server-side, so it still
protects the house when the phone is closed, offline, or out of battery.

The cutoff has two halves: an in-process timer armed when the device turns on, and
a sweep every 30 seconds. The sweep is not redundant — if the worker restarts
while an appliance is on, the timer dies with the process, but `runtime.onSince`
persists in the database and the sweep recovers the pending cutoff on its next
tick.

---

<!--
  EDITING THIS FILE — to avoid merge conflicts with three people working at once:
  each member edits only the rows and sections naming them (deliverable links,
  their team row, their setup section). Anything else, agree in the group chat
  first. Always pull main before editing.
-->
