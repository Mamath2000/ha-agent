# =============================================================================
# Script de test pour l'agent Home Assistant Windows
# =============================================================================

# Importer le script principal
. ".\ha-agent.ps1"

Write-Host "=== TEST DES FONCTIONNALITÉS ===" -ForegroundColor Magenta
Write-Host ""

# Test 1: État du PC
Write-Host "1. Test de l'état du PC:" -ForegroundColor Yellow
$pcState = Test-PCRunning
Write-Host "   PC en marche: $pcState" -ForegroundColor Green
Write-Host ""

# Test 2: Utilisateurs connectés
Write-Host "2. Test des utilisateurs connectés:" -ForegroundColor Yellow
$usersLoggedIn = Test-UsersLoggedIn
$loggedUsers = Get-LoggedUsers
Write-Host "   Des utilisateurs sont connectés: $usersLoggedIn" -ForegroundColor Green
Write-Host "   Nombre d'utilisateurs: $($loggedUsers.Count)" -ForegroundColor Green
Write-Host "   Liste des utilisateurs: $($loggedUsers -join ', ')" -ForegroundColor Green
Write-Host ""

# Test 3: Capteurs système
Write-Host "3. Test des capteurs système:" -ForegroundColor Yellow
$stats = Get-SystemStats
if ($stats.Count -gt 0) {
    Write-Host "   CPU: $($stats.cpu_percent)%" -ForegroundColor Green
    Write-Host "   RAM Total: $($stats.ram_total_gb) GB" -ForegroundColor Green
    Write-Host "   RAM Utilisée: $($stats.ram_used_gb) GB ($($stats.ram_percent)%)" -ForegroundColor Green
    Write-Host "   RAM Libre: $($stats.ram_free_gb) GB" -ForegroundColor Green
    Write-Host "   Disque Total: $($stats.disk_total_gb) GB" -ForegroundColor Green
    Write-Host "   Disque Utilisé: $($stats.disk_used_gb) GB ($($stats.disk_percent)%)" -ForegroundColor Green
    Write-Host "   Disque Libre: $($stats.disk_free_gb) GB" -ForegroundColor Green
    Write-Host "   Mises à jour en attente: $($stats.updates_pending)" -ForegroundColor Green
} else {
    Write-Host "   Erreur lors de la récupération des statistiques système" -ForegroundColor Red
}
Write-Host ""

# Test 4: Affichage des commandes disponibles
Write-Host "4. Commandes de contrôle à distance disponibles:" -ForegroundColor Yellow
Write-Host "   - reboot      : Redémarrer le PC" -ForegroundColor Cyan
Write-Host "   - shutdown    : Éteindre le PC" -ForegroundColor Cyan
Write-Host "   - hibernate   : Mettre en hibernation" -ForegroundColor Cyan
Write-Host "   - sleep       : Mettre en veille" -ForegroundColor Cyan
Write-Host "   - logout      : Déconnecter l'utilisateur actuel" -ForegroundColor Cyan
Write-Host "   - logoff      : Déconnecter tous les utilisateurs" -ForegroundColor Cyan
Write-Host ""

Write-Host "=== EXEMPLE D'UTILISATION ===" -ForegroundColor Magenta
Write-Host "Pour exécuter une commande à distance:"
Write-Host "   Invoke-RemoteCommand 'reboot'" -ForegroundColor Yellow
Write-Host "   Invoke-RemoteCommand 'shutdown'" -ForegroundColor Yellow
Write-Host "   Invoke-RemoteCommand 'hibernate'" -ForegroundColor Yellow
Write-Host ""

Write-Host "=== FIN DES TESTS ===" -ForegroundColor Magenta