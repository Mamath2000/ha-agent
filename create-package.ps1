# =============================================================================
# Script de création de package portable HA-Agent
# Crée un ZIP prêt à déployer
# =============================================================================

param(
    [string]$OutputPath = ".\HA-Agent-Portable.zip",
    [string]$DefaultMQTTBroker = "192.168.100.9"
)

Write-Host "=== CRÉATION DU PACKAGE PORTABLE HA-AGENT ===" -ForegroundColor Green

# Créer un répertoire temporaire
$tempDir = "$env:TEMP\ha-agent-package"
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
}
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

# Copier les fichiers principaux
$mainFiles = @(
    "ha-agent.ps1",
    "ha-agent-service.ps1",
    "install.ps1",
    "deploy-network.ps1"
)

foreach ($file in $mainFiles) {
    if (Test-Path $file) {
        Copy-Item $file $tempDir -Force
        Write-Host "✅ Ajouté: $file" -ForegroundColor Green
    }
}

# Créer un README pour le package
$readmeContent = @"
# HA-Agent pour Windows - Package Portable
Version de déploiement simplifié

## 🚀 Installation rapide

### Installation locale simple:
``````
.\install.ps1
``````

### Installation avec service automatique:
``````
.\install.ps1 -CreateService -AutoStart
``````

### Personnaliser le broker MQTT:
``````
.\install.ps1 -MQTTBroker "192.168.1.100" -CreateService
``````

## 🌐 Déploiement réseau

### Sur plusieurs PC en même temps:
``````
.\deploy-network.ps1 -ComputerNames PC1,PC2,PC3 -MQTTBroker "192.168.1.100"
``````

### Avec authentification réseau:
``````
`$cred = Get-Credential
.\deploy-network.ps1 -ComputerNames PC1,PC2 -Credential `$cred -CreateService
``````

## 📁 Structure d'installation

Après installation, les fichiers seront dans:
- **C:\HA-Agent\** (répertoire principal)
- **config.ps1** (configuration MQTT)
- **start-ha-agent.ps1** (script de lancement)

## ⚙️ Configuration

Éditez **C:\HA-Agent\config.ps1** pour personnaliser:
- Adresse du broker MQTT
- Topic MQTT
- Client ID
- Authentification MQTT (si nécessaire)

## 🏃‍♂️ Lancement

### Manuel:
``````
cd C:\HA-Agent
.\start-ha-agent.ps1
``````

### Service automatique:
La tâche planifiée démarre automatiquement au boot si installée avec -CreateService

## 🔧 Capteurs disponibles

- **PC Running**: État du PC (allumé/éteint)
- **Users Logged In**: Utilisateurs connectés (oui/non)  
- **Users Count**: Nombre d'utilisateurs connectés
- **Users List**: Liste des utilisateurs connectés
- **CPU Usage**: Utilisation CPU (%)
- **Memory Usage**: Utilisation RAM (%)
- **Memory Total/Used**: RAM totale et utilisée (GB)
- **Disk Usage**: Utilisation disque (%)
- **Disk Total**: Espace disque total (GB)
- **Updates Pending**: Mises à jour Windows en attente

## 📊 Topics MQTT

Les données sont publiées sur:
- **homeassistant/sensor/{PC-NAME}/state** (états du PC)
- **homeassistant/sensor/{PC-NAME}/sensors** (capteurs système)
- **homeassistant/device/{PC-NAME}/config** (découverte HA)

## 🆘 Dépannage

### Module PSMQTT manquant:
``````
Install-Module PSMQTT -Force
``````

### Problème de connexion MQTT:
1. Vérifiez l'adresse IP du broker
2. Vérifiez que le port 1883 est ouvert
3. Testez avec: ``Test-NetConnection -ComputerName IP_BROKER -Port 1883``

### PowerShell Execution Policy:
``````
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
``````
"@

Set-Content -Path "$tempDir\README.md" -Value $readmeContent -Encoding UTF8
Write-Host "✅ README créé" -ForegroundColor Green

# Créer un script de configuration rapide
$quickConfigContent = @"
# Configuration rapide HA-Agent
# Exécutez ce script pour configurer rapidement l'installation

param(
    [Parameter(Mandatory=`$true)]
    [string]`$MQTTBroker,
    [string]`$BaseTopic = "homeassistant/sensor",
    [string]`$ClientID = `$env:COMPUTERNAME
)

Write-Host "=== CONFIGURATION RAPIDE HA-AGENT ===" -ForegroundColor Green

# Installer et configurer
.\install.ps1 -MQTTBroker `$MQTTBroker -BaseTopic `$BaseTopic -ClientID `$ClientID -CreateService -AutoStart

Write-Host "✅ Configuration terminée!" -ForegroundColor Green
Write-Host "L'agent démarre automatiquement et se connecte à: `$MQTTBroker" -ForegroundColor Yellow
"@

Set-Content -Path "$tempDir\quick-setup.ps1" -Value $quickConfigContent -Encoding UTF8
Write-Host "✅ Script de configuration rapide créé" -ForegroundColor Green

# Créer le fichier ZIP
try {
    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force
    }
    
    Compress-Archive -Path "$tempDir\*" -DestinationPath $OutputPath -Force
    Write-Host "✅ Package créé: $OutputPath" -ForegroundColor Green
    
    # Informations sur le package
    $zipInfo = Get-Item $OutputPath
    Write-Host ""
    Write-Host "📦 PACKAGE PORTABLE CRÉÉ" -ForegroundColor Cyan
    Write-Host "Fichier: $($zipInfo.FullName)" -ForegroundColor Yellow
    Write-Host "Taille: $([math]::Round($zipInfo.Length / 1KB, 1)) KB" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "💡 Distribution:" -ForegroundColor Yellow
    Write-Host "  1. Copiez le ZIP sur les PC cibles" -ForegroundColor White
    Write-Host "  2. Extrayez le contenu" -ForegroundColor White
    Write-Host "  3. Exécutez: .\quick-setup.ps1 -MQTTBroker IP_DU_BROKER" -ForegroundColor White
    
}
catch {
    Write-Host "❌ Erreur création ZIP: $_" -ForegroundColor Red
}
finally {
    # Nettoyer
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== PACKAGE PORTABLE PRÊT ===" -ForegroundColor Green