# =============================================================================
# Script de désinstallation du service HA-Agent avec NSSM
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
    Start-Sleep -Seconds 5
    exit 1
}

# 3. Vérifier si le service existe
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Warning "Le service '$ServiceName' n'est pas installé. Aucune action n'est nécessaire."
    Start-Sleep -Seconds 5
    exit 0
}

# --- Arrêt et suppression du service ---

Write-Host "Arrêt du service '$ServiceName'..." -ForegroundColor Cyan
& $NssmPath stop $ServiceName

# Attendre un peu pour s'assurer que le service est bien arrêté
Start-Sleep -Seconds 2

Write-Host "Suppression du service '$ServiceName'..." -ForegroundColor Cyan
& $NssmPath remove $ServiceName confirm

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Le service '$ServiceName' a été supprimé avec succès." -ForegroundColor Green
} else {
    Write-Error "La suppression du service a échoué. NSSM a retourné le code d'erreur $LASTEXITCODE."
}

Start-Sleep -Seconds 10
