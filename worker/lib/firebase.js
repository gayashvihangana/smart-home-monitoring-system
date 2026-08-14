/**
 * Admin SDK bootstrap.
 *
 * The Admin SDK bypasses security rules entirely. That is what lets the worker
 * write the server-owned fields (devices/<id>/runtime, usageDaily) that clients
 * are rejected from by the `.validate: false` guards in
 * firebase/database.rules.json.
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '..', '.env') });
const admin = require('firebase-admin');
const log = require('./log');

const DB_URL = process.env.FIREBASE_DB_URL;
const HOME_ID = process.env.HOME_ID || 'home1';

if (!DB_URL) {
  log.error('FIREBASE_DB_URL is not set. Copy .env.example to .env and fill it in.');
  process.exit(1);
}
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  log.error('GOOGLE_APPLICATION_CREDENTIALS is not set. Point it at the service-account JSON.');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: DB_URL,
});

const db = admin.database();
const TIMESTAMP = admin.database.ServerValue.TIMESTAMP;

/**
 * Client clocks drift, and a safety cutoff that fires at the wrong time is worse
 * than no cutoff at all. Firebase exposes the difference between this machine's
 * clock and the server's, so we can reason in server time everywhere.
 */
let serverOffset = 0;
db.ref('.info/serverTimeOffset').on('value', (snap) => {
  const next = snap.val() || 0;
  if (Math.abs(next - serverOffset) > 1000) {
    log.info(`server clock offset: ${next} ms`);
  }
  serverOffset = next;
});

const serverNow = () => Date.now() + serverOffset;

const homeRef = db.ref(`homes/${HOME_ID}`);
const devicesRef = homeRef.child('devices');

module.exports = { admin, db, homeRef, devicesRef, HOME_ID, TIMESTAMP, serverNow };
