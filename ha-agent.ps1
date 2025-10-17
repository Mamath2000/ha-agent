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
# CONFIGURATION
# =============================================================================
# L'URL de votre hook Node.js.
$WebhookURL = "http://192.168.100.190:3000/ha-agent"
$DataIntervalSeconds = 60  # Intervalle pour l'envoi des données complètes
$PingIntervalSeconds = 10  # Intervalle pour le ping de présence

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

    # --- Capteurs système ---
    $stats = @{}
    try {
        $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        
        $os = Get-CimInstance Win32_OperatingSystem
        $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $ramUsed = $ramTotal - $ramFree
        
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskTotal = [math]::Round($disk.Size / 1GB, 2)
        $diskFree = [math]::Round($disk.FreeSpace / 1GB, 2)
        
        $stats = @{
            cpu_percent = [math]::Round($cpu, 1)
            ram_percent = if ($ramTotal -gt 0) { [math]::Round(($ramUsed / $ramTotal) * 100, 1) } else { 0 }
            ram_used_gb = [math]::Round($ramUsed / 1024, 2)
            disk_percent = if ($diskTotal -gt 0) { [math]::Round((($diskTotal - $diskFree) / $diskTotal) * 100, 1) } else { 0 }
        }
    } catch {}

    # --- Assemblage final ---
    $payload = @{
        device_id = $deviceID
        hostname = $hostname
        mac_address = $macAddress
        pc_running = $true
        users_logged_in = $users.Count -gt 0
        logged_users_count = $users.Count
        logged_users = ($users -join ",")
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
                Write-Host "-> Collecte et envoi des donnees completes pour $hostname..."
                $payload = Get-SystemData
            } 
            # Sinon, envoyer juste un ping
            else {
                Write-Host "-> Envoi du ping pour $hostname..."
                $payload = @{
                    device_id = $deviceID
                    hostname = $hostname
                    status = "online"
                }
            }

            $jsonPayload = $payload | ConvertTo-Json -Depth 5 -Compress
            Invoke-RestMethod -Uri $WebhookURL -Method Post -Body $jsonPayload -ContentType 'application/json'
            Write-Host "OK. Donnees envoyees avec succes."

        } catch {
            Write-Host "ERREUR lors de l'envoi au webhook: $_" -ForegroundColor Red
            # En cas d'erreur, on envoie un payload d'erreur au webhook
            try {
                $errorPayload = @{
                    device_id = $deviceID
                    hostname = $hostname
                    status = "error"
                    error = $_.Exception.Message
                } | ConvertTo-Json -Depth 5 -Compress
                Invoke-RestMethod -Uri $WebhookURL -Method Post -Body $errorPayload -ContentType 'application/json'
                Write-Host "-> Notification d'erreur envoyee au webhook."
            } catch {
                Write-Host "ERREUR critique: Impossible de contacter le webhook pour signaler l'erreur." -ForegroundColor DarkRed
            }
        }
        
        Start-Sleep -Seconds $PingIntervalSeconds
        $loopCounter++
    }
}
catch {
    Write-Host "ERREUR critique non geree: $_" -ForegroundColor Red
}
