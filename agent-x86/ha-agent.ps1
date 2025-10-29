# =============================================================================
# Script Home Assistant Agent pour Windows
# Fonctionnalités : État PC, utilisateurs connectés, capteurs système
# =============================================================================

# --- IMPORTANT ---
# =============================================================================
# Script Home Assistant Agent pour Windows (Version Webhook)
# Fonctionnalités : Envoi des données système à un hook Node.js
# Aucune dépendance externe requise.
# =============================================================================


# =============================================================================
# CONFIGURATION (chargée depuis config.ps1)
# =============================================================================
$configPath = Join-Path $PSScriptRoot "config.ps1"
if (Test-Path $configPath) {
    . $configPath
} else {
    Write-Host "[ERREUR] Fichier de configuration config.ps1 introuvable dans $PSScriptRoot" -ForegroundColor Red
    exit 1
}

# Construction dynamique de l'URL du webhook
$WebhookURL = "http://$WebhookHost`:$WebhookPort/ha-agent"

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

function Get-PrimaryMacAddress {
    try {
        $activeAdapter = Get-CimInstance Win32_NetworkAdapter | Where-Object {
            $_.NetEnabled -eq $true -and $_.AdapterTypeId -eq 0 -and $_.MACAddress -ne $null
        } | Select-Object -First 1
        
        if ($activeAdapter -and $activeAdapter.MACAddress) {
            return $activeAdapter.MACAddress.Replace("-", ":").ToLower()
        }
        
        $fallbackAdapter = Get-CimInstance Win32_NetworkAdapter | Where-Object {
            $_.MACAddress -ne $null -and $_.MACAddress -ne ""
        } | Select-Object -First 1
        
        if ($fallbackAdapter -and $fallbackAdapter.MACAddress) {
            return $fallbackAdapter.MACAddress.Replace("-", ":").ToLower()
        }
        return $null
    } catch { return $null }
}

function Get-DeviceID {
    $hostname = $env:COMPUTERNAME
    $macAddress = Get-PrimaryMacAddress
    
    if ($macAddress) {
        $macClean = $macAddress.Replace(":", "")
        return "$($hostname.ToLower())-$($macClean)"
    } else {
        return "$($hostname.ToLower())"
    }
}

# =============================================================================
# FONCTIONS DE COLLECTE DE DONNÉES
# =============================================================================

function Get-SystemData {
    # --- Données de base ---
    $hostname = $env:COMPUTERNAME
    $macAddress = Get-PrimaryMacAddress
    $deviceID = Get-DeviceID

    # --- Utilisateurs ---
    $users = @()
    try {
        $sessions = query user 2>$null
        if ($sessions.Count -gt 1) {
            foreach ($line in $sessions[1..($sessions.Count-1)]) {
                $parts = $line -split '\s+' | Where-Object { $_ -ne '' }
                if ($parts.Count -ge 1 -and $parts[0] -notmatch 'USERNAME|services|console') {
                    $users += $parts[0] -replace '^>', ''
                }
            }
        }
    } catch {}

    # --- Détection de session verrouillée/déverrouillée (LogonUI) ---
    $sessionLockState = "Unknown"
    $isLocked = $false
    try {
        $logonUI = Get-Process -Name LogonUI -ErrorAction SilentlyContinue
        if ($logonUI) {
            $sessionLockState = "Locked"
            $isLocked = $true
        } else {
            $sessionLockState = "Unlocked"
            $isLocked = $false
        }
    } catch {
        $sessionLockState = "Unknown"
        $isLocked = $false
    }
    if ($DebugMode) {
        Write-Host "[DEBUG] session_locked détecté (LogonUI): $sessionLockState ($isLocked)"
    }

    # --- Capteurs système ---
    $stats = @{}
    try {
        # CPU - protection contre les valeurs nulles
        $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        if ($cpu -eq $null -or $cpu -lt 0 -or $cpu -gt 100) { $cpu = 0 }
        
        # RAM - protection complète contre division par zéro
        $os = Get-CimInstance Win32_OperatingSystem
        $ramTotal = if ($os.TotalVisibleMemorySize) { [math]::Round($os.TotalVisibleMemorySize / 1MB, 2) } else { 0 }
        $ramFree = if ($os.FreePhysicalMemory) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { 0 }
        $ramUsed = if ($ramTotal -gt 0 -and $ramFree -ge 0) { $ramTotal - $ramFree } else { 0 }
        
        # Disque - protection complète contre division par zéro
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskTotal = if ($disk -and $disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { 0 }
        $diskFree = if ($disk -and $disk.FreeSpace) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { 0 }
        
        $stats = @{
            cpu_percent = [math]::Round($cpu, 1)
            ram_percent = if ($ramTotal -gt 0) { [math]::Round(($ramUsed / $ramTotal) * 100, 1) } else { 0 }
            ram_used_gb = if ($ramUsed -gt 0) { [math]::Round($ramUsed / 1024, 2) } else { 0 }
            disk_percent = if ($diskTotal -gt 0 -and $diskFree -ge 0) { [math]::Round((($diskTotal - $diskFree) / $diskTotal) * 100, 1) } else { 0 }
        }
    } catch {
        if ($DebugMode) {
            Write-Host "ERREUR lors de la collecte des statistiques système: $_" -ForegroundColor Red
        }
        # Valeurs par défaut en cas d'erreur
        $stats = @{
            cpu_percent = 0
            ram_percent = 0
            ram_used_gb = 0
            disk_percent = 0
        }
    }

    # --- Assemblage final ---
    $payload = @{
        device_id = $deviceID
        hostname = $hostname
        mac_address = $macAddress
        pc_running = $true
        users_logged_in = $users.Count -gt 0
        logged_users_count = $users.Count
        logged_users = ($users -join ",")
        session_locked = $isLocked
        session_locked_state = $sessionLockState
        sensors = $stats
    }

    return $payload
}

# =============================================================================
# EXÉCUTION PRINCIPALE
# =============================================================================

try {
    Write-Host ">> Demarrage HA-Agent (mode Webhook)"
    Write-Host "URL du Hook: $WebhookURL"
    Write-Host "Intervalle Donnees: $DataIntervalSeconds secondes / Ping: $PingIntervalSeconds secondes"
    Write-Host "Appuyez sur Ctrl+C pour arreter."
    
    $loopCounter = 0
    $loopsPerDataSend = [math]::Round($DataIntervalSeconds / $PingIntervalSeconds)

    while ($true) {
        $deviceID = Get-DeviceID
        $hostname = $env:COMPUTERNAME
        $payload = $null
        
        try {
            # Toutes les 60 secondes (ou au premier passage), envoyer les données complètes
            if ($loopCounter % $loopsPerDataSend -eq 0) {
                if ($DebugMode) { Write-Host "-> Collecte et envoi des donnees completes pour $hostname..." }
                $payload = Get-SystemData
            } 
            # Sinon, envoyer juste un ping
            else {
                if ($DebugMode) { Write-Host "-> Envoi du ping pour $hostname..." }
                $payload = @{
                    device_id = $deviceID
                    hostname = $hostname
                    status = "online"
                }
            }

            $jsonPayload = $payload | ConvertTo-Json -Depth 5 -Compress
            Invoke-RestMethod -Uri $WebhookURL -Method Post -Body $jsonPayload -ContentType 'application/json'
            if ($DebugMode) { Write-Host "OK. Donnees envoyees avec succes." }

        } catch {
            if ($DebugMode) { Write-Host "ERREUR lors de l'envoi au webhook: $_" -ForegroundColor Red }
            # En cas d'erreur, on envoie un payload d'erreur au webhook
            try {
                # Nettoyer le message d'erreur pour éviter les problèmes d'encodage
                $errorMessage = $_.Exception.Message -replace '[^\x20-\x7E]', '?' # Remplacer les caractères non-ASCII par ?
                if ([string]::IsNullOrEmpty($errorMessage)) {
                    $errorMessage = "Erreur inconnue lors de la collecte des donnees"
                }
                
                $errorPayload = @{
                    device_id = $deviceID
                    hostname = $hostname
                    status = "error"
                    error = $errorMessage
                } | ConvertTo-Json -Depth 5 -Compress
                Invoke-RestMethod -Uri $WebhookURL -Method Post -Body $errorPayload -ContentType 'application/json'
                if ($DebugMode) { Write-Host "-> Notification d'erreur envoyee au webhook." }
            } catch {
                if ($DebugMode) { Write-Host "ERREUR critique: Impossible de contacter le webhook pour signaler l'erreur." -ForegroundColor DarkRed }
            }
        }
        
        Start-Sleep -Seconds $PingIntervalSeconds
        $loopCounter++
    }
}
catch {
    if ($DebugMode) { Write-Host "ERREUR critique non geree: $_" -ForegroundColor Red }
}
