const express = require('express');
const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');

// =============================================================================
// CONFIGURATION (depuis config.json)
// =============================================================================
let config;
try {
    const configPath = path.join(__dirname, 'config.json');
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (error) {
    console.error('Erreur: Impossible de lire ou parser le fichier config.json.', error);
    process.exit(1); // Arrête l'application si la config est manquante
}

const PORT = config.port || 3000;
const MQTT_BROKER_URL = config.mqtt_broker_url;
const MQTT_USERNAME = config.mqtt_username;
const MQTT_PASSWORD = config.mqtt_password;
const BASE_TOPIC = 'ha-agent';

const PING_TIMEOUT = 15000; // 15 secondes en millisecondes
const DISCOVERY_INTERVAL = 6 * 60 * 60 * 1000; // 6 heures en millisecondes
const PAIRING_TIMEOUT = 5 * 60 * 1000; // 5 minutes en millisecondes

// =============================================================================
// PERSISTANCE DES DEVICES ASSOCIÉS
// =============================================================================
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const DEVICES_FILE = path.join(DATA_DIR, 'devices.json');

function loadDevices() {
    try {
        return JSON.parse(fs.readFileSync(DEVICES_FILE, 'utf8'));
    } catch (error) {
        return {};
    }
}

function saveDevices() {
    try {
        fs.mkdirSync(DATA_DIR, { recursive: true });
        fs.writeFileSync(DEVICES_FILE, JSON.stringify(devices, null, 2));
    } catch (error) {
        console.error('Erreur lors de la sauvegarde de devices.json:', error);
    }
}

// devices : appareils associés, persistés sur disque -> { [objectId]: { hostname, associatedAt, lastData } }
const devices = loadDevices();

// deviceStatus : suivi en mémoire du online/offline (non persisté, reconstruit à chaque démarrage)
const deviceStatus = {};

// pairingMode : fenêtre d'association ouverte (accepte tout nouveau device pendant PAIRING_TIMEOUT)
let pairingMode = false;
let pairingTimer = null;

// =============================================================================
// CONNEXION MQTT
// =============================================================================
const HOOK_STATUS_TOPIC = `${BASE_TOPIC}/hook/status`;
const PAIRING_COMMAND_TOPIC = `${BASE_TOPIC}/hook/pairing/set`;
const PAIRING_STATE_TOPIC = `${BASE_TOPIC}/hook/pairing/state`;
const HOOK_VERSION_TOPIC = `${BASE_TOPIC}/hook/version`;

const mqttOptions = {
    username: MQTT_USERNAME,
    password: MQTT_PASSWORD,
    will: { topic: HOOK_STATUS_TOPIC, payload: 'offline', retain: true, qos: 0 }
};

const client = mqtt.connect(MQTT_BROKER_URL, mqttOptions);

client.on('connect', () => {
    console.log(`Connecté au broker MQTT: ${MQTT_BROKER_URL}`);

    client.publish(HOOK_STATUS_TOPIC, 'online', { retain: true });
    client.subscribe(PAIRING_COMMAND_TOPIC);

    publishHookDiscovery();
    publishPairingState();

    // Au démarrage : republier la découverte + les dernières infos connues de chaque device associé
    republishAllKnownDevices('démarrage');
});

client.on('error', (err) => {
    console.error('Erreur de connexion MQTT:', err);
});

client.on('message', (topic, message) => {
    if (topic === PAIRING_COMMAND_TOPIC) {
        const payload = message.toString().trim().toUpperCase();
        if (payload === 'ON') {
            setPairingMode(true);
        } else if (payload === 'OFF') {
            setPairingMode(false);
        }
    }
});

// Republication périodique (toutes les 6h), indépendante des messages reçus
setInterval(() => republishAllKnownDevices('cycle 6h'), DISCOVERY_INTERVAL);

// Fonction pour vérifier les appareils inactifs
setInterval(() => {
    const now = Date.now();
    for (const deviceId in deviceStatus) {
        if (deviceStatus[deviceId].status === 'online' && (now - deviceStatus[deviceId].lastSeen > PING_TIMEOUT)) {
            console.log(`Appareil ${deviceId} considéré comme hors ligne (timeout).`);
            deviceStatus[deviceId].status = 'offline';
            const availabilityTopic = `${BASE_TOPIC}/${deviceId}/status`;
            client.publish(availabilityTopic, 'offline', { retain: true });
        }
    }
}, PING_TIMEOUT);

// =============================================================================
// MODE ASSOCIATION (PAIRING)
// =============================================================================
function setPairingMode(enabled) {
    pairingMode = enabled;
    clearTimeout(pairingTimer);

    if (enabled) {
        console.log(`Mode association activé pour ${PAIRING_TIMEOUT / 60000} minutes.`);
        pairingTimer = setTimeout(() => setPairingMode(false), PAIRING_TIMEOUT);
    } else {
        console.log('Mode association désactivé.');
    }

    publishPairingState();
}

function publishPairingState() {
    client.publish(PAIRING_STATE_TOPIC, pairingMode ? 'ON' : 'OFF', { retain: true });
}

function publishHookDiscovery() {
    const version = require('./package.json').version;

    const discoveryConfig = {
        device: {
            identifiers: ['ha_agent_hook'],
            name: 'HA-Agent Hook',
            model: 'Webhook Bridge',
            manufacturer: 'Node.js Hook',
            sw_version: version
        },
        origin: { name: 'HA-Agent Hook' },
        availability: [
            { topic: HOOK_STATUS_TOPIC, payload_available: 'online', payload_not_available: 'offline' }
        ],
        components: {
            pairing_mode: {
                platform: 'switch',
                name: 'Pairing Mode',
                unique_id: 'ha_agent_hook_pairing_mode',
                icon: 'mdi:link-plus',
                command_topic: PAIRING_COMMAND_TOPIC,
                state_topic: PAIRING_STATE_TOPIC,
                payload_on: 'ON',
                payload_off: 'OFF'
            },
            docker_version: {
                platform: 'sensor',
                name: 'Docker Version',
                unique_id: 'ha_agent_hook_docker_version',
                icon: 'mdi:docker',
                state_topic: HOOK_VERSION_TOPIC
            }
        }
    };

    const discoveryTopic = `homeassistant/device/ha-agent/hook/config`;
    client.publish(discoveryTopic, JSON.stringify(discoveryConfig), { retain: true });
    client.publish(HOOK_VERSION_TOPIC, version, { retain: true });
}

// =============================================================================
// LOGIQUE DE DÉCOUVERTE DES DEVICES AGENTS (inspirée de votre script original)
// =============================================================================
function getDiscoveryConfig(hostname, objectId) {
    const stateTopic = `${BASE_TOPIC}/${objectId}/state`;
    const sensorsTopic = `${BASE_TOPIC}/${objectId}/sensors`;
    const availabilityTopic = `${BASE_TOPIC}/${objectId}/status`;

    const device = {
        identifiers: [`ha_agent_${objectId}`],
        name: hostname,
        model: "Windows PC Agent",
        manufacturer: "Node.js Hook",
        sw_version: "1.0.0",
        via_device: 'ha_agent_hook'
    };

    // Définition de tous les capteurs
    const components = {
        pc_running: {
            platform: 'binary_sensor',
            name: 'Running',
            unique_id: `ha_agent_${objectId}_pc_running`,
            default_entity_id: `binary_sensor.${objectId}_pc_running`,
            device_class: 'running',
            state_topic: availabilityTopic,
            availability: [],
            payload_on: 'online',
            payload_off: 'offline'
        },
        users_logged_in: {
            platform: 'binary_sensor',
            name: 'Users Logged In',
            unique_id: `ha_agent_${objectId}_users_logged_in`,
            default_entity_id: `binary_sensor.${objectId}_users_logged_in`,
            device_class: 'occupancy',
            state_topic: stateTopic,
            value_template: '{{ value_json.users_logged_in }}',
            payload_on: true,
            payload_off: false
        },
        users_count: {
            platform: 'sensor',
            name: 'Users Count',
            unique_id: `ha_agent_${objectId}_users_count`,
            default_entity_id: `sensor.${objectId}_users_count`,
            icon: 'mdi:account-group',
            state_topic: stateTopic,
            value_template: '{{ value_json.logged_users_count }}',
            state_class: 'measurement'
        },
        users_list: {
            platform: 'sensor',
            name: 'Logged Users',
            unique_id: `ha_agent_${objectId}_users_list`,
            default_entity_id: `sensor.${objectId}_users_list`,
            icon: 'mdi:account-details',
            state_topic: stateTopic,
            value_template: '{{ value_json.logged_users }}'
        },
        ram_percent: {
            platform: 'sensor',
            name: 'Memory Usage',
            unique_id: `ha_agent_${objectId}_ram_percent`,
            default_entity_id: `sensor.${objectId}_ram_percent`,
            icon: 'mdi:memory',
            unit_of_measurement: '%',
            state_topic: sensorsTopic,
            value_template: '{{ value_json.ram_percent }}',
            state_class: 'measurement'
        },
        disk_percent: {
            platform: 'sensor',
            name: 'Disk Usage',
            unique_id: `ha_agent_${objectId}_disk_percent`,
            default_entity_id: `sensor.${objectId}_disk_percent`,
            icon: 'mdi:harddisk',
            unit_of_measurement: '%',
            state_topic: sensorsTopic,
            value_template: '{{ value_json.disk_percent }}',
            state_class: 'measurement'
        },
        session_locked: {
            platform: 'binary_sensor',
            name: 'Session Locked',
            unique_id: `ha_agent_${objectId}_session_locked`,
            default_entity_id: `binary_sensor.${objectId}_session_locked`,
            device_class: 'lock',
            state_topic: stateTopic,
            value_template: '{{ value_json.session_locked }}',
            payload_on: false,
            payload_off: true
        },
        interactive: {
            platform: 'binary_sensor',
            name: 'Interactive',
            unique_id: `ha_agent_${objectId}_interactive`,
            default_entity_id: `binary_sensor.${objectId}_interactive`,
            // device_class: 'lock',
            state_topic: stateTopic,
            value_template: '{{ value_json.session_locked and value_json.users_logged_in }}',
            payload_on: false,
            payload_off: true
        }
    };

    // On génère la configuration complète pour chaque composant
    return {
        device: device,
        origin: { name: "HA-Agent Hook" },
        availability: [
            { topic: availabilityTopic, payload_available: 'online', payload_not_available: 'offline' }
        ],
        availability_mode: "all",
        components: components
    };
}

function publishDeviceState(objectId, data) {
    const stateTopic = `${BASE_TOPIC}/${objectId}/state`;
    const sensorsTopic = `${BASE_TOPIC}/${objectId}/sensors`;

    const statePayload = {
        users_logged_in: data.users_logged_in,
        logged_users_count: data.logged_users_count,
        logged_users: data.logged_users,
        session_locked: data.session_locked
    };
    client.publish(stateTopic, JSON.stringify(statePayload), { retain: true });

    if (data.sensors) {
        client.publish(sensorsTopic, JSON.stringify(data.sensors), { retain: true });
    }
}

// Republie la découverte + les dernières données connues pour un device associé
function republishDevice(objectId) {
    const device = devices[objectId];
    if (!device) return;

    const discoveryConfigs = getDiscoveryConfig(device.hostname, objectId);
    const discoveryTopic = `homeassistant/device/ha-agent/${objectId}/config`;
    client.publish(discoveryTopic, JSON.stringify(discoveryConfigs), { retain: true });

    if (device.lastData) {
        publishDeviceState(objectId, device.lastData);
    }
}

function republishAllKnownDevices(reason) {
    const ids = Object.keys(devices);
    if (ids.length === 0) return;

    console.log(`Republication de la découverte pour ${ids.length} device(s) associé(s) (${reason}).`);
    ids.forEach(republishDevice);
}

// =============================================================================
// SERVEUR WEB (Express)
// =============================================================================
const app = express();

// Utiliser express.text() pour capturer le body complet
app.use('/ha-agent', express.text({ type: 'application/json', limit: '10mb' }));

app.post('/ha-agent', (req, res) => {
    const rawBody = req.body;

    let data;
    try {
        data = JSON.parse(rawBody);
    } catch (parseError) {
        console.error('❌ ERREUR JSON - Parsing échoué:', parseError.message);
        return res.status(400).send('JSON invalide');
    }

    if (!data || !data.device_id || !data.hostname) {
        console.warn('⚠️ DONNÉES INVALIDES:', JSON.stringify(data));
        return res.status(400).send('Données invalides, device_id/hostname manquant.');
    }

    const hostname = data.hostname.trim();
    const objectId = hostname
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '') || 'ha_agent_device';

    const now = Date.now();

    // --- Association ---
    const isKnownDevice = !!devices[objectId];

    if (!isKnownDevice) {
        if (!pairingMode) {
            console.warn(`Device inconnu rejeté (mode association désactivé): ${objectId}`);
            return res.status(403).send('Device non associé. Active le mode association dans Home Assistant.');
        }

        console.log(`Nouveau device associé: ${objectId} (${hostname})`);
        devices[objectId] = {
            hostname: hostname,
            associatedAt: now,
            lastData: null
        };
        saveDevices();

        // Découverte immédiate pour ce nouveau device
        republishDevice(objectId);
    }

    // Mettre à jour le statut et le timestamp de l'appareil
    if (!deviceStatus[objectId]) {
        deviceStatus[objectId] = { lastSeen: now, status: 'online' };
    } else {
        deviceStatus[objectId].lastSeen = now;
        deviceStatus[objectId].status = 'online';
    }

    // Toujours publier la disponibilité 'online' quand on reçoit des données
    const availabilityTopic = `${BASE_TOPIC}/${objectId}/status`;
    client.publish(availabilityTopic, 'online', { retain: true });

    // Si ce n'est pas juste un ping/erreur, publier et persister les données
    if (data.status !== 'online' && data.status !== 'error') {
        devices[objectId].lastData = data;
        saveDevices();

        publishDeviceState(objectId, data);
        console.log(`Données d'état complètes reçues et publiées pour ${objectId}`);
    } else if (data.status === 'error') {
        console.error(`Erreur remontée par l'agent ${objectId}: ${data.error}`);
    } else {
        console.log(`Ping reçu de ${objectId}.`);
    }

    res.status(200).send('Données reçues');
});

app.get('/', (req, res) => {
    res.send('HA-Agent Hook est en cours d\'exécution.');
});

app.listen(PORT, () => {
    console.log(`Serveur HA-Agent Hook démarré sur le port ${PORT}`);
});
