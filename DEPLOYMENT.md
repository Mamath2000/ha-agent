# 🚀 Guide de déploiement HA-Agent

Ce guide présente plusieurs méthodes pour déployer l'agent Home Assistant sur différents PC Windows.

## 📦 Méthodes de déploiement

### 1. 🎯 Installation locale simple

Pour installer sur un PC unique :

```powershell
# Télécharger et exécuter
.\install.ps1

# Avec configuration personnalisée
.\install.ps1 -MQTTBroker "192.168.1.100" -CreateService -AutoStart
```

**Avantages**: Simple, rapide, contrôle total
**Utilisation**: PC unique ou quelques machines

### 2. 🌐 Déploiement réseau (PowerShell Remoting)

Pour déployer sur plusieurs PC via le réseau :

```powershell
# Prérequis: WinRM activé sur les PC cibles
Enable-PSRemoting -Force

# Déploiement multiple
.\deploy-network.ps1 -ComputerNames PC1,PC2,PC3 -MQTTBroker "192.168.1.100" -CreateService

# Avec authentification
$cred = Get-Credential
.\deploy-network.ps1 -ComputerNames PC1,PC2 -Credential $cred
```

**Avantages**: Déploiement simultané, gestion centralisée
**Utilisation**: Environnement réseau d'entreprise

### 3. 📦 Package portable (ZIP)

Pour créer un package autonome :

```powershell
# Créer le package
.\create-package.ps1 -OutputPath "HA-Agent-v1.0.zip"

# Sur chaque PC cible:
# 1. Extraire le ZIP
# 2. Exécuter:
.\quick-setup.ps1 -MQTTBroker "192.168.1.100"
```

**Avantages**: Autonome, facile à distribuer, offline
**Utilisation**: Distribution par email/USB, environnements isolés

### 4. 💾 Déploiement par GPO (Groupe Policy)

Pour les environnements Active Directory :

1. **Copier les fichiers** vers un partage réseau (\\\\server\\netlogon\\ha-agent\\)

2. **Créer un script de démarrage** (startup.bat) :
```batch
@echo off
if not exist "C:\HA-Agent\ha-agent.ps1" (
    powershell.exe -ExecutionPolicy Bypass -File "\\server\netlogon\ha-agent\install.ps1" -MQTTBroker "192.168.1.100" -CreateService -AutoStart
)
```

3. **Déployer via GPO** : Computer Configuration > Policies > Windows Settings > Scripts > Startup

**Avantages**: Automatique, gestion centralisée AD
**Utilisation**: Grande entreprise avec Active Directory

### 5. 🔧 Déploiement manuel par partage réseau

Configuration d'un partage réseau pour installation manuelle :

```powershell
# Sur le serveur de fichiers
New-SmbShare -Name "HA-Agent" -Path "C:\Shares\HA-Agent" -ReadAccess "Domain Users"

# Copier les fichiers sur le partage
Copy-Item .\* \\server\HA-Agent\ -Recurse

# Sur chaque PC (via script ou manuellement)
net use Z: \\server\HA-Agent
Z:\install.ps1 -MQTTBroker "192.168.1.100" -CreateService
net use Z: /delete
```

**Avantages**: Simple, pas besoin de WinRM
**Utilisation**: Réseau simple, installation à la demande

## ⚙️ Configuration avancée

### Variables d'environnement système

Pour une configuration standardisée, utilisez des variables d'environnement :

```powershell
# Définir au niveau système
[Environment]::SetEnvironmentVariable("HA_MQTT_BROKER", "192.168.1.100", "Machine")
[Environment]::SetEnvironmentVariable("HA_BASE_TOPIC", "homeassistant/sensor", "Machine")

# L'agent les utilisera automatiquement
.\install.ps1 -MQTTBroker $env:HA_MQTT_BROKER
```

### Configuration par fichier INI

Créer un fichier `ha-config.ini` :

```ini
[MQTT]
Broker=192.168.1.100
Port=1883
Username=
Password=
BaseTopic=homeassistant/sensor

[Agent]
ClientID=%COMPUTERNAME%
Interval=60
CreateService=true
```

### Déploiement par SCCM/Intune

Pour Microsoft System Center ou Intune :

1. **Empaqueter** avec `create-package.ps1`
2. **Créer une application** SCCM/Intune
3. **Ligne de commande** : `powershell.exe -ExecutionPolicy Bypass -File install.ps1 -MQTTBroker 192.168.1.100 -CreateService`
4. **Déployer** sur les collections cibles

## 🔍 Vérification du déploiement

### Script de vérification

```powershell
# Vérifier l'installation sur plusieurs PC
$computers = @("PC1", "PC2", "PC3")
foreach ($pc in $computers) {
    $result = Invoke-Command -ComputerName $pc -ScriptBlock {
        Test-Path "C:\HA-Agent\ha-agent.ps1"
    } -ErrorAction SilentlyContinue
    
    if ($result) {
        Write-Host "✅ $pc : Agent installé" -ForegroundColor Green
    } else {
        Write-Host "❌ $pc : Agent manquant" -ForegroundColor Red
    }
}
```

### Monitoring MQTT

Surveillez les topics MQTT pour vérifier la connectivité :

```bash
# Avec mosquitto_sub
mosquitto_sub -h 192.168.1.100 -t "homeassistant/sensor/+/state" -v

# Voir tous les PC connectés
mosquitto_sub -h 192.168.1.100 -t "homeassistant/device/+/config" -v
```

## 🛠️ Dépannage commun

### PowerShell Execution Policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### WinRM pour déploiement réseau
```powershell
# Sur chaque PC cible
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts * -Force
```

### Firewall Windows
```powershell
# Autoriser PowerShell Remoting
New-NetFirewallRule -DisplayName "PS Remoting" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow
```

### Test de connectivité MQTT
```powershell
Test-NetConnection -ComputerName 192.168.1.100 -Port 1883
```

## 📋 Checklist de déploiement

- [ ] Broker MQTT accessible depuis tous les PC
- [ ] PowerShell Execution Policy configurée
- [ ] WinRM activé (pour déploiement réseau)
- [ ] Firewall configuré si nécessaire
- [ ] Module PSMQTT installable depuis PowerShell Gallery
- [ ] Privilèges administrateur (pour services Windows)
- [ ] Noms DNS/IP des PC cibles connus
- [ ] Home Assistant configuré pour recevoir les discovery MQTT

## 💡 Bonnes pratiques

1. **Testez d'abord** sur un PC de test
2. **Documentez** les paramètres spécifiques à votre environnement
3. **Surveillez** les logs lors du premier déploiement
4. **Planifiez** la maintenance et les mises à jour
5. **Sauvegardez** la configuration avant modifications