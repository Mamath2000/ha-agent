# =============================================================================
# Script HA-Agent pour exécution en service Windows
# Version service qui republique les discovery périodiquement
# =============================================================================

# Import du module PSMQTT
Import-Module PSMQTT

# =============================================================================
# CONFIGURATION - Modifiez ces valeurs selon votre installation
# =============================================================================
$MQTTBroker = "mqtt://192.168.100.9"  # Adresse de votre broker MQTT
$BaseTopic = "ha-agent"                # Topic de base pour MQTT
$IntervalSeconds = 60                  # Intervalle entre les envois (secondes)

# Importer le script principal
$scriptPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "ha-agent.ps1"
. $scriptPath

function Start-HAAgentService {
    param(
        [int]$Interval = 60,
        [bool]$Once = $false
    )
    
    Write-Host "=== DÉMARRAGE DU SERVICE HOME ASSISTANT AGENT ===" -ForegroundColor Green
    Write-Host "Intervalle: $Interval secondes" -ForegroundColor Yellow
    Write-Host "Discovery: Au lancement puis toutes les heures" -ForegroundColor Yellow
    Write-Host "Mode: $(if($Once) {'Exécution unique'} else {'Service continu'})" -ForegroundColor Yellow
    Write-Host "Appuyez sur Ctrl+C pour arrêter le service" -ForegroundColor Yellow
    Write-Host ""
    
    $iteration = 0
    $lastDiscoveryTime = $null
    $discoveryIntervalMinutes = 60  # Republier le discovery toutes les 60 minutes
    
    # Initialisation au premier démarrage
    Initialize-HAAgent
    $lastDiscoveryTime = Get-Date
    
    do {
        $iteration++
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $currentTime = Get-Date
        
        Write-Host "[$timestamp] === Itération $iteration ===" -ForegroundColor Cyan
        
        try {
            # Vérifier si il faut republier le discovery (toutes les heures)
            if ($lastDiscoveryTime -eq $null -or ($currentTime - $lastDiscoveryTime).TotalMinutes -ge $discoveryIntervalMinutes) {
                Write-Host "⏰ Republication du discovery MQTT (toutes les heures)" -ForegroundColor Magenta
                Publish-HADiscovery -ClientID $ClientID -BaseTopic $BaseTopic
                $lastDiscoveryTime = $currentTime
            }
            
            # Publier seulement les données (pas d'initialisation)
            Publish-HAData
            
            if (-not $Once) {
                Write-Host "[$timestamp] Prochaine exécution dans $Interval secondes..." -ForegroundColor Gray
                Write-Host ""
                Start-Sleep -Seconds $Interval
            }
        }
        catch {
            Write-Error "[$timestamp] Erreur lors de l'exécution : $_"
            if (-not $Once) {
                Write-Host "Tentative de reprise dans $Interval secondes..." -ForegroundColor Yellow
                Start-Sleep -Seconds $Interval
            }
        }
        
    } while (-not $Once)
    
    Write-Host "=== ARRÊT DU SERVICE HOME ASSISTANT AGENT ===" -ForegroundColor Red
    Stop-HAAgent
}

# Gestion des signaux d'interruption
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Host "`n=== Service interrompu par l'utilisateur ===" -ForegroundColor Yellow
    Stop-HAAgent
}

# Démarrage du service
Start-HAAgentService -Interval $IntervalSeconds -Once $RunOnce