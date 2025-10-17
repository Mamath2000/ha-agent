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

// Cache en mémoire pour savoir quels appareils ont déjà été découverts
const publishedDevices = new Set();

// =============================================================================
// LOGIQUE DE DÉCOUVERTE (inspirée de votre script original)
// =============================================================================
function getDiscoveryConfig(deviceData) {
    const deviceId = deviceData.device_id;
    const hostname = deviceData.hostname;

    const stateTopic = `${BASE_TOPIC}/${deviceId}/state`;
    const sensorsTopic = `${BASE_TOPIC}/${deviceId}/sensors`;
    const availabilityTopic = `${BASE_TOPIC}/${deviceId}/status`;

    const device = {
        identifiers: [`ha_agent_${deviceId}`],
        name: hostname,
        model: "Windows PC Agent",
        manufacturer: "Node.js Hook",
        sw_version: "1.0.0",
        connections: deviceData.mac_address ? [["mac", deviceData.mac_address]] : [],
    };

    // Définition de tous les capteurs
    const components = {
        pc_running: { type: 'binary_sensor', name: 'Running', device_class: 'running', state_topic: availabilityTopic, payload_on: 'online', payload_off: 'offline' },
        users_logged_in: { type: 'binary_sensor', name: 'Users Logged In', device_class: 'occupancy', state_topic: stateTopic, value_template: '{{ value_json.users_logged_in }}', payload_on: true, payload_off: false },
        users_count: { type: 'sensor', name: 'Users Count', icon: 'mdi:account-group', state_topic: stateTopic, value_template: '{{ value_json.logged_users_count }}', state_class: 'measurement' },
        users_list: { type: 'sensor', name: 'Logged Users', icon: 'mdi:account-details', state_topic: stateTopic, value_template: '{{ value_json.logged_users }}' },
        cpu_percent: { type: 'sensor', name: 'CPU Usage', icon: 'mdi:cpu-64-bit', unit_of_measurement: '%', state_topic: sensorsTopic, value_template: '{{ value_json.cpu_percent }}', state_class: 'measurement' },
        ram_percent: { type: 'sensor', name: 'Memory Usage', icon: 'mdi:memory', unit_of_measurement: '%', state_topic: sensorsTopic, value_template: '{{ value_json.ram_percent }}', state_class: 'measurement' },
        disk_percent: { type: 'sensor', name: 'Disk Usage', icon: 'mdi:harddisk', unit_of_measurement: '%', state_topic: sensorsTopic, value_template: '{{ value_json.disk_percent }}', state_class: 'measurement' },
    };

    // On génère la configuration complète pour chaque composant
    const fullConfig = {};
    for (const [key, value] of Object.entries(components)) {
        fullConfig[key] = {
            ...value,
            name: `${hostname} ${value.name}`,
            unique_id: `${deviceId}_${key}`,
            availability_topic: availabilityTopic,
            device: device,
        };
    }
    return fullConfig;
}

// =============================================================================
// SERVEUR WEB (Express)
// =============================================================================
const app = express();
app.use(express.json());

app.post('/ha-agent', (req, res) => {
  const data = req.body;

  if (!data || !data.device_id) {
    console.warn('Données invalides reçues:', data);
    return res.status(400).send('Données invalides, device_id manquant.');
  }

  const deviceId = data.device_id;

  // --- 1. Publication de la découverte (si c'est la première fois) ---
  if (!publishedDevices.has(deviceId)) {
    console.log(`Nouveau périphérique détecté: ${deviceId}. Publication de la découverte...`);
    const discoveryConfigs = getDiscoveryConfig(data);

    for (const [key, config] of Object.entries(discoveryConfigs)) {
      const componentType = config.type;
      const discoveryTopic = `homeassistant/${componentType}/ha-agent/${deviceId}_${key}/config`;
      
      // On retire la clé "type" qui n'est pas utile dans le payload final
      delete config.type;

      client.publish(discoveryTopic, JSON.stringify(config), { retain: true }, (err) => {
        if (err) {
          console.error(`Erreur lors de la publication de la découverte pour ${key}:`, err);
        }
      });
    }
    publishedDevices.add(deviceId);
    console.log(`Découverte publiée pour ${deviceId}.`);
  }

  // --- 2. Publication de la disponibilité et des états ---
  const availabilityTopic = `${BASE_TOPIC}/${deviceId}/status`;
  const stateTopic = `${BASE_TOPIC}/${deviceId}/state`;
  const sensorsTopic = `${BASE_TOPIC}/${deviceId}/sensors`;

  // Disponibilité
  client.publish(availabilityTopic, 'online', { retain: true });

  // États principaux
  const statePayload = {
    users_logged_in: data.users_logged_in,
    logged_users_count: data.logged_users_count,
    logged_users: data.logged_users,
  };
  client.publish(stateTopic, JSON.stringify(statePayload));

  // États des capteurs
  if (data.sensors) {
    client.publish(sensorsTopic, JSON.stringify(data.sensors));
  }
  
  console.log(`Données d'état reçues et publiées pour ${deviceId}`);
  res.status(200).send('Données reçues');
});

app.get('/', (req, res) => {
    res.send('HA-Agent Hook est en cours d\'exécution.');
});

app.listen(PORT, () => {
  console.log(`Serveur HA-Agent Hook démarré sur le port ${PORT}`);
});
