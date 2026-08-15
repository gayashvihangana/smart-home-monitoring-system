/**
 * Smart Home Monitoring & Control System — safety worker.
 *
 *   cd worker && npm install && npm start
 *
 * Three responsibilities, all server-side:
 *   1. lib/cutoff.js    — force a hazard device OFF when it exceeds max_on_duration
 *   2. lib/scheduler.js — hold scheduled bulbs at the state their window implies
 *   3. lib/usage.js     — append to the event log and aggregate daily usage
 *
 * The spec permits "a backend cloud listener or a worker process". This is the
 * worker-process form, chosen over Cloud Functions because deploying Functions
 * now requires the Firebase Blaze billing plan. The logic would port directly.
 *
 * ONE LISTENER, NOT THREE. The whole worker watches `devices` through a single
 * subscription and dispatches transitions to the modules above. Three separate
 * listeners on the same path would mean three copies of every payload over the
 * socket for no benefit.
 */

const { devicesRef, HOME_ID } = require('./lib/firebase');
const cutoff = require('./lib/cutoff');
const scheduler = require('./lib/scheduler');
const usage = require('./lib/usage');
const log = require('./lib/log');

/** Last known state per device, so a change event can be read as a transition. */
const previous = new Map();

async function handleChange(deviceId, next) {
  const prev = previous.get(deviceId);
  previous.set(deviceId, next);

  // Sequential, not Promise.all: cutoff may write runtime.onSince, and usage
  // should observe a settled device rather than race that write.
  try {
    await cutoff.onDeviceChange(deviceId, prev, next);
    await usage.onDeviceChange(deviceId, prev, next);
  } catch (e) {
    log.error(`handling ${deviceId}: ${e.message}`);
  }
}

function main() {
  log.info(`worker starting for home "${HOME_ID}"`);

  devicesRef.on('child_added', (snap) => handleChange(snap.key, snap.val()));
  devicesRef.on('child_changed', (snap) => handleChange(snap.key, snap.val()));
  devicesRef.on('child_removed', (snap) => previous.delete(snap.key));

  const sweepTimer = cutoff.startSweep();
  const scheduleTimer = scheduler.start();

  log.info('listening for device changes');

  const shutdown = (signal) => {
    log.info(`${signal} received, shutting down`);
    clearInterval(sweepTimer);
    clearInterval(scheduleTimer);
    devicesRef.off();
    // Pending cutoffs are NOT lost here: runtime.onSince is in the database, and
    // the sweep re-arms them on the next start. That is the point of half 2.
    process.exit(0);
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main();
