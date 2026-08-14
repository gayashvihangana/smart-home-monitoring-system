/** Timestamped console logging, so the demo video shows when each event fired. */

function stamp() {
  return new Date().toISOString().slice(11, 19); // HH:MM:SS
}

const log = (tag, msg) => console.log(`[${stamp()}] ${tag.padEnd(9)} ${msg}`);

module.exports = {
  info: (msg) => log('INFO', msg),
  cutoff: (msg) => console.log(`[${stamp()}] ${'CUTOFF'.padEnd(9)} ${msg}`),
  schedule: (msg) => log('SCHEDULE', msg),
  usage: (msg) => log('USAGE', msg),
  warn: (msg) => log('WARN', msg),
  error: (msg) => console.error(`[${stamp()}] ERROR     ${msg}`),
};
