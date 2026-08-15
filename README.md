# Smart Home Monitoring & Control System

SCS 3311 — Mobile Application Design & Development, mini-project.

A real-time smart home monitoring and control system: a Flutter mobile client, a
Firebase Realtime Database, a server-side safety worker, and a web-based hardware
simulator standing in for physical appliances.

## Deliverables

| | |
|---|---|
| **APK download** | _(link — Member A)_ |
| **Live simulator** | https://smart-home-monitoring-sy-75fd9.web.app |
| **Demo video** | _(link — Member C)_ |
| **Technical report** | `docs/technical-report.md` |

## Team

| Member | Responsibility | Report section |
|---|---|---|
| Gayash Vihangana | Backend, sync layer, safety worker, usage reporting | The synchronising mechanism |
| _(Member A)_ | Mobile client, floor plans, grid overlay, device control, camera | Floor representation |
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

```bash
flutter pub get
flutterfire configure      # select project smart-home-monitoring-sy-75fd9
flutter run
```

### Safety worker

Needs a Firebase service-account key, which is deliberately **not** in this
repository. Copy `.env.example` to `.env` and fill in both values, then:

```bash
cd worker
npm install
npm start
```

### Simulator

No build step and no dependencies. Serve the folder and open it:

```bash
cd simulator
python -m http.server 8000
```

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
