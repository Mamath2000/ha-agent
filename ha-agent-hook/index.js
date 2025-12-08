const express = require('express');
const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');
const { platform } = require('os');

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

// Cache pour suivre l'état et le dernier contact de chaque appareil
const deviceStatus = {};
const PING_TIMEOUT = 15000; // 15 secondes en millisecondes
const DISCOVERY_INTERVAL = 6 * 60 * 60 * 1000; // 6 heures en millisecondes

// =============================================================================
// CONNEXION MQTT
// =============================================================================
const mqttOptions = {
    username: MQTT_USERNAME,
    password: MQTT_PASSWORD,
};

const client = mqtt.connect(MQTT_BROKER_URL, mqttOptions);

client.on('connect', () => {
    console.log(`Connecté au broker MQTT: ${MQTT_BROKER_URL}`);
});

client.on('error', (err) => {
    console.error('Erreur de connexion MQTT:', err);
});

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
// LOGIQUE DE DÉCOUVERTE (inspirée de votre script original)
// =============================================================================
function getDiscoveryConfig(deviceData) {
    const hostname = (deviceData.hostname).trim();
    const objectId = hostname
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '') || 'ha_agent_device';

    const stateTopic = `${BASE_TOPIC}/${objectId}/state`;
    const sensorsTopic = `${BASE_TOPIC}/${objectId}/sensors`;
    const availabilityTopic = `${BASE_TOPIC}/${objectId}/status`;

    const device = {
        identifiers: [`ha_agent_${objectId}`],
        name: hostname,
        model: "Windows PC Agent",
        manufacturer: "Node.js Hook",
        sw_version: "1.0.0"
    };

    // Définition de tous les capteurs
    const components = {
        pc_running: {
            platform: 'binary_sensor',
            name: 'Running',
            unique_id: `ha_agent_${objectId}_pc_running`,
            object_id: `${objectId}_pc_running`,
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
            object_id: `${objectId}_users_logged_in`,
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
            object_id: `${objectId}_users_count`,
            icon: 'mdi:account-group',
            state_topic: stateTopic,
            value_template: '{{ value_json.logged_users_count }}',
            state_class: 'measurement'
        },
        users_list: {
            platform: 'sensor',
            name: 'Logged Users',
            unique_id: `ha_agent_${objectId}_users_list`,
            object_id: `${objectId}_users_list`,
            icon: 'mdi:account-details',
            state_topic: stateTopic,
            value_template: '{{ value_json.logged_users }}'
        },
        ram_percent: {
            platform: 'sensor',
            name: 'Memory Usage',
            unique_id: `ha_agent_${objectId}_ram_percent`,
            object_id: `${objectId}_ram_percent`,
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
            object_id: `${objectId}_disk_percent`,
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
            object_id: `${objectId}_session_locked`,
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
            object_id: `${objectId}_interactive`,
            // device_class: 'lock',
            state_topic: stateTopic,
            value_template: '{{ value_json.session_locked and value_json.users_logged_in }}',
            payload_on: false,
            payload_off: true
        }
    };

    // On génère la configuration complète pour chaque composant
    const fullConfig = {
        device: device,
        origin: { name: "HA-Agent Hook" },
        availability: [
            { topic: availabilityTopic, payload_on: 'online', payload_off: 'offline' }
        ],
        availability_mode: "all",
        components: components
    };

    return fullConfig;
}

// =============================================================================
// SERVEUR WEB (Express)
// =============================================================================
const app = express();

// Utiliser express.text() pour capturer le body complet
app.use('/ha-agent', express.text({ type: 'application/json', limit: '10mb' }));

app.post('/ha-agent', (req, res) => {
    const rawBody = req.body;

    // LOG DE DEBUG : toujours afficher le flux brut reçu
    console.log('📥 FLUX REÇU:');
    console.log('Raw body:', rawBody);
    console.log('Body length:', rawBody ? rawBody.length : 0);
    console.log('Body type:', typeof rawBody);
    console.log('---');

    try {
        let data;

        // Parser manuellement le JSON
        try {
            data = JSON.parse(rawBody);
            console.log('✅ JSON parsé avec succès');
        } catch (parseError) {
            console.error('❌ ERREUR JSON - Parsing échoué:');
            console.error('Parse error:', parseError.message);
            console.error('---');
            return res.status(400).send('JSON invalide');
        }

        if (!data || !data.device_id) {
            console.warn('⚠️ DONNÉES INVALIDES:');
            console.warn('Parsed body:', JSON.stringify(data, null, 2));
            console.warn('---');
            return res.status(400).send('Données invalides, device_id manquant.');
        }

        const hostname = (data.hostname).trim();
        const objectId = hostname
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '_')
            .replace(/^_+|_+$/g, '') || 'ha_agent_device';

        const now = Date.now();

        // Mettre à jour le statut et le timestamp de l'appareil
        if (!deviceStatus[objectId]) {
            deviceStatus[objectId] = {
                lastSeen: now,
                status: 'online',
                lastDiscovery: 0 // 0 pour forcer la publication au premier contact
            };
        } else {
            deviceStatus[objectId].lastSeen = now;
            deviceStatus[objectId].status = 'online';
        }


        // --- 1. Publication de la découverte (première fois ou toutes les 6 heures) ---
        const shouldPublishDiscovery = (now - deviceStatus[objectId].lastDiscovery) > DISCOVERY_INTERVAL;

        if (shouldPublishDiscovery) {
            console.log(`Publication de la découverte pour ${objectId}...`);
            const discoveryConfigs = getDiscoveryConfig(data);
            const discoveryTopic = `homeassistant/device/ha-agent/${objectId}/config`;


            client.publish(discoveryTopic, JSON.stringify(discoveryConfigs), { retain: true }, (err) => {
                if (err) {
                    console.error(`Erreur lors de la publication de la découverte pour ${objectId}:`, err);
                }
            });

            deviceStatus[objectId].lastDiscovery = now;
            console.log(`Découverte publiée pour ${objectId}.`);
        }

        // --- 2. Publication de la disponibilité et des états ---
        const availabilityTopic = `${BASE_TOPIC}/${objectId}/status`;
        const stateTopic = `${BASE_TOPIC}/${objectId}/state`;
        const sensorsTopic = `${BASE_TOPIC}/${objectId}/sensors`;

        // Toujours publier la disponibilité 'online' quand on reçoit des données
        client.publish(availabilityTopic, 'online', { retain: true });

        // Si ce n'est pas juste un ping, publier les données
        if (data.status !== 'online' && data.status !== 'error') {
            // États principaux
            const statePayload = {
                users_logged_in: data.users_logged_in,
                logged_users_count: data.logged_users_count,
                logged_users: data.logged_users,
                session_locked: data.session_locked
            };
            client.publish(stateTopic, JSON.stringify(statePayload));

            // États des capteurs
            if (data.sensors) {
                client.publish(sensorsTopic, JSON.stringify(data.sensors));
            }
            console.log(`Données d'état complètes reçues et publiées pour ${objectId}`);
        }
        // Gérer le cas d'une erreur remontée par l'agent
        else if (data.status === 'error') {
            console.error(`Erreur remontée par l'agent ${objectId}: ${data.error}`);
            // Ici, vous pourriez publier sur un topic d'erreur spécifique si nécessaire
        }
        // C'est un simple ping, on ne fait rien de plus
        else {
            console.log(`Ping reçu de ${objectId}.`);
        }

        res.status(200).send('Données reçues');

    } catch (error) {
        console.error('❌ ERREUR SERVEUR:');
        console.error('Erreur:', error.message);
        console.error('Stack:', error.stack);
        console.error('---');
        res.status(500).send('Erreur interne du serveur');
    }
});

app.get('/', (req, res) => {
    res.send('HA-Agent Hook est en cours d\'exécution.');
});

app.listen(PORT, () => {
    console.log(`Serveur HA-Agent Hook démarré sur le port ${PORT}`);
});
