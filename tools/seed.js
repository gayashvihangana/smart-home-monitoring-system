/**
 * Seeds the Realtime Database with a demo home: three floors, one of every device
 * type, and two weeks of usage history so the reports screen has something to plot.
 *
 *   cd tools && npm install
 *   node seed.js            # merge into whatever is already there
 *   node seed.js --reset    # wipe the home first, then seed
 *
 * Requires FIREBASE_DB_URL and GOOGLE_APPLICATION_CREDENTIALS in ../.env
 *
 * NOTE ON MEMBERSHIP: security rules key off homes/$homeId/meta/members/$uid, and
 * this script OVERWRITES that map on every run. So it has to list everyone at once:
 * OWNER_UID plus MEMBER_UIDS (comma-separated) in .env. Anyone left out loses access
 * the moment this is re-run — including the web simulator, which signs in as its own
 * device account and is just another member as far as the rules are concerned.
 *
 * Nobody has a UID until their account exists. Create the accounts in Firebase
 * Console > Authentication > Users (or register in the app), copy the UIDs, then
 * fill in .env and re-run. Until then the members map is empty and the locked-down
 * rules will deny everything — which is correct, not a bug.
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const admin = require('firebase-admin');

const DB_URL = process.env.FIREBASE_DB_URL;
const HOME_ID = process.env.HOME_ID || 'home1';
const OWNER_UID = process.env.OWNER_UID || '';
const RESET = process.argv.includes('--reset');

// Everyone admitted to the home: the owner, the other developers, and the
// simulator's device account. The owner is always a member — being owner is not
// itself a grant, the rules check members only.
const MEMBER_UIDS = [
  ...new Set(
    [OWNER_UID, ...(process.env.MEMBER_UIDS || '').split(',')]
      .map((uid) => uid.trim())
      .filter(Boolean)
  ),
];

if (!DB_URL) {
  console.error('FIREBASE_DB_URL is not set. Copy .env.example to .env and fill it in.');
  process.exit(1);
}
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('GOOGLE_APPLICATION_CREDENTIALS is not set. Point it at the service-account JSON.');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: DB_URL,
});

const db = admin.database();
const now = Date.now();

// ---------------------------------------------------------------- floors

const floors = {
  floorGround: { name: 'Ground Floor', order: 0, planAsset: 'assets/plans/ground.png', grid: { cols: 10, rows: 8 } },
  floorFirst:  { name: 'First Floor',  order: 1, planAsset: 'assets/plans/first.png',  grid: { cols: 10, rows: 8 } },
  floorRoof:   { name: 'Roof Terrace', order: 2, planAsset: 'assets/plans/roof.png',   grid: { cols: 10, rows: 8 } },
};

// ---------------------------------------------------------------- devices
// Every type in the spec is represented at least once. Cells are integer grid
// indices, never pixels — see 00-PROJECT-PLAN.md §4.

const devices = {
  // --- outlets: simple binary nodes
  outletLiving: {
    floorId: 'floorGround', name: 'Living Room Outlet', type: 'outlet',
    cell: { x: 2, y: 3 }, status: 'OFF', lastChangedAt: now, lastChangedBy: 'seed',
  },
  outletKitchen: {
    floorId: 'floorGround', name: 'Kitchen Outlet', type: 'outlet',
    cell: { x: 7, y: 2 }, status: 'ON', lastChangedAt: now, lastChangedBy: 'seed',
  },

  // --- multi-switch: one physical gang box, N individually addressable channels
  gangHallway: {
    floorId: 'floorGround', name: 'Hallway Gang Box', type: 'multiswitch',
    cell: { x: 4, y: 5 }, status: 'OFF', lastChangedAt: now, lastChangedBy: 'seed',
    channels: {
      0: { label: 'Ceiling Light', state: 'OFF', lastChangedAt: now },
      1: { label: 'Wall Light',    state: 'OFF', lastChangedAt: now },
      2: { label: 'Exhaust Fan',   state: 'OFF', lastChangedAt: now },
    },
  },
  gangBedroom: {
    floorId: 'floorFirst', name: 'Bedroom Switch Panel', type: 'multiswitch',
    cell: { x: 3, y: 2 }, status: 'ON', lastChangedAt: now, lastChangedBy: 'seed',
    channels: {
      0: { label: 'Main Light', state: 'ON',  lastChangedAt: now },
      1: { label: 'Bedside',    state: 'OFF', lastChangedAt: now },
    },
  },

  // --- hazard: fire-risk appliance with a hard cap on active duration.
  // 30s here so the safety cutoff can be demonstrated on video without a long wait.
  // Production values would be minutes — say so in the report.
  ironLaundry: {
    floorId: 'floorFirst', name: 'Clothes Iron', type: 'hazard',
    cell: { x: 6, y: 6 }, status: 'OFF', lastChangedAt: now, lastChangedBy: 'seed',
    config: { maxOnDurationSec: 30 },
  },
  heaterBath: {
    floorId: 'floorFirst', name: 'Water Heater', type: 'hazard',
    cell: { x: 8, y: 4 }, status: 'OFF', lastChangedAt: now, lastChangedBy: 'seed',
    config: { maxOnDurationSec: 300 },
  },

  // --- bulbs: scheduled on/off over a preset window
  bulbPorch: {
    floorId: 'floorGround', name: 'Porch Light', type: 'bulb',
    cell: { x: 1, y: 7 }, status: 'OFF', lastChangedAt: now, lastChangedBy: 'seed',
    schedule: { enabled: true, onAt: '18:30', offAt: '23:00', days: [1, 2, 3, 4, 5, 6, 7], tz: 'Asia/Colombo' },
  },
  bulbGarden: {
    floorId: 'floorRoof', name: 'Garden Light', type: 'bulb',
    cell: { x: 5, y: 3 }, status: 'OFF', lastChangedAt: now, lastChangedBy: 'seed',
    schedule: { enabled: true, onAt: '19:00', offAt: '22:30', days: [5, 6, 7], tz: 'Asia/Colombo' },
  },

  // --- cameras: mock snapshot / stream URIs
  camFront: {
    floorId: 'floorGround', name: 'Front Door Camera', type: 'camera',
    cell: { x: 0, y: 4 }, status: 'ON', lastChangedAt: now, lastChangedBy: 'seed',
    snapshotUri: 'https://picsum.photos/seed/frontdoor/640/360',
    streamUri: 'https://example.com/mock/stream/frontdoor.m3u8',
  },
  camBack: {
    floorId: 'floorRoof', name: 'Backyard Camera', type: 'camera',
    cell: { x: 9, y: 1 }, status: 'ON', lastChangedAt: now, lastChangedBy: 'seed',
    snapshotUri: 'https://picsum.photos/seed/backyard/640/360',
    streamUri: 'https://example.com/mock/stream/backyard.m3u8',
  },
};

// ---------------------------------------------------------------- usage history
// Fourteen days of plausible history. An empty chart reads as broken on camera; a
// populated one reads as finished. Declare it as seeded demo data in the report.

function dateKey(daysAgo) {
  const d = new Date(now - daysAgo * 86400000);
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

// Deterministic pseudo-random, so re-seeding produces the same charts and the
// screenshots in the report stay consistent with the live app.
function pseudoRandom(seed) {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 1000) / 1000;
}

// Rough daily on-time per type, in seconds, before jitter.
const TYPICAL_ON_SECONDS = {
  outlet: 6 * 3600,
  multiswitch: 5 * 3600,
  hazard: 20 * 60,
  bulb: 4.5 * 3600,
  camera: 24 * 3600,
};

function buildUsage() {
  const usage = {};
  for (const [deviceId, device] of Object.entries(devices)) {
    const perDay = {};
    for (let daysAgo = 13; daysAgo >= 0; daysAgo--) {
      const key = dateKey(daysAgo);
      const r = pseudoRandom(`${deviceId}:${key}`);
      const base = TYPICAL_ON_SECONDS[device.type] ?? 3600;
      // ±40% jitter, and weekends run a little longer
      const weekend = [0, 6].includes(new Date(now - daysAgo * 86400000).getDay()) ? 1.2 : 1.0;
      perDay[key] = {
        onSeconds: Math.round(base * (0.6 + r * 0.8) * weekend),
        toggleCount: Math.max(1, Math.round(2 + r * 10)),
      };
    }
    usage[deviceId] = perDay;
  }
  return usage;
}

// A few historical cutoff alerts, so the "safety cutoffs this week" summary card
// is not zero before the live demo fires one.
function buildAlerts() {
  const alerts = {};
  [2, 5, 9].forEach((daysAgo, i) => {
    alerts[`seedAlert${i}`] = {
      deviceId: 'ironLaundry',
      reason: 'MAX_DURATION_EXCEEDED',
      ts: now - daysAgo * 86400000,
      read: true,
    };
  });
  return alerts;
}

// ---------------------------------------------------------------- run

async function main() {
  const homeRef = db.ref(`homes/${HOME_ID}`);

  if (RESET) {
    console.log(`--reset: removing homes/${HOME_ID} and presence/*`);
    await homeRef.remove();
    await db.ref('presence').remove();
  }

  const members = Object.fromEntries(MEMBER_UIDS.map((uid) => [uid, true]));
  if (MEMBER_UIDS.length === 0) {
    console.warn('\n  ⚠  OWNER_UID and MEMBER_UIDS are both blank — meta/members will be empty.');
    console.warn('     Create the accounts in Firebase Console > Authentication > Users,');
    console.warn('     copy the UIDs into .env, and re-run. Locked-down rules deny');
    console.warn('     everything — app and simulator alike — until then.\n');
  } else if (!OWNER_UID) {
    console.warn('\n  ⚠  OWNER_UID is blank, so meta/ownerUid will be null.');
    console.warn('     Members can still read and write; only the ownership field is unset.\n');
  }

  await homeRef.child('meta').set({
    name: 'Demo Smart Home',
    ownerUid: OWNER_UID || null,
    members,
  });
  await homeRef.child('floors').set(floors);
  await homeRef.child('devices').set(devices);
  await homeRef.child('usageDaily').set(buildUsage());
  await homeRef.child('alerts').set(buildAlerts());

  // Devices start offline. The simulator claims presence when it connects, which is
  // what makes DISCONNECTED the honest default rather than a fake "all online".
  const presence = {};
  for (const deviceId of Object.keys(devices)) {
    presence[deviceId] = { online: false, lastSeen: now };
  }
  await db.ref('presence').set(presence);

  console.log(`✓ Seeded homes/${HOME_ID}`);
  console.log(`  members: ${MEMBER_UIDS.length}${MEMBER_UIDS.length ? ` (${MEMBER_UIDS.join(', ')})` : ''}`);
  console.log(`  floors:  ${Object.keys(floors).length}`);
  console.log(`  devices: ${Object.keys(devices).length} (${[...new Set(Object.values(devices).map((d) => d.type))].join(', ')})`);
  console.log(`  usage:   14 days per device`);
  console.log(`  alerts:  ${Object.keys(buildAlerts()).length} historical cutoffs`);
  await admin.app().delete();
}

main().catch((err) => {
  console.error('Seed failed:', err.message);
  process.exit(1);
});
