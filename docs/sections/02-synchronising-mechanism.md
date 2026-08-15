# The Synchronising Mechanism

*Section author: Gayash Vihangana (Member B)*

## Overview

The system has three independent clients — the Flutter mobile app, the web
hardware simulator, and a Node.js safety worker — and none of them talks to
another directly. All three connect only to a Firebase Realtime Database and
agree on a single schema. Every behaviour described below follows from that one
decision: the database is the integration point, and it is the only one.

This is why the app and the simulator could be developed in parallel by different
members, and why either can be demonstrated while the other is switched off.

## Why the Realtime Database

Firestore was considered and rejected. Device toggles are small, frequent writes
to a known path, and three properties of the Realtime Database suit that better.
It pushes deltas rather than whole documents over a single WebSocket; it has no
per-document read cost, which matters when several clients hold live listeners on
the same node; and it exposes `onDisconnect()`, a server-side hook that fires
when a client's socket drops. That last one is what makes device presence
detection possible without a heartbeat protocol of our own.

## Push, not poll

There is no refresh button and no polling timer anywhere in this project. Each
client registers listeners — `onValue` in JavaScript, `DatabaseReference.onValue`
in Dart — and Firebase holds an open socket to the server. When any client writes,
the server pushes the changed subtree to every other listener within
milliseconds. A toggle in the app therefore reaches the simulator without either
of them knowing the other exists.

Listener scope is deliberate. The app subscribes to `homes/<homeId>/devices`, not
to the database root. Listening higher in the tree would re-serialise every floor,
alert and usage record on every individual toggle. Where a screen needs only one
floor, filtering happens after a single shared subscription rather than by opening
another one, and `.indexOn` entries in the security rules keep server-side
ordering from degrading into client-side filtering.

## Writes, conflicts and provenance

Two different concurrency strategies are used, and the contrast is intentional.

Device status uses a plain `update()`, which is last-write-wins. For a light
switch this is not a compromise but the correct semantics: if two people press
the switch, the most recent human intent should win. A transaction here would
resolve races in favour of whoever retried rather than whoever acted last.

Usage counters use `runTransaction()`. A counter is the opposite case — every
increment must survive, so two writes landing together must not clobber each
other.

Every write also stamps `lastChangedBy` with one of `app`, `simulator`, `worker`
or `schedule`, and `lastChangedAt` using `ServerValue.TIMESTAMP` rather than the
client clock. Server timestamps matter because client clocks drift, and a safety
cutoff that fires against a wrong clock is worse than none. The provenance field
makes it demonstrable at any moment which client caused a given change.

Offline behaviour comes from the SDK rather than from our code. A write made
without connectivity is queued locally and replayed on reconnect, and the local
listener fires immediately, so the interface responds at once and reconciles when
the network returns.

## Presence and the DISCONNECTED state

`DISCONNECTED` is never stored on a device. It is derived.

The simulator, standing in for physical hardware, registers
`onDisconnect(presenceRef).update({ online: false })` *before* writing
`online: true`. Registering in that order matters: if the write came first and the
process died in the gap, the device would be marked online permanently. Because
the handler runs on Firebase's servers, closing the browser tab or losing the
network causes the server itself to mark the device offline.

The app then joins two streams — devices and presence — and presence wins. A
device nobody can reach is a different condition from one that was switched off,
and only presence knows the difference. The join is done by holding the latest
snapshot of each stream and recombining, rather than nesting listeners, which
would rebuild the entire device list every time a single heartbeat ticked.

## Server-side safety enforcement

The most important synchronisation in the system is the one that happens with no
user present. If a fire-risk appliance exceeds its configured
`maxOnDurationSec`, the worker flips the database state to `OFF` and pushes an
alert. This runs on the server precisely because the phone may be closed,
offline, or out of battery.

The cutoff has two halves. When a hazard device transitions to `ON`, the worker
stamps `runtime.onSince` and arms an in-process timer. Separately, a sweep every
thirty seconds forces off any hazard device whose elapsed time has passed its
limit.

The sweep is not redundant, and the reason is the core of the design. If the
worker crashes or is redeployed while an iron is on, the in-process timer dies
with the process — it lived in memory. `runtime.onSince` lives in the database. On
restart the sweep reads that persisted state and recovers the pending cutoff.
Memory is disposable; database state is authoritative.

This was verified rather than assumed. In normal operation an iron with a
thirty-second limit was switched off by the worker 32.4 seconds after being turned
on, with an alert recorded showing it had run 30 seconds against a 30-second
limit. The worker was then killed with the device on and sixty seconds elapsed, so
no timer existed anywhere; on restart it cut the device off within eight seconds,
logging `via sweep` rather than `via timer`.

## Reporting pipeline

Every observed transition is appended to an event log, and completed ON periods
are folded into `usageDaily` per device per day. Aggregation happens server-side
so the reports screen is a plain read with no computation, and so `usageDaily` can
be locked as server-owned in the security rules — figures a client could rewrite
would be unfalsifiable.

## Security model

Access is scoped to home membership. Two server-owned paths — `devices/<id>/runtime`
and `usageDaily` — are protected with `.validate: false` rather than a `.write`
rule, because Realtime Database read and write permissions cascade downwards and
cannot be revoked by a child rule, whereas validation rules are evaluated along
the whole path and can reject a write the cascade permitted. The worker uses the
Admin SDK, which bypasses rules entirely, so it still writes those fields. That
asymmetry is what stops a client forging `runtime.onSince` to postpone its own
safety cutoff indefinitely.

## Sequence

```
App → RTDB → Simulator
  user taps switch
  app writes  homes/home1/devices/outletLiving  { status: ON, lastChangedBy: app }
  server pushes the delta to all listeners
  simulator's onValue fires, div turns green      (no refresh, no polling)

Simulator → RTDB → App
  user clicks the simulator's button
  simulator writes { status: OFF, lastChangedBy: simulator }
  app's stream emits, the Switch moves on its own

Worker → RTDB → both
  iron exceeds maxOnDurationSec
  worker writes { status: OFF, runtime/onSince: null, lastChangedBy: worker }
  and pushes to alerts/
  app shows the alert banner; simulator's iron goes cold
```

---

*≈1,000 words of prose, 1,180 including the sequence block — trim the reporting
or security paragraphs first if the report runs long.*

*Assembly note for Member C: the introduction should carry the architecture
diagram; this section assumes it has already been shown.*
