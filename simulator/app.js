import {
    ref,
    onValue,
    update,
    serverTimestamp,
    onDisconnect
} from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-database.js';

const HOME_ID = 'home1';

let database;
const registeredPresence = new Set();

// Latest snapshot of each device, kept so the hazard countdown can tick once a
// second without waiting for a database event.
const deviceCache = new Map();

// deviceId -> online. DISCONNECTED is DERIVED from this, never stored on the
// device itself: presence is what the hardware reports, status is what it was
// last told to do, and the two are different questions.
const presenceState = new Map();

export function setupSimulator(db) {
    database = db;
    watchPresence();
    watchDevices();
    startHazardTicker();
}

function watchDevices() {
    const devicesRef = ref(database, `homes/${HOME_ID}/devices`);

    onValue(devicesRef, (snapshot) => {
        const devices = snapshot.val();
        const container = document.getElementById('devices');

        if (!devices) {
            container.innerHTML = `<p>No devices found in ${HOME_ID}</p>`;
            return;
        }

        const deviceIds = Object.keys(devices);

        // Remove elements that are no longer in the database
        Array.from(container.children).forEach(el => {
            if (!deviceIds.includes(el.id)) {
                container.removeChild(el);
                registeredPresence.delete(el.id);
                deviceCache.delete(el.id);
            }
        });

        deviceIds.forEach(id => {
            const deviceData = { ...devices[id], id };
            deviceCache.set(id, deviceData);
            render(deviceData);
            setupPresence(id);
        });

        setStatusLine(`Connected to ${HOME_ID} — ${deviceIds.length} devices`, 'green');
    }, (error) => {
        console.error(error);
        setStatusLine('Error: ' + error.message, 'red');
    });
}

// The simulator stands in for all the physical hardware, so it claims presence
// on behalf of every device. Closing this tab marks them all offline.
function watchPresence() {
    onValue(ref(database, 'presence'), (snapshot) => {
        const all = snapshot.val() || {};
        Object.keys(all).forEach(id => presenceState.set(id, all[id].online !== false));
        deviceCache.forEach(device => render(device));
    });
}

function setupPresence(deviceId) {
    if (registeredPresence.has(deviceId)) return;

    const presenceRef = ref(database, `presence/${deviceId}`);

    // Register the onDisconnect handler BEFORE writing online: true. Firebase
    // runs it server-side when the socket drops, so if we wrote online first and
    // crashed in the gap, the device would be stuck online forever.
    onDisconnect(presenceRef).update({
        online: false,
        lastSeen: serverTimestamp()
    }).then(() => {
        update(presenceRef, {
            online: true,
            lastSeen: serverTimestamp()
        });
        registeredPresence.add(deviceId);
    });
}

/** Presence beats status: an unreachable device is DISCONNECTED whatever it was told. */
function effectiveStatus(device) {
    if (presenceState.get(device.id) === false) return 'DISCONNECTED';
    return device.status || 'OFF';
}

/** A gang box is one unit with N channels, and reads ON if ANY channel is on. */
function isDeviceOn(device) {
    if (device.type === 'multiswitch') {
        return Object.values(device.channels || {}).some(c => c && c.state === 'ON');
    }
    return device.status === 'ON';
}

function render(device) {
    let el = document.getElementById(device.id);

    if (!el) {
        el = document.createElement('div');
        el.id = device.id;
        document.getElementById('devices').appendChild(el);
    }

    const status = effectiveStatus(device);
    const isOn = isDeviceOn(device);
    const isFaulted = status === 'ERROR';
    const isOffline = status === 'DISCONNECTED';

    el.className = `device ${device.type} ${status.toLowerCase()}`;

    let typeSpecificHtml = '';

    if (device.type === 'multiswitch') {
        const channels = device.channels || {};
        typeSpecificHtml = '<div class="switches">' +
            Object.keys(channels).map(ch => `
                <button class="rocker ${channels[ch].state === 'ON' ? 'on' : 'off'}"
                        onclick="window.toggleSubSwitch('${device.id}', '${ch}', '${channels[ch].state === 'ON' ? 'OFF' : 'ON'}')">
                    ${channels[ch].label || 'Switch ' + ch}
                </button>
            `).join('') +
            '</div>';
    } else if (device.type === 'hazard') {
        typeSpecificHtml = `<div class="timer">${hazardLabel(device)}</div>`;
    } else if (device.type === 'camera') {
        typeSpecificHtml = `<div class="camera-feed" style="background-image: url('${device.snapshotUri || ''}')"></div>`;
    }

    // A faulted device offers a way back. Without this, forcing ERROR during the
    // demo leaves the device stuck with no way to recover from the simulator.
    const primaryControl = isFaulted
        ? `<button onclick="window.clearFault('${device.id}')">Clear fault</button>`
        : `<button onclick="window.toggleDevice('${device.id}', '${isOn ? 'OFF' : 'ON'}')" ${isOffline ? 'disabled' : ''}>
               ${isOn ? 'Turn OFF' : 'Turn ON'}
           </button>`;

    el.innerHTML = `
        <span class="name">${device.name || device.id}</span>
        <span class="type-icon">${getTypeIcon(device.type)}</span>
        <span class="status-pill">${status}</span>
        ${typeSpecificHtml}
        <div class="controls">${primaryControl}</div>
        <div class="fault-controls">
            <button class="fault-btn" onclick="window.injectFault('${device.id}')">Force ERROR</button>
            <button class="fault-btn" onclick="window.setPresence('${device.id}', ${isOffline})">
                ${isOffline ? 'Reconnect' : 'Disconnect'}
            </button>
        </div>
    `;
}

/**
 * Time left before the safety worker cuts this device off. runtime.onSince is
 * stamped by the worker, and config.maxOnDurationSec is the configured limit —
 * this is display only, the actual cutoff happens server-side.
 */
function hazardLabel(device) {
    const startedAt = device.runtime && device.runtime.onSince;
    const limitSec = (device.config && device.config.maxOnDurationSec) || 0;

    if (device.status !== 'ON' || !startedAt || !limitSec) return '--:--';

    const elapsed = Math.floor((Date.now() - startedAt) / 1000);
    const remaining = Math.max(0, limitSec - elapsed);
    const mm = String(Math.floor(remaining / 60)).padStart(2, '0');
    const ss = String(remaining % 60).padStart(2, '0');
    return `cutoff in ${mm}:${ss}`;
}

// The countdown has to move every second, but device data only arrives when
// something actually changes — so it is driven from the cache, not from Firebase.
function startHazardTicker() {
    setInterval(() => {
        deviceCache.forEach(device => {
            if (device.type !== 'hazard') return;
            const el = document.getElementById(device.id);
            const timer = el && el.querySelector('.timer');
            if (timer) timer.textContent = hazardLabel(device);
        });
    }, 1000);
}

function setStatusLine(text, colour) {
    const el = document.getElementById('connection-status');
    el.textContent = text;
    el.className = 'status-badge';
    if (colour === 'green') {
        el.classList.add('connected');
    } else if (colour === 'red') {
        el.classList.add('error');
    } else {
        el.classList.add('connecting');
    }
}

function getTypeIcon(type) {
    switch (type) {
        case 'bulb': return '💡';
        case 'outlet': return '🔌';
        case 'multiswitch': return '🎛️';
        case 'hazard': return '🔥';
        case 'camera': return '📷';
        default: return '📱';
    }
}

// --- writes back to the database -------------------------------------------
// Every write records lastChangedBy so it is provable which side caused a
// change. This is what demonstrates that synchronisation is bidirectional.

window.toggleDevice = (deviceId, newStatus) => {
    update(ref(database, `homes/${HOME_ID}/devices/${deviceId}`), {
        status: newStatus,
        lastChangedBy: 'simulator',
        lastChangedAt: serverTimestamp()
    });
};

window.toggleSubSwitch = (deviceId, channelKey, newState) => {
    // One multi-path update, so the channel and the unit's metadata can never
    // be observed out of step with each other.
    update(ref(database, `homes/${HOME_ID}/devices/${deviceId}`), {
        [`channels/${channelKey}/state`]: newState,
        [`channels/${channelKey}/lastChangedAt`]: serverTimestamp(),
        lastChangedBy: 'simulator',
        lastChangedAt: serverTimestamp()
    });
};

window.injectFault = (deviceId) => {
    update(ref(database, `homes/${HOME_ID}/devices/${deviceId}`), {
        status: 'ERROR',
        lastChangedBy: 'simulator',
        lastChangedAt: serverTimestamp()
    });
};

window.clearFault = (deviceId) => {
    update(ref(database, `homes/${HOME_ID}/devices/${deviceId}`), {
        status: 'OFF',
        lastChangedBy: 'simulator',
        lastChangedAt: serverTimestamp()
    });
};

// Disconnecting writes presence, NOT status. A disconnected device has not been
// switched off — nobody can reach it — and the app derives DISCONNECTED from here.
window.setPresence = (deviceId, online) => {
    update(ref(database, `presence/${deviceId}`), {
        online: online,
        lastSeen: serverTimestamp()
    });
};

/**
 * Global control: sends OFF to all devices.
 */
window.powerOffAll = () => {
    const updates = {};
    deviceCache.forEach(device => {
        if (effectiveStatus(device) !== 'DISCONNECTED') {
            updates[`homes/${HOME_ID}/devices/${device.id}/status`] = 'OFF';
            updates[`homes/${HOME_ID}/devices/${device.id}/lastChangedBy`] = 'simulator';
            updates[`homes/${HOME_ID}/devices/${device.id}/lastChangedAt`] = serverTimestamp();
            
            // Turn off channels if multiswitch
            if (device.type === 'multiswitch' && device.channels) {
                Object.keys(device.channels).forEach(ch => {
                    updates[`homes/${HOME_ID}/devices/${device.id}/channels/${ch}/state`] = 'OFF';
                    updates[`homes/${HOME_ID}/devices/${device.id}/channels/${ch}/lastChangedAt`] = serverTimestamp();
                });
            }
        }
    });
    if (Object.keys(updates).length > 0) {
        update(ref(database), updates);
    }
};

/**
 * Global control: toggles connection state for all devices to simulate outage.
 */
window.disconnectAll = () => {
    // Check if any device is currently online. If so, disconnect all. Else reconnect all.
    let anyOnline = false;
    deviceCache.forEach(device => {
        if (presenceState.get(device.id) !== false) anyOnline = true;
    });
    
    const newOnlineState = !anyOnline;
    const updates = {};
    deviceCache.forEach(device => {
        updates[`presence/${device.id}/online`] = newOnlineState;
        updates[`presence/${device.id}/lastSeen`] = serverTimestamp();
    });
    if (Object.keys(updates).length > 0) {
        update(ref(database), updates);
    }
};
