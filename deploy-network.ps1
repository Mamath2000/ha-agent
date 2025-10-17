# =============================================================================
# Script de déploiement réseau HA-Agent
# Déploie l'agent sur plusieurs PC via réseau
# =============================================================================

param(
    [string[]]$ComputerNames = @(),  # Liste des PC cibles
    [string]$NetworkPath = "",       # Chemin réseau partagé (optionnel)
    [string]$MQTTBroker = "192.168.100.9",
    [PSCredential]$Credential = $null,
    [switch]$CreateService = $false
)

if ($ComputerNames.Count -eq 0) {
    Write-Host "Usage: .\deploy-network.ps1 -ComputerNames PC1,PC2,PC3 -MQTTBroker 192.168.1.100" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Paramètres:" -ForegroundColor Cyan
    Write-Host "  -ComputerNames    : Liste des noms de PC (séparés par virgule)" -ForegroundColor White
    Write-Host "  -NetworkPath      : Chemin réseau partagé (ex: \\server\share\ha-agent)" -ForegroundColor White
    Write-Host "  -MQTTBroker       : Adresse IP du broker MQTT" -ForegroundColor White
    Write-Host "  -Credential       : Identifiants réseau (optionnel)" -ForegroundColor White
    Write-Host "  -CreateService    : Créer une tâche planifiée sur chaque PC" -ForegroundColor White
    exit 1
}

Write-Host "=== DÉPLOIEMENT HA-AGENT SUR RÉSEAU ===" -ForegroundColor Green
Write-Host "PC cibles: $($ComputerNames -join ', ')" -ForegroundColor Yellow
Write-Host "Broker MQTT: $MQTTBroker" -ForegroundColor Yellow

# Préparer les fichiers localement
$tempPath = "$env:TEMP\ha-agent-deploy"
if (Test-Path $tempPath) {
    Remove-Item $tempPath -Recurse -Force
}
New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

# Copier les fichiers nécessaires
$filesToCopy = @(
    "ha-agent.ps1",
    "ha-agent-service.ps1", 
    "install.ps1"
)

foreach ($file in $filesToCopy) {
    if (Test-Path $file) {
        Copy-Item $file $tempPath -Force
        Write-Host "✅ Préparé: $file" -ForegroundColor Green
    } else {
        Write-Host "❌ Fichier manquant: $file" -ForegroundColor Red
        exit 1
    }
}

# Créer un script de déploiement distant
$remoteScript = @"
param([string]`$MQTTBroker, [bool]`$CreateService)

# Changer vers le répertoire temporaire
Set-Location `$env:TEMP\ha-agent-deploy

# Exécuter l'installation
`$params = @{
    MQTTBroker = `$MQTTBroker
    CreateService = `$CreateService
    AutoStart = `$CreateService
}

.\install.ps1 @params

# Nettoyer les fichiers temporaires
Set-Location C:\
Remove-Item `$env:TEMP\ha-agent-deploy -Recurse -Force -ErrorAction SilentlyContinue
"@

Set-Content -Path "$tempPath\remote-install.ps1" -Value $remoteScript

# Déployer sur chaque PC
foreach ($computerName in $ComputerNames) {
    Write-Host ""
    Write-Host "=== Déploiement sur $computerName ===" -ForegroundColor Cyan
    
    try {
        # Vérifier la connectivité
        if (-not (Test-Connection -ComputerName $computerName -Count 1 -Quiet)) {
            Write-Host "❌ PC $computerName non accessible" -ForegroundColor Red
            continue
        }
        
        # Créer une session PS sur le PC distant
        $sessionParams = @{
            ComputerName = $computerName
        }
        if ($Credential) {
            $sessionParams.Credential = $Credential
        }
        
        $session = New-PSSession @sessionParams -ErrorAction Stop
        Write-Host "✅ Session PowerShell établie" -ForegroundColor Green
        
        # Copier les fichiers
        Copy-Item -Path "$tempPath\*" -Destination "$env:TEMP\ha-agent-deploy" -ToSession $session -Recurse -Force
        Write-Host "✅ Fichiers copiés" -ForegroundColor Green
        
        # Exécuter l'installation à distance
        $result = Invoke-Command -Session $session -ScriptBlock {
            param($mqttBroker, $createSvc)
            Set-Location $env:TEMP
            if (-not (Test-Path ha-agent-deploy)) {
                New-Item -Path ha-agent-deploy -ItemType Directory -Force
            }
            Set-Location ha-agent-deploy
            .\remote-install.ps1 -MQTTBroker $mqttBroker -CreateService $createSvc
        } -ArgumentList $MQTTBroker, $CreateService
        
        Write-Host "✅ Installation terminée sur $computerName" -ForegroundColor Green
        
        # Fermer la session
        Remove-PSSession $session
        
    }
    catch {
        Write-Host "❌ Erreur sur $computerName : $_" -ForegroundColor Red
    }
}

# Nettoyer les fichiers temporaires locaux
Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== DÉPLOIEMENT RÉSEAU TERMINÉ ===" -ForegroundColor Green
Write-Host ""
Write-Host "💡 Les agents sont installés dans C:\HA-Agent sur chaque PC" -ForegroundColor Yellow
Write-Host "💡 Chaque PC aura son propre Client ID basé sur son nom" -ForegroundColor Yellow