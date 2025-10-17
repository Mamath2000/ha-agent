# =============================================================================
# Script Home Assistant Agent pour Windows
# Fonctionnalités : État PC, utilisateurs connectés, contrôle à distance, capteurs système
# =============================================================================

# Import du module PSMQTT
Import-Module PSMQTT

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

function Get-PrimaryMacAddress {
    try {
        # Récupérer l'interface réseau active avec une adresse IP
        $activeAdapter = Get-CimInstance Win32_NetworkAdapter | Where-Object {
            $_.NetEnabled -eq $true -and 
            $_.AdapterTypeId -eq 0 -and  # Ethernet
            $_.MACAddress -ne $null -and
            $_.MACAddress -ne "" -and
            $_.MACAddress -notlike "*00-00-00-00-00-00*"
        } | Select-Object -First 1
        
        if ($activeAdapter -and $activeAdapter.MACAddress) {
            # Convertir au format standard avec deux-points
            return $activeAdapter.MACAddress.Replace("-", ":").ToLower()
        }
        
        # Fallback: prendre la première interface avec MAC valide
        $fallbackAdapter = Get-CimInstance Win32_NetworkAdapter | Where-Object {
            $_.MACAddress -ne $null -and 
            $_.MACAddress -ne "" -and
            $_.MACAddress -notlike "*00-00-00-00-00-00*"
        } | Select-Object -First 1
        
        if ($fallbackAdapter -and $fallbackAdapter.MACAddress) {
            return $fallbackAdapter.MACAddress.Replace("-", ":").ToLower()
        }
        
        return $null
    }
    catch {
        Write-Host "⚠️ Impossible de récupérer l'adresse MAC: $_" -ForegroundColor Yellow
        return $null
    }
}

# Configuration MQTT
$MQTTBroker = "mqtt://192.168.100.9"
$MQTTUser = ""
$MQTTPassword = ""

# Génération automatique du Client ID basé sur le nom de machine + MAC
function Get-ClientID {
    $hostname = $env:COMPUTERNAME
    $macAddress = Get-PrimaryMacAddress
    
    if ($macAddress) {
        # Enlever les deux-points de la MAC
        $macClean = $macAddress.Replace(":", "")
        return "$hostname-$macClean"
    } else {
        # Fallback sur hostname seul si pas de MAC
        return $hostname
    }
}

$ClientID = Get-ClientID
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

# Fonction pour republier la découverte MQTT manuellement
function Invoke-RepublishDiscovery {
    Write-Host "📡 Republication de la découverte MQTT..." -ForegroundColor Magenta
    Publish-HADiscovery -ClientID $ClientID -BaseTopic $BaseTopic
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
    $hostnameLower = $hostname.ToLower()
    $macAddress = Get-PrimaryMacAddress
    
    # Préparer les connexions du device (liste d'entrées: [ [type, value], ... ])
    $deviceConnections = @()
    if ($macAddress) {
        # Ajouter une entrée en tant que tableau ["mac", "aa:bb:cc:..."]
        $deviceConnections += ,@("mac", $macAddress)
        Write-Host "🔗 Adresse MAC détectée: $macAddress" -ForegroundColor Cyan
    }
    
    # Créer la structure device de base
    $deviceConfig = @{
        identifiers = @("ha_agent_$clientIdLower")
        name = "$hostname ($ClientID)"
        model = "Windows PC"
        manufacturer = "Microsoft"
        sw_version = (Get-CimInstance Win32_OperatingSystem).Version
    }
    
    # Ajouter les connexions si au moins une entrée est disponible
    if ($deviceConnections.Count -gt 0) {
        # $deviceConnections est déjà une liste d'entrées (arrays)
        $deviceConfig.connections = $deviceConnections
    }
    
    $discoveryConfig = @{
        device = $deviceConfig
        origin = @{
            name = "HA-Agent PowerShell"
        }
        state_topic = "$BaseTopic/$ClientID/state"
        components = @{
            # État du PC
            "${clientIdLower}_pc_running" = @{
                platform = "binary_sensor"
                unique_id = "${clientIdLower}_pc_running"
                object_id = "${hostnameLower}_pc_running"
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
                object_id = "${hostnameLower}_users_logged_in"
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
                object_id = "${hostnameLower}_users_count"
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
                object_id = "${hostnameLower}_users_list"
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
                object_id = "${hostnameLower}_cpu_percent"
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
                object_id = "${hostnameLower}_ram_percent"
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
                object_id = "${hostnameLower}_ram_total"
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
                object_id = "${hostnameLower}_ram_used"
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
                object_id = "${hostnameLower}_disk_percent"
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
                object_id = "${hostnameLower}_disk_total"
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
                object_id = "${hostnameLower}_updates_pending"
                has_entity_name = $true
                force_update = $true
                name = "Updates Pending"
                icon = "mdi:update"
                value_template = "{{ value_json.updates_pending }}"
                state_class = "measurement"
                state_topic = "$BaseTopic/$ClientID/sensors"
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
        
        # Publier la configuration de découverte avec retain pour persistance
        Publish-MQTT $discoveryTopic $jsonConfig $true
        
        Write-Host "✅ Configuration de découverte publiée avec RETAIN sur $discoveryTopic" -ForegroundColor Green
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

function Publish-MQTT($topic, $payload, [bool]$retain = $false) {
    try {
        # S'assurer que la session est connectée
        $session = Initialize-MQTTConnection
        if (-not $session) {
            throw "Pas de session MQTT disponible"
        }
        
        # Publier le message avec ou sans retain
        if ($retain) {
            Send-MQTTMessage -Session $session -Topic $topic -Payload $payload.ToString() -Retain -Quiet
        } else {
            Send-MQTTMessage -Session $session -Topic $topic -Payload $payload.ToString() -Quiet
        }
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $retainFlag = if ($retain) { " [RETAIN]" } else { "" }
        Write-Host "[$timestamp] MQTT ✅$retainFlag $topic : $payload" -ForegroundColor Green
    }
    catch {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] MQTT ❌ Erreur: $_" -ForegroundColor Red
        Write-Host "[$timestamp] MQTT -> $topic : $payload" -ForegroundColor Yellow
    }
}



# =============================================================================
# FONCTION PRINCIPALE
# =============================================================================

function Initialize-HAAgent {
    Write-Host "=== Initialisation de l'agent Home Assistant pour Windows ===" -ForegroundColor Green
    Write-Host "Client ID: $ClientID" -ForegroundColor Yellow
    Write-Host "Broker MQTT: $MQTTBroker" -ForegroundColor Yellow
    Write-Host ""
    
    # Publication de la découverte Home Assistant (au démarrage uniquement)
    Publish-HADiscovery -ClientID $ClientID -BaseTopic $BaseTopic
    
    Write-Host "✅ Agent initialisé - publication des capteurs uniquement" -ForegroundColor Green
    Write-Host ""
}

function Publish-HAData {
    # État du PC
    $pcRunning = Test-PCRunning
    $usersLoggedIn = Test-UsersLoggedIn
    $loggedUsers = Get-LoggedUsers
    
    # Statistiques système
    $stats = Get-SystemStats
    
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
    
    # Heartbeat avec retain pour persistance
    Publish-MQTT "$BaseTopic/$ClientID/status" "online" $true
    
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

function Start-HAAgent {
    # Fonction de compatibilité - appelle les nouvelles fonctions
    Initialize-HAAgent
    Publish-HAData
}

# Fonction de nettoyage pour fermer la session MQTT
function Stop-HAAgent {
    if ($Global:MQTTSession -and $Global:MQTTSession.IsConnected) {
        try {
            Publish-MQTT "$BaseTopic/$ClientID/status" "offline" $true
            Disconnect-MQTTBroker -Session $Global:MQTTSession
            Write-Host "✅ Session MQTT fermée proprement" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠️ Erreur lors de la fermeture MQTT: $_" -ForegroundColor Yellow
        }
    }
}

# =============================================================================
# EXÉCUTION PRINCIPALE
# =============================================================================

# Exécution principale - capteurs seulement
Start-HAAgent
