# smart-home-monitoring-system

A real-time smart home monitoring system with a Flutter mobile app and a web-based device simulator.

## Project Structure

- `simulator/`: Web-based device simulator (Plain HTML/JS)
    - `index.html`: Main entry point
    - `app.js`: Firebase integration and rendering logic
    - `style.css`: Simulator visuals
    - `firebase-config.js`: Firebase project configuration (Managed by Member B)

## Simulator (Member C)

The simulator provides a virtual representation of hardware devices, allowing for bi-directional synchronization with the mobile app via Firebase Realtime Database.

**Status:** Phase 3 (Advanced Features) in progress. Simulator connected to Firebase.
