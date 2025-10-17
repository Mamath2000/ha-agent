# =============================================================================
# Script Home Assistant Agent - Mode Service
# Exécution en boucle continue avec intervalle configurable
# =============================================================================

param(
    [int]$IntervalSeconds = 60,  # Intervalle entre les publications (par défaut 60 secondes)
    [switch]$RunOnce = $false    # Exécuter une seule fois au lieu d'une boucle
)

# Importer le script principal
. ".\ha-agent.ps1"

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