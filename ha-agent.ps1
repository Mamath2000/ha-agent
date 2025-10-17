# =============================================================================
# Script Home Assistant Agent pour Windows
# Fonctionnalités : État PC, utilisateurs connectés, contrôle à distance, capteurs système
# =============================================================================

# Import du module PSMQTT
Import-Module PSMQTT

# Configuration MQTT
$MQTTBroker = "mqtt://192.168.100.9"
$MQTTUser = ""
$MQTTPassword = ""
$ClientID = "DarkFragtal"
$BaseTopic = "ha-agent"

# Configuration de sécurité (PAR DÉFAUT SÉCURISÉ)
$Global:SafeMode = $true   # Mode sécurisé activé par défaut — bloque les commandes dangereuses
$Global:CommandsEnabled = $false  # Si true, permet l'exécution (NE PAS ACTIVER SANS VÉRIFICATION)

# =============================================================================
# FONCTIONS DE DÉTECTION D'ÉTAT
# =============================================================================

# Vérifier si le PC est démarré (cette fonction sera toujours true si le script tourne)
function Test-PCRunning {
    return $true
}

# Vérifier si des utilisateurs sont connectés
function Test-UsersLoggedIn {
    try {
        $sessions = query user 2>$null
        return $sessions.Count -gt 1  # Plus d'une ligne (header + utilisateurs)
    }
    catch {
        return $false
    }
}

# Obtenir la liste des utilisateurs connectés
function Get-LoggedUsers {
    try {
        $users = @()
        $sessions = query user 2>$null
        
        if ($sessions.Count -gt 1) {
            foreach ($line in $sessions[1..($sessions.Count-1)]) {
                # Parse la ligne pour extraire le nom d'utilisateur
                $parts = $line -split '\s+' | Where-Object { $_ -ne '' }
                if ($parts.Count -ge 1 -and $parts[0] -ne 'USERNAME') {
                    $username = $parts[0]
                    if ($username -notmatch '^>?services$|^>?console$') {
                        $users += $username -replace '^>', ''
                    }
                }
            }
        }
        return $users
    }
    catch {
        return @()
    }
}

# =============================================================================
# FONCTIONS DE CAPTEURS SYSTÈME
# =============================================================================

function Get-SystemStats {
    try {
        # CPU Usage (moyenne sur tous les cœurs)
        $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        
        # Mémoire
        $os = Get-CimInstance Win32_OperatingSystem
        $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $ramUsed = [math]::Round($ramTotal - $ramFree, 2)
        $ramPercent = [math]::Round(($ramUsed / $ramTotal) * 100, 1)
        
        # Disque C:
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFree = [math]::Round($disk.FreeSpace / 1GB, 2)
        $diskTotal = [math]::Round($disk.Size / 1GB, 2)
        $diskUsed = [math]::Round($diskTotal - $diskFree, 2)
        $diskPercent = [math]::Round(($diskUsed / $diskTotal) * 100, 1)
        
        # Windows Update (nombre de mises à jour en attente)
        $updatesPending = 0
        try {
            # Méthode alternative sans module PSWindowsUpdate
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0")
            $updatesPending = $searchResult.Updates.Count
        }
        catch {
            # Si l'API COM échoue, essayer via Get-WindowsUpdate si disponible
            try {
                if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
                    $updatesPending = (Get-WindowsUpdate -MicrosoftUpdate).Count
                }
            }
            catch {
                $updatesPending = -1  # Indique une erreur de détection
            }
        }
        
        return @{
            cpu_percent = [math]::Round($cpu, 1)
            ram_total_gb = $ramTotal
            ram_used_gb = $ramUsed
            ram_free_gb = $ramFree
            ram_percent = $ramPercent
            disk_total_gb = $diskTotal
            disk_used_gb = $diskUsed
            disk_free_gb = $diskFree
            disk_percent = $diskPercent
            updates_pending = $updatesPending
        }
    }
    catch {
        Write-Error "Erreur lors de la récupération des statistiques système : $_"
        return @{}
    }
}

# =============================================================================
# FONCTIONS DE CONTRÔLE À DISTANCE
# =============================================================================

function Invoke-RemoteCommand([string]$command, [switch]$ConfirmExecution) {

    # Autoriser uniquement la commande sûre 'lock' ; tout le reste est bloqué
    $allowed = @('lock')

    Write-Host "Commande reçue: '$command'" -ForegroundColor Yellow

    if ($allowed -notcontains $command.ToLower()) {
        Write-Host "🚫 Cette commande est bloquée pour la sécurité. Seule 'lock' est autorisée." -ForegroundColor Red
        return
    }

    switch ($command.ToLower()) {
        'lock' {
            Write-Host "🔒 Commande 'lock' reçue." -ForegroundColor Cyan
            if ($ConfirmExecution) {
                Write-Host "Exécution confirmée : verrouillage en cours..." -ForegroundColor Green
                Invoke-LockWorkstation
            }
            else {
                Write-Host "Simulation : pour verrouiller réellement, appelez Invoke-RemoteCommand 'lock' -ConfirmExecution" -ForegroundColor Yellow
            }
        }
        default {
            Write-Host "Commande non reconnue ou non autorisée : $command" -ForegroundColor Red
        }
    }
}

# Fonction pour rafraîchir et republier tous les capteurs
function Invoke-RefreshSensors {
    Write-Host "🔄 Rafraîchissement des capteurs en cours..." -ForegroundColor Cyan
    
    # Recalculer toutes les données
    $pcRunning = Test-PCRunning
    $usersLoggedIn = Test-UsersLoggedIn
    $loggedUsers = Get-LoggedUsers
    $stats = Get-SystemStats
    
    # Republier toutes les données
    Publish-MQTT "$BaseTopic/$ClientID/state/pc_running" $pcRunning
    Publish-MQTT "$BaseTopic/$ClientID/state/users_logged_in" $usersLoggedIn
    Publish-MQTT "$BaseTopic/$ClientID/state/logged_users" ($loggedUsers -join ",")
    Publish-MQTT "$BaseTopic/$ClientID/state/logged_users_count" $loggedUsers.Count
    
    if ($stats.Count -gt 0) {
        Publish-MQTT "$BaseTopic/$ClientID/sensor/cpu_percent" $stats.cpu_percent
        Publish-MQTT "$BaseTopic/$ClientID/sensor/ram_total_gb" $stats.ram_total_gb
        Publish-MQTT "$BaseTopic/$ClientID/sensor/ram_used_gb" $stats.ram_used_gb
        Publish-MQTT "$BaseTopic/$ClientID/sensor/ram_free_gb" $stats.ram_free_gb
        Publish-MQTT "$BaseTopic/$ClientID/sensor/ram_percent" $stats.ram_percent
        Publish-MQTT "$BaseTopic/$ClientID/sensor/disk_total_gb" $stats.disk_total_gb
        Publish-MQTT "$BaseTopic/$ClientID/sensor/disk_used_gb" $stats.disk_used_gb
        Publish-MQTT "$BaseTopic/$ClientID/sensor/disk_free_gb" $stats.disk_free_gb
        Publish-MQTT "$BaseTopic/$ClientID/sensor/disk_percent" $stats.disk_percent
        Publish-MQTT "$BaseTopic/$ClientID/sensor/updates_pending" $stats.updates_pending
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Publish-MQTT "$BaseTopic/$ClientID/sensor/last_refresh" $timestamp
    
    Write-Host "✅ Capteurs rafraîchis avec succès !" -ForegroundColor Green
}

# =============================================================================
# VERROUILLER LA SESSION (SAFE)
# =============================================================================
function Invoke-LockWorkstation {
    try {
        # Définir l'API LockWorkStation
        $signature = @'
        [DllImport("user32.dll")]
        public static extern bool LockWorkStation();
'@
        Add-Type -MemberDefinition $signature -Name "Win32Lock" -Namespace Win32Utils -ErrorAction SilentlyContinue

        if ([Win32Utils.Win32Lock]::LockWorkStation()) {
            Write-Host "🔒 Écran verrouillé." -ForegroundColor Green
        }
        else {
            Write-Host "⚠️ Impossible de verrouiller l'écran (peut nécessiter des privilèges)." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "❌ Erreur lors du verrouillage : $_" -ForegroundColor Red
    }
}


# Fonction pour afficher le statut système
function Show-SystemStatus {
    Write-Host "📊 Statut du système:" -ForegroundColor Cyan
    
    $pcRunning = Test-PCRunning
    $usersLoggedIn = Test-UsersLoggedIn
    $loggedUsers = Get-LoggedUsers
    $stats = Get-SystemStats
    
    Write-Host "  PC en marche: $pcRunning" -ForegroundColor Green
    Write-Host "  Utilisateurs connectés: $usersLoggedIn" -ForegroundColor Green
    Write-Host "  Liste des utilisateurs: $($loggedUsers -join ', ')" -ForegroundColor Green
    
    if ($stats.Count -gt 0) {
        Write-Host "  CPU: $($stats.cpu_percent)%" -ForegroundColor Green
        Write-Host "  RAM: $($stats.ram_used_gb)GB / $($stats.ram_total_gb)GB ($($stats.ram_percent)%)" -ForegroundColor Green
        Write-Host "  Disque C: $($stats.disk_used_gb)GB / $($stats.disk_total_gb)GB ($($stats.disk_percent)%)" -ForegroundColor Green
        Write-Host "  Mises à jour en attente: $($stats.updates_pending)" -ForegroundColor Green
    }
    
    # Publier le statut avec timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Publish-MQTT "$BaseTopic/$ClientID/sensor/last_status_check" $timestamp
    
    Write-Host "✅ Statut affiché et publié !" -ForegroundColor Green
}

# =============================================================================
# FONCTIONS MQTT DISCOVERY
# =============================================================================

function Get-HADiscoveryConfig {
    param(
        [string]$ClientID,
        [string]$BaseTopic
    )
    
    # Créer un identifiant en minuscules pour Home Assistant
    $clientIdLower = $ClientID.ToLower()
    
    $hostname = $env:COMPUTERNAME
    $discoveryConfig = @{
        device = @{
            identifiers = @("ha_agent_$clientIdLower")
            name = "$hostname ($ClientID)"
            model = "Windows PC"
            manufacturer = "Microsoft"
            sw_version = (Get-CimInstance Win32_OperatingSystem).Version
        }
        origin = @{
            name = "HA-Agent PowerShell"
        }
        state_topic = "$BaseTopic/$ClientID/state"
        components = @{
            # État du PC
            "${clientIdLower}_pc_running" = @{
                platform = "binary_sensor"
                unique_id = "${clientIdLower}_pc_running"
                default_entity_id = "${clientIdLower}_pc_running"
                has_entity_name = $true
                force_update = $true
                name = "PC Running"
                icon = "mdi:desktop-tower"
                device_class = "running"
                value_template = "{{ value_json.pc_running }}"
                payload_on = "True"
                payload_off = "False"
                state_topic = "$BaseTopic/$ClientID/state"
            }
            
            # Utilisateurs connectés
            "${clientIdLower}_users_logged_in" = @{
                platform = "binary_sensor"
                unique_id = "${clientIdLower}_users_logged_in"
                default_entity_id = "${clientIdLower}_users_logged_in"
                has_entity_name = $true
                force_update = $true
                name = "Users Logged In"
                icon = "mdi:account-multiple"
                device_class = "occupancy"
                value_template = "{{ value_json.users_logged_in }}"
                payload_on = "True"
                payload_off = "False"
                state_topic = "$BaseTopic/$ClientID/state"
            }
            
            # Nombre d'utilisateurs
            "${clientIdLower}_users_count" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_users_count"
                default_entity_id = "${clientIdLower}_users_count"
                has_entity_name = $true
                force_update = $true
                name = "Users Count"
                icon = "mdi:account-group"
                value_template = "{{ value_json.logged_users_count }}"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/state"
            }
            
            # Liste des utilisateurs
            "${clientIdLower}_users_list" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_users_list"
                default_entity_id = "${clientIdLower}_users_list"
                has_entity_name = $true
                force_update = $true
                name = "Logged Users"
                icon = "mdi:account-details"
                value_template = "{{ value_json.logged_users }}"
                state_topic = "$BaseTopic/$ClientID/state"
            }
            
            # CPU
            "${clientIdLower}_cpu_percent" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_cpu_percent"
                default_entity_id = "${clientIdLower}_cpu_percent"
                has_entity_name = $true
                force_update = $true
                name = "CPU Usage"
                icon = "mdi:cpu-64-bit"
                value_template = "{{ value_json.cpu_percent }}"
                device_class = "power_factor"
                unit_of_measurement = "%"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/sensors"
            }
            
            # RAM Usage
            "${clientIdLower}_ram_percent" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_ram_percent"
                default_entity_id = "${clientIdLower}_ram_percent"
                has_entity_name = $true
                force_update = $true
                name = "Memory Usage"
                icon = "mdi:memory"
                value_template = "{{ value_json.ram_percent }}"
                device_class = "power_factor"
                unit_of_measurement = "%"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/sensors"
            }
            
            # RAM Total
            "${clientIdLower}_ram_total" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_ram_total"
                default_entity_id = "${clientIdLower}_ram_total"
                has_entity_name = $true
                force_update = $true
                name = "Memory Total"
                icon = "mdi:memory"
                value_template = "{{ value_json.ram_total_gb }}"
                device_class = "data_size"
                unit_of_measurement = "GB"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/sensors"
            }
            
            # RAM Used
            "${clientIdLower}_ram_used" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_ram_used"
                default_entity_id = "${clientIdLower}_ram_used"
                has_entity_name = $true
                force_update = $true
                name = "Memory Used"
                icon = "mdi:memory"
                value_template = "{{ value_json.ram_used_gb }}"
                device_class = "data_size"
                unit_of_measurement = "GB"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/sensors"
            }
            
            # Disque Usage
            "${clientIdLower}_disk_percent" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_disk_percent"
                default_entity_id = "${clientIdLower}_disk_percent"
                has_entity_name = $true
                force_update = $true
                name = "Disk Usage"
                icon = "mdi:harddisk"
                value_template = "{{ value_json.disk_percent }}"
                device_class = "power_factor"
                unit_of_measurement = "%"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/sensors"
            }
            
            # Disque Total
            "${clientIdLower}_disk_total" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_disk_total"
                default_entity_id = "${clientIdLower}_disk_total"
                has_entity_name = $true
                force_update = $true
                name = "Disk Total"
                icon = "mdi:harddisk"
                value_template = "{{ value_json.disk_total_gb }}"
                device_class = "data_size"
                unit_of_measurement = "GB"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/sensors"
            }
            
            # Windows Updates
            "${clientIdLower}_updates_pending" = @{
                platform = "sensor"
                unique_id = "${clientIdLower}_updates_pending"
                default_entity_id = "${clientIdLower}_updates_pending"
                has_entity_name = $true
                force_update = $true
                name = "Updates Pending"
                icon = "mdi:update"
                value_template = "{{ value_json.updates_pending }}"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/sensors"
            }
            
            # Boutons de contrôle
            "${clientIdLower}_reboot" = @{
                platform = "button"
                unique_id = "${clientIdLower}_reboot"
                default_entity_id = "${clientIdLower}_reboot"
                name = "Reboot"
                command_topic = "$BaseTopic/$ClientID/command"
                icon = "mdi:restart"
                payload_press = '{"action":"reboot"}'
                device_class = "restart"
            }
            
            "${clientIdLower}_shutdown" = @{
                platform = "button"
                unique_id = "${clientIdLower}_shutdown"
                default_entity_id = "${clientIdLower}_shutdown"
                name = "Shutdown"
                command_topic = "$BaseTopic/$ClientID/command"
                icon = "mdi:power"
                payload_press = '{"action":"shutdown"}'
            }
            
            "${clientIdLower}_hibernate" = @{
                platform = "button"
                unique_id = "${clientIdLower}_hibernate"
                default_entity_id = "${clientIdLower}_hibernate"
                name = "Hibernate"
                command_topic = "$BaseTopic/$ClientID/command"
                icon = "mdi:sleep"
                payload_press = '{"action":"hibernate"}'
            }
            
            "${clientIdLower}_logout" = @{
                platform = "button"
                unique_id = "${clientIdLower}_logout"
                default_entity_id = "${clientIdLower}_logout"
                name = "Logout"
                command_topic = "$BaseTopic/$ClientID/command"
                icon = "mdi:logout"
                payload_press = '{"action":"logout"}'
            }
            
            "${clientIdLower}_refresh" = @{
                platform = "button"
                unique_id = "${clientIdLower}_refresh"
                default_entity_id = "${clientIdLower}_refresh"
                name = "Refresh Sensors"
                command_topic = "$BaseTopic/$ClientID/command"
                icon = "mdi:refresh"
                payload_press = '{"action":"refresh"}'
                entity_category = "diagnostic"
            }
            
            "${clientIdLower}_status" = @{
                platform = "button"
                unique_id = "${clientIdLower}_status"
                default_entity_id = "${clientIdLower}_status"
                name = "Show Status"
                command_topic = "$BaseTopic/$ClientID/command"
                icon = "mdi:information-outline"
                payload_press = '{"action":"status"}'
                entity_category = "diagnostic"
            }
        }
    }
    
    return $discoveryConfig
}

function Publish-HADiscovery {
    param(
        [string]$ClientID,
        [string]$BaseTopic
    )
    
    try {
        Write-Host "=== Publication de la découverte Home Assistant ===" -ForegroundColor Cyan
        
        # Générer la configuration de découverte
        $discoveryConfig = Get-HADiscoveryConfig -ClientID $ClientID -BaseTopic $BaseTopic
        
        # Convertir en JSON
        $jsonConfig = $discoveryConfig | ConvertTo-Json -Depth 10 -Compress
        
        # Topic de découverte Home Assistant
        $discoveryTopic = "homeassistant/device/ha-agent/$($ClientID.ToLower())/config"
        
        # Publier la configuration de découverte
        Publish-MQTT $discoveryTopic $jsonConfig
        
        Write-Host "✅ Configuration de découverte publiée sur $discoveryTopic" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Erreur lors de la publication de découverte: $_" -ForegroundColor Red
    }
}

# Variable globale pour la session MQTT
$Global:MQTTSession = $null

function Initialize-MQTTConnection {
    if ($Global:MQTTSession -and $Global:MQTTSession.IsConnected) {
        return $Global:MQTTSession
    }
    
    try {
        # Extraire l'host du broker (enlever mqtt://)
        $brokerHost = $MQTTBroker -replace '^mqtt://', '' -replace '^mqtts://', ''
        
        # Créer la session MQTT
        if ($MQTTUser -and $MQTTPassword) {
            $Global:MQTTSession = Connect-MQTTBroker -Hostname $brokerHost -Port 1883 -Username $MQTTUser -Password $MQTTPassword
        } else {
            $Global:MQTTSession = Connect-MQTTBroker -Hostname $brokerHost -Port 1883
        }
        
        Write-Host "✅ Connexion MQTT établie avec $brokerHost" -ForegroundColor Green
        return $Global:MQTTSession
    }
    catch {
        Write-Host "❌ Erreur de connexion MQTT: $_" -ForegroundColor Red
        return $null
    }
}

function Publish-MQTT($topic, $payload) {
    try {
        # S'assurer que la session est connectée
        $session = Initialize-MQTTConnection
        if (-not $session) {
            throw "Pas de session MQTT disponible"
        }
        
        # Publier le message
        Send-MQTTMessage -Session $session -Topic $topic -Payload $payload.ToString() -Quiet
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] MQTT ✅ $topic : $payload" -ForegroundColor Green
    }
    catch {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] MQTT ❌ Erreur: $_" -ForegroundColor Red
        Write-Host "[$timestamp] MQTT -> $topic : $payload" -ForegroundColor Yellow
    }
}

function Start-MQTTCommandListener {
    param(
        [string]$ClientID,
        [string]$BaseTopic
    )
    
    try {
        $session = Initialize-MQTTConnection
        if (-not $session) {
            Write-Host "❌ Pas de session MQTT pour écouter les commandes" -ForegroundColor Red
            return
        }
        
        $commandTopic = "$BaseTopic/$ClientID/command"
        
        # S'abonner au topic de commandes (fonction non disponible dans PSMQTT de base)
        # Cette partie nécessiterait une extension ou une approche différente
        Write-Host "🔔 Écoute des commandes sur: $commandTopic" -ForegroundColor Yellow
        Write-Host "Note: L'écoute MQTT nécessite une implémentation avancée" -ForegroundColor Gray
    }
    catch {
        Write-Host "❌ Erreur lors de l'écoute MQTT: $_" -ForegroundColor Red
    }
}

function Process-HACommand {
    param(
        [string]$JsonCommand
    )
    
    try {
        $command = $JsonCommand | ConvertFrom-Json
        $action = $command.action
        
        Write-Host "🎯 Commande reçue: $action" -ForegroundColor Cyan
        
        switch ($action.ToLower()) {
            "reboot" { 
                Write-Host "⚡ Exécution: Redémarrage du système" -ForegroundColor Yellow
                Invoke-RemoteCommand "reboot"
            }
            "shutdown" { 
                Write-Host "⚡ Exécution: Arrêt du système" -ForegroundColor Yellow
                Invoke-RemoteCommand "shutdown"
            }
            "hibernate" { 
                Write-Host "⚡ Exécution: Mise en hibernation" -ForegroundColor Yellow
                Invoke-RemoteCommand "hibernate"
            }
            "sleep" { 
                Write-Host "⚡ Exécution: Mise en veille" -ForegroundColor Yellow
                Invoke-RemoteCommand "sleep"
            }
            "logout" { 
                Write-Host "⚡ Exécution: Déconnexion" -ForegroundColor Yellow
                Invoke-RemoteCommand "logout"
            }
            "refresh" { 
                Write-Host "🔄 Exécution: Rafraîchissement des capteurs" -ForegroundColor Green
                Invoke-RefreshSensors
            }
            "status" { 
                Write-Host "📊 Exécution: Affichage du statut" -ForegroundColor Green
                Show-SystemStatus
            }
            default { 
                Write-Host "⚠️ Commande non reconnue: $action" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "❌ Erreur lors du traitement de la commande: $_" -ForegroundColor Red
    }
}

# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

function Start-HAAgent {
    Write-Host "=== Démarrage de l'agent Home Assistant pour Windows ===" -ForegroundColor Green
    Write-Host "Client ID: $ClientID" -ForegroundColor Yellow
    Write-Host "Broker MQTT: $MQTTBroker" -ForegroundColor Yellow
    Write-Host ""
    
    # État du PC
    $pcRunning = Test-PCRunning
    $usersLoggedIn = Test-UsersLoggedIn
    $loggedUsers = Get-LoggedUsers
    
    # Statistiques système
    $stats = Get-SystemStats
    
    # Publication de la découverte Home Assistant (une seule fois)
    Publish-HADiscovery -ClientID $ClientID -BaseTopic $BaseTopic
    
    # Publication des données
    Write-Host "=== Publication des données ===" -ForegroundColor Cyan
    
    # Créer les objets JSON pour les topics groupés
    $stateData = @{
        pc_running = $pcRunning
        users_logged_in = $usersLoggedIn
        logged_users = ($loggedUsers -join ",")
        logged_users_count = $loggedUsers.Count
    }
    
    $sensorsData = @{}
    if ($stats.Count -gt 0) {
        $sensorsData = @{
            cpu_percent = $stats.cpu_percent
            ram_total_gb = $stats.ram_total_gb
            ram_used_gb = $stats.ram_used_gb
            ram_free_gb = $stats.ram_free_gb
            ram_percent = $stats.ram_percent
            disk_total_gb = $stats.disk_total_gb
            disk_used_gb = $stats.disk_used_gb
            disk_free_gb = $stats.disk_free_gb
            disk_percent = $stats.disk_percent
            updates_pending = $stats.updates_pending
        }
    }
    
    # Publier les données groupées en JSON
    Publish-MQTT "$BaseTopic/$ClientID/state" ($stateData | ConvertTo-Json -Compress)
    
    if ($sensorsData.Count -gt 0) {
        Publish-MQTT "$BaseTopic/$ClientID/sensors" ($sensorsData | ConvertTo-Json -Compress)
    }
    
    # Heartbeat
    Publish-MQTT "$BaseTopic/$ClientID/status" "online"
    
    Write-Host ""
    Write-Host "=== Résumé ===" -ForegroundColor Green
    Write-Host "PC en marche: $pcRunning"
    Write-Host "Utilisateurs connectés: $usersLoggedIn"
    Write-Host "Liste des utilisateurs: $($loggedUsers -join ', ')"
    if ($stats.Count -gt 0) {
        Write-Host "CPU: $($stats.cpu_percent)%"
        Write-Host "RAM: $($stats.ram_used_gb)GB / $($stats.ram_total_gb)GB ($($stats.ram_percent)%)"
        Write-Host "Disque C: $($stats.disk_used_gb)GB / $($stats.disk_total_gb)GB ($($stats.disk_percent)%)"
        Write-Host "Mises à jour en attente: $($stats.updates_pending)"
    }
}

# Fonction de nettoyage pour fermer la session MQTT
function Stop-HAAgent {
    if ($Global:MQTTSession -and $Global:MQTTSession.IsConnected) {
        try {
            Publish-MQTT "$BaseTopic/$ClientID/status" "offline"
            Disconnect-MQTTBroker -Session $Global:MQTTSession
            Write-Host "✅ Session MQTT fermée proprement" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠️ Erreur lors de la fermeture MQTT: $_" -ForegroundColor Yellow
        }
    }
}

# =============================================================================
# EXEMPLES D'UTILISATION
# =============================================================================

# Exécution principale
Start-HAAgent

# Exemples de commandes à distance (décommentez pour tester)
# Invoke-RemoteCommand "reboot"
# Invoke-RemoteCommand "shutdown"
# Invoke-RemoteCommand "hibernate"
# Invoke-RemoteCommand "logout"
