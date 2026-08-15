/**
 * SERVER-SIDE SAFETY CUTOFF
 *
 * If a fire-risk appliance (iron, water heater) stays on longer than its
 * configured max_on_duration, the database state is flipped to OFF and an alert
 * is pushed. This lives on the server, not in the app, because the phone may be
 * closed, offline, or out of battery — none of which should disable a safety
 * feature.
 *
 * It has TWO HALVES, and the second is the one that actually protects the house:
 *
 *   1. ARM ON TRANSITION — when a hazard device goes OFF -> ON we stamp
 *      runtime.onSince and set an in-process timer for the remaining duration.
 *      This is precise and fires exactly on time.
 *
 *   2. SWEEP EVERY 30 SECONDS — scan every hazard device whose runtime.onSince
 *      is set and whose elapsed time has passed the limit, and force it off.
 *
 * The sweep is NOT redundant. If the worker crashes or is redeployed while an
 * iron is on, the in-process timer from half 1 dies with the old process. The
 * timer lived in memory; runtime.onSince lives in the database. On restart the
 * sweep reads that persisted state and recovers the pending cutoff, so the
 * protection survives a restart. That distinction — memory is disposable,
 * database state is authoritative — is the core of the design.
 */

const { devicesRef, TIMESTAMP, serverNow, homeRef } = require('./firebase');
const { isHazard, maxOnDurationSec, onSince } = require('./devices');
const log = require('./log');

const SWEEP_INTERVAL_MS = 30_000;

/** deviceId -> setTimeout handle. In-process only, deliberately not persisted. */
const timers = new Map();

function clearTimer(deviceId) {
  const t = timers.get(deviceId);
  if (t) {
    clearTimeout(t);
    timers.delete(deviceId);
  }
}

/**
 * Flip the device off and record why. Everything is written in one update() so
 * a reader never observes status OFF while onSince is still set.
 */
async function forceOff(deviceId, device, trigger) {
  clearTimer(deviceId);

  const heldForSec = Math.round((serverNow() - onSince(device)) / 1000);

  await devicesRef.child(deviceId).update({
    status: 'OFF',
    'runtime/onSince': null,
    lastChangedBy: 'worker',
    lastChangedAt: TIMESTAMP,
  });

  await homeRef.child('alerts').push({
    deviceId,
    deviceName: device.name || deviceId,
    reason: 'MAX_DURATION_EXCEEDED',
    limitSec: maxOnDurationSec(device),
    heldForSec,
    ts: TIMESTAMP,
    read: false,
  });

  log.cutoff(
    `${device.name || deviceId} forced OFF after ${heldForSec}s ` +
      `(limit ${maxOnDurationSec(device)}s, via ${trigger})`
  );
}

/**
 * Arm a timer for the remaining time on an already-on device. Called both when a
 * device turns on and, on startup, for devices found already running.
 */
function armTimer(deviceId, device) {
  clearTimer(deviceId);

  const limitMs = maxOnDurationSec(device) * 1000;
  if (limitMs <= 0) return;

  const elapsedMs = serverNow() - onSince(device);
  const remainingMs = Math.max(0, limitMs - elapsedMs);

  timers.set(
    deviceId,
    setTimeout(async () => {
      // Re-read before acting: the device may have been switched off by a human
      // in the meantime, and firing a stale timer would be a phantom cutoff.
      const snap = await devicesRef.child(deviceId).once('value');
      const current = snap.val();
      if (current && current.status === 'ON' && onSince(current)) {
        await forceOff(deviceId, current, 'timer');
      }
    }, remainingMs)
  );

  log.info(
    `armed ${device.name || deviceId}: cutoff in ${Math.round(remainingMs / 1000)}s`
  );
}

/**
 * Half 1 — react to a state transition observed on the devices listener.
 * `prev` is undefined on the first observation of a device.
 */
async function onDeviceChange(deviceId, prev, next) {
  if (!isHazard(next)) return;

  const wasOn = prev ? prev.status === 'ON' : false;
  const isOn = next.status === 'ON';

  if (!wasOn && isOn) {
    // Stamp the start time if nobody has. The app never writes runtime.onSince —
    // security rules reject it — so the worker owns this field exclusively.
    if (!onSince(next)) {
      await devicesRef.child(deviceId).child('runtime').update({ onSince: TIMESTAMP });
      return; // the resulting write comes back through this same listener
    }
    armTimer(deviceId, next);
  } else if (wasOn && !isOn) {
    clearTimer(deviceId);
    if (onSince(next)) {
      await devicesRef.child(deviceId).child('runtime').update({ onSince: null });
    }
    // Our own cutoff write comes back through this listener. Logging it again
    // would put a misleading "turned off" line just above the CUTOFF line.
    if (next.lastChangedBy !== 'worker') {
      log.info(`${next.name || deviceId} turned off by ${next.lastChangedBy || 'unknown'}, timer cleared`);
    }
  } else if (isOn && onSince(next) && !timers.has(deviceId)) {
    // Covers the onSince stamp landing, and re-arming after a restart.
    armTimer(deviceId, next);
  }
}

/**
 * Half 2 — the sweep. Recovers cutoffs whose in-process timer was lost, which is
 * exactly what happens across a worker restart.
 */
async function sweep() {
  const snap = await devicesRef.once('value');
  const devices = snap.val() || {};
  const now = serverNow();

  for (const [deviceId, device] of Object.entries(devices)) {
    if (!isHazard(device) || device.status !== 'ON') continue;

    const started = onSince(device);
    const limitMs = maxOnDurationSec(device) * 1000;

    if (!started) {
      // On but never stamped — the transition was missed while the worker was
      // down. Stamp it now so the device is not left unprotected forever.
      await devicesRef.child(deviceId).child('runtime').update({ onSince: TIMESTAMP });
      log.warn(`${device.name || deviceId} was ON with no onSince — stamped now`);
      continue;
    }

    if (limitMs > 0 && now - started > limitMs) {
      await forceOff(deviceId, device, 'sweep');
    } else if (!timers.has(deviceId)) {
      armTimer(deviceId, device);
    }
  }
}

function startSweep() {
  log.info(`safety sweep running every ${SWEEP_INTERVAL_MS / 1000}s`);
  sweep().catch((e) => log.error(`sweep failed: ${e.message}`));
  return setInterval(
    () => sweep().catch((e) => log.error(`sweep failed: ${e.message}`)),
    SWEEP_INTERVAL_MS
  );
}

module.exports = { onDeviceChange, startSweep, sweep, forceOff };
