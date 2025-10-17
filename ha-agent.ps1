# =============================================================================
# Script Home Assistant Agent pour Windows
# Fonctionnalités : État PC, utilisateurs connectés, capteurs système
# =============================================================================

# Log de démarrage initial pour le débogage du service
"Script démarré à $(Get-Date)" | Out-File -FilePath (Join-Path $PSScriptRoot "logs" "startup.log") -Append

# --- IMPORTANT ---
# Remplacez le chemin ci-dessous par le résultat de la commande 'Get-Module PSMQTT -ListAvailable | Select-Object Path'
# =============================================================================
# Script Home Assistant Agent pour Windows (Version Webhook)
# Fonctionnalités : Envoi des données système à un hook Node.js
# Aucune dépendance externe requise.
# =============================================================================

# =============================================================================
# CONFIGURATION
# =============================================================================
# L'URL de votre hook Node.js. À modifier lorsque le hook sera prêt.
$WebhookURL = "http://192.168.100.190:3000/ha-agent"
$IntervalSeconds = 60                  # Intervalle entre les envois (secondes)

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
    Write-Host "🚀 Démarrage HA-Agent (mode Webhook)"
    Write-Host "🎯 URL du Hook: $WebhookURL"
    Write-Host "📊 Intervalle: $IntervalSeconds secondes"
    Write-Host "Appuyez sur Ctrl+C pour arrêter."
    
    while ($true) {
        $payload = Get-SystemData
        $jsonPayload = $payload | ConvertTo-Json -Depth 5 -Compress
        
        try {
            Write-Host "-> Envoi des données pour $($payload.hostname)..."
            Invoke-RestMethod -Uri $WebhookURL -Method Post -Body $jsonPayload -ContentType 'application/json'
            Write-Host "✅ Données envoyées avec succès."
        } catch {
            Write-Host "❌ Erreur lors de l'envoi au webhook: $_" -ForegroundColor Red
        }
        
        Start-Sleep -Seconds $IntervalSeconds
    }
}
catch {
    Write-Host "❌ Erreur critique: $_" -ForegroundColor Red
}
