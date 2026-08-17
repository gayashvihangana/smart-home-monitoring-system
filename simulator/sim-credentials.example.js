// Copy to sim-credentials.js and fill in the password. NEVER commit
// sim-credentials.js — .gitignore blocks it.
//
// This is the simulator's own device account, created in Firebase Console >
// Authentication > Users. It is not a person's login: it exists so the simulator
// can authenticate, and its UID goes into MEMBER_UIDS in .env so the seed script
// enrols it in homes/<HOME_ID>/meta/members.
//
// Deploying is what publishes this file — `firebase deploy --only hosting` uploads
// the simulator/ folder, and the hosting ignore list in firebase.json does not
// exclude it. Treat the password as public once deployed: give this account
// nothing beyond membership of the demo home.
export const simCredentials = {
  email: 'simulator@shms.local',
  password: '',
};
