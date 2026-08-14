/**
 * SCHEDULE ENFORCEMENT
 *
 * Bulbs can be configured to run over a preset window (e.g. 18:30 -> 23:00 on
 * given weekdays). Every 60 seconds this compares each bulb's current state
 * against what its schedule says it *should* be, and corrects any disagreement.
 *
 * WHY COMPARE, NOT FIRE ON THE EDGE: an edge-triggered scheduler ("at 18:30, turn
 * on") misses its window entirely if the worker happens to be restarting at
 * 18:30, and the light stays off all evening. Comparing against the window means
 * the very next tick after a restart puts the light into the correct state by
 * itself. Same self-healing principle as the safety sweep.
 *
 * A manual override is respected until the next boundary: if you switch the porch
 * light off at 20:00 it will come back on at the next tick, which is the expected
 * behaviour for a schedule — the schedule is the authority while it is active.
 */

const { devicesRef, TIMESTAMP } = require('./firebase');
const log = require('./log');

const TICK_MS = 60_000;

/**
 * Current wall-clock time in an arbitrary IANA timezone, without pulling in a
 * date library. Returns minutes-since-midnight and an ISO weekday (1=Mon..7=Sun).
 */
function localTime(tz) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz,
    hour: '2-digit',
    minute: '2-digit',
    weekday: 'short',
    hour12: false,
  }).formatToParts(new Date());

  const get = (t) => parts.find((p) => p.type === t)?.value;
  const hour = parseInt(get('hour'), 10);
  const minute = parseInt(get('minute'), 10);
  const weekdayMap = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

  return { minutes: hour * 60 + minute, weekday: weekdayMap[get('weekday')] };
}

const toMinutes = (hhmm) => {
  const [h, m] = String(hhmm).split(':').map(Number);
  return h * 60 + m;
};

/**
 * Is `now` inside [onAt, offAt)? Handles windows that cross midnight, e.g.
 * 22:00 -> 06:00, where onAt > offAt.
 */
function isWithinWindow(nowMin, onMin, offMin) {
  if (onMin === offMin) return false;
  return onMin < offMin
    ? nowMin >= onMin && nowMin < offMin
    : nowMin >= onMin || nowMin < offMin; // crosses midnight
}

async function tick() {
  const snap = await devicesRef.once('value');
  const devices = snap.val() || {};

  for (const [deviceId, device] of Object.entries(devices)) {
    const s = device.schedule;
    if (device.type !== 'bulb' || !s || !s.enabled || !s.onAt || !s.offAt) continue;

    const { minutes, weekday } = localTime(s.tz || 'Asia/Colombo');

    // For a window crossing midnight, the active day is the day it STARTED on.
    const days = Array.isArray(s.days) ? s.days : [1, 2, 3, 4, 5, 6, 7];
    const onMin = toMinutes(s.onAt);
    const offMin = toMinutes(s.offAt);
    const inWindow = isWithinWindow(minutes, onMin, offMin);
    const startDay = onMin > offMin && minutes < offMin ? (weekday === 1 ? 7 : weekday - 1) : weekday;

    const shouldBeOn = inWindow && days.includes(startDay);
    const desired = shouldBeOn ? 'ON' : 'OFF';

    // Never fight an ERROR or DISCONNECTED state — those mean the device is not
    // answering, and a schedule should not paper over a fault.
    if (device.status !== 'ON' && device.status !== 'OFF') continue;
    if (device.status === desired) continue;

    await devicesRef.child(deviceId).update({
      status: desired,
      lastChangedBy: 'schedule',
      lastChangedAt: TIMESTAMP,
    });

    log.schedule(
      `${device.name || deviceId} -> ${desired} ` +
        `(window ${s.onAt}-${s.offAt} ${s.tz || 'Asia/Colombo'})`
    );
  }
}

function start() {
  log.info(`schedule enforcement running every ${TICK_MS / 1000}s`);
  tick().catch((e) => log.error(`schedule tick failed: ${e.message}`));
  return setInterval(
    () => tick().catch((e) => log.error(`schedule tick failed: ${e.message}`)),
    TICK_MS
  );
}

module.exports = { start, tick, isWithinWindow, localTime, toMinutes };
