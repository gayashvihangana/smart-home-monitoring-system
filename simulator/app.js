import { ref, onValue, update, serverTimestamp, onDisconnect } from 'https://www.gstatic.com/firebasejs/10.12.0/firebase-database.js';

const HOME_ID = 'home_01'; // Default, update if Member B used a different ID
let database;
const registeredPresence = new Set();

export function setupSimulator(db) {
    database = db;
    const devicesRef = ref(db, `homes/${HOME_ID}/devices`);

    onValue(devicesRef, (snapshot) => {
        const devices = snapshot.val();
        const container = document.getElementById('devices');

        if (devices) {
            const deviceIds = Object.keys(devices);

            // Remove elements that are no longer in the database
            Array.from(container.children).forEach(el => {
                if (!deviceIds.includes(el.id)) {
                    container.removeChild(el);
                    registeredPresence.delete(el.id);
                }
            });

            // Render/Update devices
            deviceIds.forEach(id => {
                const deviceData = { ...devices[id], id };
                render(deviceData);
                setupPresence(id);
            });
            document.getElementById('connection-status').textContent = 'Connected to ' + HOME_ID;
            document.getElementById('connection-status').style.color = 'green';
        } else {
            container.innerHTML = '<p>No devices found in ' + HOME_ID + '</p>';
        }
    }, (error) => {
        console.error(error);
        document.getElementById('connection-status').textContent = 'Error: ' + error.message;
        document.getElementById('connection-status').style.color = 'red';
    });
}

function setupPresence(deviceId) {
    if (registeredPresence.has(deviceId)) return;

    const presenceRef = ref(database, `presence/${deviceId}`);

    // Phase 3 - Step C5: Presence heartbeat + onDisconnect
    // Register the onDisconnect handler BEFORE writing online: true
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

function render(device) {
    let el = document.getElementById(device.id);

    if (!el) {
        const container = document.getElementById('devices');
        el = document.createElement('div');
        el.id = device.id;
        container.appendChild(el);
    }

    const isWorking = device.status !== 'ERROR' && device.status !== 'DISCONNECTED';
    const isOn = device.status === 'ON';

    el.className = `device ${device.type} ${device.status?.toLowerCase() || 'off'}`;

    // Specific rendering based on type
    let typeSpecificHtml = '';
    if (device.type === 'multiswitch') {
        // Handle multiswitch rocker switches if they exist
        const switches = device.switches || {};
        typeSpecificHtml = '<div class="switches">' +
            Object.keys(switches).map(sKey => `
                <button class="rocker ${switches[sKey] ? 'on' : 'off'}"
                        onclick="window.toggleSubSwitch('${device.id}', '${sKey}', ${!switches[sKey]})">
                    ${sKey}
                </button>
            `).join('') +
            '</div>';
    } else if (device.type === 'hazard') {
        typeSpecificHtml = `<div class="timer">${device.activeTime || '00:00'}</div>`;
    } else if (device.type === 'camera') {
        typeSpecificHtml = `<div class="camera-feed" style="background-image: url('${device.snapshot || ''}')"></div>`;
    }

    el.innerHTML = `
        <span class="name">${device.name || device.id}</span>
        <span class="type-icon">${getTypeIcon(device.type)}</span>
        ${typeSpecificHtml}
        <div class="controls">
            <button onclick="window.toggleDevice('${device.id}', '${isOn ? 'OFF' : 'ON'}')" ${!isWorking ? 'disabled' : ''}>
                ${isOn ? 'Turn OFF' : 'Turn ON'}
            </button>
        </div>
        <div class="fault-controls">
            <button class="fault-btn" onclick="window.injectFault('${device.id}', 'ERROR')">Force ERROR</button>
            <button class="fault-btn" onclick="window.injectFault('${device.id}', 'DISCONNECTED')">Disconnect</button>
        </div>
    `;
}

function getTypeIcon(type) {
    switch(type) {
        case 'bulb': return '💡';
        case 'outlet': return '🔌';
        case 'multiswitch': return '🎛️';
        case 'hazard': return '🔥';
        case 'camera': return '📷';
        default: return '📱';
    }
}

// Global functions for button clicks
window.toggleDevice = (deviceId, newStatus) => {
    update(ref(database, `homes/${HOME_ID}/devices/${deviceId}`), {
        status: newStatus,
        lastChangedBy: 'simulator',
        lastChangedAt: serverTimestamp()
    });
};

window.toggleSubSwitch = (deviceId, switchKey, newState) => {
    update(ref(database, `homes/${HOME_ID}/devices/${deviceId}/switches`), {
        [switchKey]: newState
    });
};

window.injectFault = (deviceId, faultStatus) => {
    update(ref(database, `homes/${HOME_ID}/devices/${deviceId}`), {
        status: faultStatus,
        lastChangedBy: 'simulator',
        lastChangedAt: serverTimestamp()
    });
};
