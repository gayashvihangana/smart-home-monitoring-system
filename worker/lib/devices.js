/** Shared helpers for reasoning about device state. */

/**
 * A multi-switch gang box is one entity wrapping N independently addressable
 * channels. It counts as ON if ANY channel is on — the same rule the mobile
 * client uses for the unit's summary status, so the two never disagree.
 */
function isDeviceOn(device) {
  if (!device) return false;
  if (device.type === 'multiswitch') {
    return Object.values(device.channels || {}).some((c) => c && c.state === 'ON');
  }
  return device.status === 'ON';
}

/** Hazard devices are the fire-risk appliances subject to a max active duration. */
const isHazard = (device) => device && device.type === 'hazard';

const maxOnDurationSec = (device) =>
  (device && device.config && device.config.maxOnDurationSec) || 0;

const onSince = (device) => (device && device.runtime && device.runtime.onSince) || 0;

module.exports = { isDeviceOn, isHazard, maxOnDurationSec, onSince };
