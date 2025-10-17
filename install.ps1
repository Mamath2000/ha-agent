# =============================================================================
# Script d'installation automatique HA-Agent
# Déploiement simplifié sur différents PC Windows
# =============================================================================

param(
    [string]$InstallPath = "C:\HA-Agent",
    [string]$MQTTBroker = "192.168.100.9",
    [string]$BaseTopic = "homeassistant/sensor",
    [string]$ClientID = $env:COMPUTERNAME,
    [switch]$CreateService = $false,
    [switch]$AutoStart = $false
)

Write-Host "=== INSTALLATION HA-AGENT POUR WINDOWS ===" -ForegroundColor Green
Write-Host "Chemin d'installation: $InstallPath" -ForegroundColor Yellow
Write-Host "Broker MQTT: $MQTTBroker" -ForegroundColor Yellow
Write-Host "Client ID: $ClientID" -ForegroundColor Yellow

# Vérifier les privilèges administrateur
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and $CreateService) {
    Write-Host "⚠️ Les privilèges administrateur sont requis pour créer un service Windows" -ForegroundColor Yellow
    Write-Host "Relancez ce script en tant qu'administrateur avec -CreateService" -ForegroundColor Yellow
    $CreateService = $false
}

# Créer le répertoire d'installation
try {
    if (-not (Test-Path $InstallPath)) {
        New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
        Write-Host "✅ Répertoire créé: $InstallPath" -ForegroundColor Green
    }
}
catch {
    Write-Host "❌ Erreur lors de la création du répertoire: $_" -ForegroundColor Red
    exit 1
}

# Vérifier PowerShell Gallery et installer PSMQTT
Write-Host ""
Write-Host "=== Installation du module PSMQTT ===" -ForegroundColor Cyan

try {
    # Vérifier si le module est déjà installé
    $psmqtt = Get-Module -ListAvailable -Name PSMQTT
    if ($psmqtt) {
        Write-Host "✅ Module PSMQTT déjà installé (version $($psmqtt.Version))" -ForegroundColor Green
    } else {
        Write-Host "📥 Installation du module PSMQTT..." -ForegroundColor Yellow
        
        # Configurer PowerShell Gallery si nécessaire
        if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
            Write-Host "Enregistrement de PowerShell Gallery..." -ForegroundColor Yellow
            Register-PSRepository -Default
        }
        
        # Installer le module
        Install-Module -Name PSMQTT -Force -Scope CurrentUser -AllowClobber
        Write-Host "✅ Module PSMQTT installé avec succès" -ForegroundColor Green
    }
}
catch {
    Write-Host "❌ Erreur lors de l'installation PSMQTT: $_" -ForegroundColor Red
    Write-Host "💡 Vous pouvez l'installer manuellement avec: Install-Module PSMQTT -Force" -ForegroundColor Yellow
}

# Copier les fichiers du script
Write-Host ""
Write-Host "=== Copie des fichiers ===" -ForegroundColor Cyan

$sourceFiles = @(
    "ha-agent.ps1",
    "ha-agent-service.ps1"
)

foreach ($file in $sourceFiles) {
    if (Test-Path $file) {
        try {
            $destPath = Join-Path $InstallPath $file
            Copy-Item $file $destPath -Force
            Write-Host "✅ Copié: $file → $destPath" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Erreur copie $file : $_" -ForegroundColor Red
        }
    } else {
        Write-Host "⚠️ Fichier manquant: $file" -ForegroundColor Yellow
    }
}

# Créer un fichier de configuration
Write-Host ""
Write-Host "=== Création de la configuration ===" -ForegroundColor Cyan

$configContent = @"
# Configuration HA-Agent
# Modifiez ces paramètres selon votre environnement

`$MQTTBroker = "$MQTTBroker"
`$BaseTopic = "$BaseTopic" 
`$ClientID = "$ClientID"

# Paramètres avancés
`$MQTTPort = 1883
`$MQTTUsername = ""  # Laissez vide si pas d'authentification
`$MQTTPassword = ""  # Laissez vide si pas d'authentification
"@

try {
    $configPath = Join-Path $InstallPath "config.ps1"
    Set-Content -Path $configPath -Value $configContent -Encoding UTF8
    Write-Host "✅ Configuration créée: $configPath" -ForegroundColor Green
}
catch {
    Write-Host "❌ Erreur création config: $_" -ForegroundColor Red
}

# Créer un script de lancement simple
$launcherContent = @"
# Script de lancement HA-Agent
Set-Location "$InstallPath"
. ".\config.ps1"
. ".\ha-agent-service.ps1" -IntervalSeconds 60
"@

try {
    $launcherPath = Join-Path $InstallPath "start-ha-agent.ps1"
    Set-Content -Path $launcherPath -Value $launcherContent -Encoding UTF8
    Write-Host "✅ Launcher créé: $launcherPath" -ForegroundColor Green
}
catch {
    Write-Host "❌ Erreur création launcher: $_" -ForegroundColor Red
}

# Tester la connexion MQTT
Write-Host ""
Write-Host "=== Test de connexion MQTT ===" -ForegroundColor Cyan

try {
    Set-Location $InstallPath
    . ".\config.ps1"
    . ".\ha-agent.ps1"
    
    # Test basique de connexion
    $session = Initialize-MQTTConnection
    if ($session -and $session.IsConnected) {
        Write-Host "✅ Connexion MQTT réussie!" -ForegroundColor Green
        Disconnect-MQTTBroker -Session $session
    } else {
        Write-Host "⚠️ Impossible de se connecter au broker MQTT" -ForegroundColor Yellow
        Write-Host "Vérifiez l'adresse du broker dans: $configPath" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "⚠️ Test MQTT échoué: $_" -ForegroundColor Yellow
}

# Créer une tâche planifiée (optionnel)
if ($CreateService) {
    Write-Host ""
    Write-Host "=== Création de la tâche planifiée ===" -ForegroundColor Cyan
    
    try {
        $taskName = "HA-Agent-$ClientID"
        $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        
        if ($taskExists) {
            Write-Host "⚠️ Tâche '$taskName' existe déjà" -ForegroundColor Yellow
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
        
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File `"$launcherPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings
        
        Write-Host "✅ Tâche planifiée créée: $taskName" -ForegroundColor Green
        
        if ($AutoStart) {
            Start-ScheduledTask -TaskName $taskName
            Write-Host "✅ Tâche démarrée automatiquement" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Erreur création tâche planifiée: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== INSTALLATION TERMINÉE ===" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Fichiers installés dans: $InstallPath" -ForegroundColor Cyan
Write-Host "⚙️  Configuration: $configPath" -ForegroundColor Cyan
Write-Host "🚀 Lancement: $launcherPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Pour démarrer l'agent:" -ForegroundColor Yellow
Write-Host "  cd `"$InstallPath`"" -ForegroundColor White
Write-Host "  .\start-ha-agent.ps1" -ForegroundColor White
Write-Host ""

if (-not $CreateService) {
    Write-Host "💡 Pour créer une tâche planifiée (démarrage auto):" -ForegroundColor Yellow
    Write-Host "  .\install.ps1 -CreateService -AutoStart" -ForegroundColor White
}