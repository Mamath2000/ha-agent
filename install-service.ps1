# =============================================================================
# Script d'installation du service HA-Agent avec NSSM
# Doit être exécuté en tant qu'administrateur.
# =============================================================================

# --- Configuration ---
$ServiceName = "HA-AgentSvc"
# Chemin vers nssm.exe. Par défaut, on suppose qu'il est dans le même dossier.
$NssmPath = Join-Path $PSScriptRoot "nssm.exe" 

# --- Vérification des prérequis ---

# 1. Vérifier si le script s'exécute en tant qu'administrateur
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Ce script doit être exécuté en tant qu'administrateur."
    Write-Host "Veuillez faire un clic droit sur le script et choisir 'Exécuter en tant qu'administrateur'."
    Start-Sleep -Seconds 10
    exit 1
}

# 2. Vérifier si nssm.exe existe
if (-NOT (Test-Path $NssmPath)) {
    Write-Error "nssm.exe n'a pas été trouvé à l'emplacement '$NssmPath'."
    Write-Host "Veuillez télécharger NSSM (https://nssm.cc/download) et placer le fichier nssm.exe approprié dans le même dossier que ce script." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    exit 1
}

# 3. Vérifier si le service existe déjà
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Warning "Le service '$ServiceName' existe déjà. Aucune action ne sera effectuée."
    Write-Host "Si vous souhaitez le réinstaller, veuillez d'abord le supprimer avec le script 'uninstall-service.ps1'."
    Start-Sleep -Seconds 10
    exit 0
}


# --- Installation du service ---

# Chemin complet du script principal à exécuter
$ScriptPath = Join-Path $PSScriptRoot "ha-agent.ps1"
if (-NOT (Test-Path $ScriptPath)) {
    Write-Error "Le script 'ha-agent.ps1' est introuvable dans le dossier '$PSScriptRoot'."
    Start-Sleep -Seconds 5
    exit 1
}

# Chemin de l'exécutable PowerShell
# Utilisation de pwsh.exe (PowerShell 7+) si disponible, sinon powershell.exe (Windows PowerShell 5.1)
$PowerShellExe = "powershell.exe"
try {
    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        $PowerShellExe = (Get-Command pwsh.exe).Source
        Write-Host "Utilisation de PowerShell 7+ (pwsh.exe)." -ForegroundColor Green
    } else {
        $PowerShellExe = (Get-Command powershell.exe).Source
        Write-Host "Utilisation de Windows PowerShell (powershell.exe)." -ForegroundColor Yellow
    }
} catch {
    Write-Error "Impossible de trouver un exécutable PowerShell."
    Start-Sleep -Seconds 5
    exit 1
}


# Arguments pour NSSM
# -NoProfile      : Ne charge pas le profil PowerShell, pour un démarrage plus rapide et plus propre.
# -ExecutionPolicy Bypass : Pour éviter les problèmes de politique d'exécution.
# -File           : Le chemin vers le script à exécuter.
$Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

Write-Host "Installation du service '$ServiceName'..." -ForegroundColor Cyan

# Commande d'installation
& $NssmPath install $ServiceName $PowerShellExe $Arguments

if ($LASTEXITCODE -ne 0) {
    Write-Error "L'installation du service a échoué. NSSM a retourné le code d'erreur $LASTEXITCODE."
    # Tenter de supprimer une installation partielle en cas d'échec
    & $NssmPath remove $ServiceName confirm
    Start-Sleep -Seconds 5
    exit 1
}

# --- Configuration supplémentaire du service ---

Write-Host "Configuration du service..." -ForegroundColor Cyan

# Définir le répertoire de travail pour que les chemins relatifs fonctionnent
& $NssmPath set $ServiceName AppDirectory $PSScriptRoot

# Définir une description pour le service
& $NssmPath set $ServiceName Description "Agent de liaison Home Assistant pour Windows. Publie des capteurs et des états via MQTT."

# Configurer le redémarrage automatique en cas de crash
& $NssmPath set $ServiceName AppRestartDelay 2000 # Délai de 2 secondes avant redémarrage

# Créer un dossier pour les logs s'il n'existe pas
$LogPath = Join-Path $PSScriptRoot "logs"
if (-NOT (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory | Out-Null
}

# Configurer la redirection des logs vers des fichiers
Write-Host "Configuration de la journalisation..." -ForegroundColor Cyan
& $NssmPath set $ServiceName AppStdout (Join-Path $LogPath "output.log")
& $NssmPath set $ServiceName AppStderr (Join-Path $LogPath "error.log")

# Configurer la rotation des logs pour éviter qu'ils ne deviennent trop gros
& $NssmPath set $ServiceName AppRotateFiles 1 # Activer la rotation
& $NssmPath set $ServiceName AppRotateBytes 1048576 # Rotation tous les 1 Mo (1024*1024)

# --- Démarrage du service ---

Write-Host "Démarrage du service '$ServiceName'..." -ForegroundColor Cyan
& $NssmPath start $ServiceName

# Vérifier le statut du service après le démarrage
Start-Sleep -Seconds 2
$serviceStatus = (Get-Service -Name $ServiceName).Status
if ($serviceStatus -eq 'Running') {
    Write-Host "✅ Le service '$ServiceName' a été installé et démarré avec succès." -ForegroundColor Green
} else {
    Write-Error "Le service '$ServiceName' a été installé mais n'a pas pu démarrer. Statut actuel : $serviceStatus"
    Write-Host "Vérifiez les journaux d'événements pour plus de détails ('nssm get $ServiceName AppEvents')."
}

Start-Sleep -Seconds 10
