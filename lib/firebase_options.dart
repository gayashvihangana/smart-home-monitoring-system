// Firebase configuration for the Smart Home Monitoring & Control System.
//
// NOTE FOR MEMBER A: this file was written by hand from the project's web app
// config so the data layer could be built and tested before the Android app was
// registered. Once you have Firebase CLI access, run:
//
//     dart pub global activate flutterfire_cli
//     flutterfire configure
//
// and pick project `smart-home-monitoring-sy-75fd9`. That registers a proper
// Android app, writes google-services.json, and regenerates this file with a
// platform-specific appId. Replace this file wholesale when you do — nothing
// else needs to change, everything imports DefaultFirebaseOptions.
//
// These values are not secret. The API key ships inside every APK by design;
// access is controlled by the database security rules in firebase/, not by
// hiding this file.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'AIzaSyBpwsPlYkD6DzkgTliOYz_RpZPZOiunAtE',
    appId: '1:1008139955420:web:2da644290eb4f2c3f5d819',
    messagingSenderId: '1008139955420',
    projectId: 'smart-home-monitoring-sy-75fd9',
    authDomain: 'smart-home-monitoring-sy-75fd9.firebaseapp.com',
    databaseURL:
        'https://smart-home-monitoring-sy-75fd9-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'smart-home-monitoring-sy-75fd9.firebasestorage.app',
    measurementId: 'G-Y43XTL6Y5L',
  );
}

/// The home this build talks to. Single-home project, so it is a constant rather
/// than something the user picks.
const String kHomeId = 'home1';
