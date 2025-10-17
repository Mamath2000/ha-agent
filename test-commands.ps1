# =============================================================================
# Script de test pour les commandes Home Assistant (MODE SIMULATION UNIQUEMENT)
# =============================================================================

# Importer le script principal
. ".\ha-agent.ps1"

Write-Host "=== TEST DES COMMANDES HOME ASSISTANT (SIMULATION) ===" -ForegroundColor Magenta
Write-Host "⚠️  MODE SIMULATION - AUCUNE COMMANDE DANGEREUSE NE SERA EXÉCUTÉE ⚠️" -ForegroundColor Red
Write-Host ""

# Fonction de test sécurisée qui ne fait que parser et afficher
function Test-HACommandSafely {
    param([string]$JsonCommand)
    
    try {
        $command = $JsonCommand | ConvertFrom-Json
        $action = $command.action
        
        Write-Host "   Action détectée: $action" -ForegroundColor Cyan
        
        switch ($action.ToLower()) {
            "refresh" { 
                Write-Host "   ✅ Commande SÉCURISÉE - Rafraîchissement des capteurs" -ForegroundColor Green
                # Ici on pourrait vraiment exécuter le refresh
                # Invoke-RefreshSensors
            }
            "status" { 
                Write-Host "   ✅ Commande SÉCURISÉE - Affichage du statut" -ForegroundColor Green
                # Ici on pourrait vraiment exécuter le status
                # Show-SystemStatus
            }
            "reboot" { 
                Write-Host "   ⛔ COMMANDE DANGEREUSE - Redémarrage (NON EXÉCUTÉ)" -ForegroundColor Red
            }
            "shutdown" { 
                Write-Host "   ⛔ COMMANDE DANGEREUSE - Arrêt (NON EXÉCUTÉ)" -ForegroundColor Red
            }
            "sleep" { 
                Write-Host "   ⚠️  COMMANDE POTENTIELLE - Veille (NON EXÉCUTÉ)" -ForegroundColor Yellow
            }
            "hibernate" { 
                Write-Host "   ⚠️  COMMANDE POTENTIELLE - Hibernation (NON EXÉCUTÉ)" -ForegroundColor Yellow
            }
            "logout" { 
                Write-Host "   ⚠️  COMMANDE POTENTIELLE - Déconnexion (NON EXÉCUTÉ)" -ForegroundColor Yellow
            }
            default { 
                Write-Host "   ❌ Commande inconnue: $action" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host "   ❌ Erreur de parsing JSON: $_" -ForegroundColor Red
    }
}

# Test des commandes JSON (SIMULATION UNIQUEMENT)
$testCommands = @(
    '{"action":"refresh"}',
    '{"action":"status"}',
    '{"action":"sleep"}',
    '{"action":"hibernate"}',
    '{"action":"logout"}',
    '{"action":"reboot"}',
    '{"action":"shutdown"}',
    '{"action":"invalid"}'
)

foreach ($cmd in $testCommands) {
    Write-Host "Test de la commande: $cmd" -ForegroundColor Yellow
    Test-HACommandSafely -JsonCommand $cmd
    Write-Host ""
}

Write-Host "=== SIMULATION D'ENVOI DE COMMANDE VIA MQTT ===" -ForegroundColor Magenta
Write-Host ""

# Simuler l'envoi d'une commande de test (sans exécution réelle)
$commandTopic = "$BaseTopic/$ClientID/command"
$testCommand = '{"action":"refresh"}'

Write-Host "Pour tester une vraie commande depuis Home Assistant:" -ForegroundColor Cyan
Write-Host "Topic: $commandTopic" -ForegroundColor Yellow
Write-Host "Payload: $testCommand" -ForegroundColor Yellow
Write-Host ""

Write-Host "Exemple avec mosquitto_pub:" -ForegroundColor Cyan
Write-Host "mosquitto_pub -h 192.168.100.9 -t `"$commandTopic`" -m `"$testCommand`"" -ForegroundColor Gray

Write-Host ""
Write-Host "=== NOTE IMPORTANTE ===" -ForegroundColor Red
Write-Host "L'écoute des commandes MQTT nécessite une implémentation avancée." -ForegroundColor Yellow
Write-Host "Le module PSMQTT ne supporte pas nativement l'abonnement MQTT." -ForegroundColor Yellow
Write-Host "Pour une vraie écoute, il faudrait utiliser MQTTnet ou un autre client." -ForegroundColor Yellow