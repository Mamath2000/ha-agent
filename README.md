# Home Assistant Agent pour Windows

Script PowerShell pour intégrer un PC Windows avec Home Assistant via MQTT.

## Fonctionnalités

### Détection d'état
- ✅ Vérifier si le PC est démarré
- ✅ Détecter si des utilisateurs sont connectés
- ✅ Obtenir la liste des utilisateurs connectés

### Contrôle à distance
- ✅ Redémarrer le PC
- ✅ Éteindre le PC
- ✅ Mettre en hibernation
- ✅ Mettre en veille
- ✅ Déconnecter les utilisateurs

### Capteurs système
- ✅ Utilisation CPU (%)
- ✅ Utilisation mémoire (GB et %)
- ✅ Utilisation disque C: (GB et %)
- ✅ Nombre de mises à jour Windows en attente

## Fichiers

- `ha-agent.ps` - Script principal avec toutes les fonctions
- `test-functions.ps1` - Script de test des fonctionnalités
- `ha-agent-service.ps1` - Mode service pour exécution continue

## Configuration

Modifiez les variables de configuration dans `ha-agent.ps` :

```powershell
$MQTTBroker = "mqtt://192.168.100.9"  # Adresse de votre broker MQTT
$MQTTUser = ""                        # Nom d'utilisateur MQTT (optionnel)
$MQTTPassword = ""                    # Mot de passe MQTT (optionnel)
$ClientID = "DarkFragtal"             # ID unique pour ce PC
$BaseTopic = "ha-agent"               # Topic MQTT de base
```

## Utilisation

### Test des fonctionnalités
```powershell
.\test-functions.ps1
```

### Exécution unique
```powershell
.\ha-agent.ps
```

### Mode service (exécution continue)
```powershell
# Exécution toutes les 60 secondes (par défaut)
.\ha-agent-service.ps1

# Exécution toutes les 30 secondes
.\ha-agent-service.ps1 -IntervalSeconds 30

# Exécution unique
.\ha-agent-service.ps1 -RunOnce
```

### Commandes à distance
```powershell
# Dans le script ou via MQTT
Invoke-RemoteCommand "reboot"      # Redémarrer
Invoke-RemoteCommand "shutdown"    # Éteindre
Invoke-RemoteCommand "hibernate"   # Hibernation
Invoke-RemoteCommand "sleep"       # Veille
Invoke-RemoteCommand "logout"      # Déconnexion
```

## Topics MQTT publiés

### État du système
- `ha-agent/[ClientID]/state/pc_running` - PC en marche (true/false)
- `ha-agent/[ClientID]/state/users_logged_in` - Utilisateurs connectés (true/false)
- `ha-agent/[ClientID]/state/logged_users` - Liste des utilisateurs (string)
- `ha-agent/[ClientID]/state/logged_users_count` - Nombre d'utilisateurs (number)

### Capteurs système
- `ha-agent/[ClientID]/sensor/cpu_percent` - CPU utilisé (%)
- `ha-agent/[ClientID]/sensor/ram_total_gb` - RAM totale (GB)
- `ha-agent/[ClientID]/sensor/ram_used_gb` - RAM utilisée (GB)
- `ha-agent/[ClientID]/sensor/ram_free_gb` - RAM libre (GB)
- `ha-agent/[ClientID]/sensor/ram_percent` - RAM utilisée (%)
- `ha-agent/[ClientID]/sensor/disk_total_gb` - Disque total (GB)
- `ha-agent/[ClientID]/sensor/disk_used_gb` - Disque utilisé (GB)
- `ha-agent/[ClientID]/sensor/disk_free_gb` - Disque libre (GB)
- `ha-agent/[ClientID]/sensor/disk_percent` - Disque utilisé (%)
- `ha-agent/[ClientID]/sensor/updates_pending` - Mises à jour en attente

### Statut général
- `ha-agent/[ClientID]/status` - Statut de l'agent ("online")

## Prérequis

- Windows PowerShell 5.1 ou PowerShell Core 7+
- Droits d'administration pour certaines commandes (redémarrage, arrêt)
- Client MQTT (à implémenter selon votre choix)

## Installation d'un client MQTT

Vous devez adapter la fonction `Publish-MQTT` selon votre client MQTT :

### Option 1 : Mosquitto CLI
```bash
# Installation via Chocolatey
choco install mosquitto

# Utilisation dans le script
mosquitto_pub -h $MQTTBroker -u $MQTTUser -P $MQTTPassword -t $topic -m $payload
```

### Option 2 : MQTTnet CLI
```bash
# Installation via dotnet
dotnet tool install --global MQTTnet.App

# Utilisation dans le script
mqttnet publish -s $MQTTBroker -u $MQTTUser -p $MQTTPassword -t $topic -m $payload
```

## Intégration Home Assistant

Ajoutez ces capteurs dans votre `configuration.yaml` :

```yaml
mqtt:
  sensor:
    - name: "PC DarkFragtal Status"
      state_topic: "ha-agent/DarkFragtal/state/pc_running"
      
    - name: "PC DarkFragtal Users"
      state_topic: "ha-agent/DarkFragtal/state/logged_users"
      
    - name: "PC DarkFragtal CPU"
      state_topic: "ha-agent/DarkFragtal/sensor/cpu_percent"
      unit_of_measurement: "%"
      
    - name: "PC DarkFragtal RAM"
      state_topic: "ha-agent/DarkFragtal/sensor/ram_percent"
      unit_of_measurement: "%"
      
    - name: "PC DarkFragtal Disk"
      state_topic: "ha-agent/DarkFragtal/sensor/disk_percent"
      unit_of_measurement: "%"
      
    - name: "PC DarkFragtal Updates"
      state_topic: "ha-agent/DarkFragtal/sensor/updates_pending"

  switch:
    - name: "PC DarkFragtal Reboot"
      command_topic: "ha-agent/DarkFragtal/command"
      payload_on: "reboot"
      
    - name: "PC DarkFragtal Shutdown"
      command_topic: "ha-agent/DarkFragtal/command"
      payload_on: "shutdown"
```

## Exécution en tant que service Windows

Pour exécuter en tant que service Windows, vous pouvez utiliser `NSSM` ou créer une tâche planifiée.

### Avec NSSM
```bash
# Installation
choco install nssm

# Création du service
nssm install "HAAgent" "powershell.exe" "-ExecutionPolicy Bypass -File C:\Path\To\ha-agent-service.ps1"
nssm start "HAAgent"
```

## Sécurité

- Exécutez avec les privilèges minimum nécessaires
- Sécurisez votre broker MQTT avec authentification
- Limitez l'accès réseau au broker MQTT
- Testez les commandes à distance en environnement sécurisé

## Dépannage

### Windows Update ne fonctionne pas
L'agent utilise l'API COM Windows Update. Si elle échoue, vérifiez :
- Service Windows Update en cours d'exécution
- Droits d'administration
- Installation du module PSWindowsUpdate (optionnel)

### Détection des utilisateurs
La commande `query user` nécessite parfois des droits spéciaux. Exécutez en tant qu'administrateur si nécessaire.