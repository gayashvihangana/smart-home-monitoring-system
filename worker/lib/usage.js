/**
 * EVENT LOG + USAGE AGGREGATION
 *
 * The worker is the single writer of both `events` and `usageDaily`. Every device
 * transition it observes is appended to the event log, and completed ON periods
 * are folded into per-device daily totals.
 *
 * WHY AGGREGATE HERE RATHER THAN IN THE APP: the reports screen becomes a plain
 * read with no computation, so it stays fast and cannot disagree between devices.
 * It also means `usageDaily` can be locked as server-owned in the security rules
 * — if clients could write it, usage figures would be unfalsifiable.
 *
 * Increments use a transaction because two writes landing together (a channel
 * toggle and a cutoff, say) would otherwise clobber each other. Note the
 * contrast with device status, which deliberately uses last-write-wins: for a
 * light switch the most recent human intent should win, but for a counter every
 * increment must survive.
 */

const { homeRef, serverNow } = require('./firebase');
const { isDeviceOn } = require('./devices');
const log = require('./log');

/**
 * deviceId -> local epoch ms when it was last observed turning on.
 *
 * Deliberately Date.now() and not serverNow(). The server clock offset is fetched
 * asynchronously at startup, so a duration measured by subtracting two
 * offset-adjusted readings taken either side of that fetch is wrong by the whole
 * offset — which is how a genuine 8-second run first got recorded as 0 seconds.
 * Durations are a local interval measurement and must use one consistent clock;
 * serverNow() is only for absolute timestamps written to the database, where
 * agreeing with other clients is what matters.
 */
const onSinceMemory = new Map();

const dateKey = (ms) => new Date(ms).toISOString().slice(0, 10);

async function recordEvent(deviceId, device, from, to) {
  await homeRef.child('events').push({
    deviceId,
    deviceName: device.name || deviceId,
    from,
    to,
    source: device.lastChangedBy || 'unknown',
    ts: serverNow(),
  });
}

async function addUsage(deviceId, seconds) {
  if (seconds <= 0) return;
  const key = dateKey(serverNow());
  const ref = homeRef.child('usageDaily').child(deviceId).child(key);

  await ref.transaction((current) => ({
    onSeconds: ((current && current.onSeconds) || 0) + Math.round(seconds),
    toggleCount: ((current && current.toggleCount) || 0) + 1,
  }));

  log.usage(`${deviceId} +${Math.round(seconds)}s on ${key}`);
}

/**
 * Called for every observed device change. `prev` is undefined the first time a
 * device is seen, in which case we only prime the in-memory start time rather
 * than inventing usage we never actually observed.
 */
async function onDeviceChange(deviceId, prev, next) {
  const wasOn = isDeviceOn(prev);
  const isOn = isDeviceOn(next);

  if (!prev) {
    if (isOn) onSinceMemory.set(deviceId, Date.now());
    return;
  }
  if (wasOn === isOn) return;

  await recordEvent(deviceId, next, wasOn ? 'ON' : 'OFF', isOn ? 'ON' : 'OFF');

  if (isOn) {
    onSinceMemory.set(deviceId, Date.now());
  } else {
    const started = onSinceMemory.get(deviceId);
    onSinceMemory.delete(deviceId);
    // Only count periods this process actually watched from start to finish.
    // Guessing at a start time we never saw would put fiction into the reports.
    if (started) await addUsage(deviceId, (Date.now() - started) / 1000);
  }
}

module.exports = { onDeviceChange };
