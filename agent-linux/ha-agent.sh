#!/bin/bash

# =============================================================================
# Script Home Assistant Agent pour Linux
# Fonctionnalités : État PC, utilisateurs connectés, capteurs système
# =============================================================================

# Forcer l'utilisation du format anglais (point comme séparateur décimal)
export LC_ALL=C
export LC_NUMERIC=C

# =============================================================================
# CONFIGURATION
# =============================================================================
WEBHOOK_URL="http://localhost:3000/ha-agent"
DATA_INTERVAL=60  # Intervalle pour l'envoi des données complètes (secondes)
PING_INTERVAL=10  # Intervalle pour le ping de présence (secondes)

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

# Obtenir l'adresse MAC principale
get_primary_mac_address() {
    # Essayer de récupérer la MAC de l'interface réseau active
    local mac=$(ip -o link show | grep -v "lo:" | grep "state UP" | head -n1 | awk '{print $17}')
    
    # Si pas trouvée, prendre la première interface avec une MAC
    if [ -z "$mac" ]; then
        mac=$(ip -o link show | grep -v "lo:" | head -n1 | awk '{print $17}')
    fi
    
    echo "$mac" | tr '[:upper:]' '[:lower:]'
}

# Générer le device_id
get_device_id() {
    local hostname=$(hostname)
    local mac=$(get_primary_mac_address)
    
    if [ -n "$mac" ]; then
        local mac_clean=$(echo "$mac" | tr -d ':')
        echo "${hostname}-${mac_clean}" | tr '[:upper:]' '[:lower:]'
    else
        echo "${hostname}" | tr '[:upper:]' '[:lower:]'
    fi
}

# Collecter les données système
get_system_data() {
    local hostname=$(hostname)
    local mac=$(get_primary_mac_address)
    local device_id=$(get_device_id)

    # --- Utilisateurs connectés ---
    local users_list=$(who | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')
    local users_count=$(who | awk '{print $1}' | sort -u | wc -l)
    local users_logged_in="false"
    if [ "$users_count" -gt 0 ]; then
        users_logged_in="true"
    fi

    # --- Détection de session verrouillée/déverrouillée ---
    local session_locked="null"
    # Méthode 1 : vérifier la présence d'un screensaver actif (gnome, cinnamon, etc.)
    if command -v gnome-screensaver-command >/dev/null 2>&1; then
        if gnome-screensaver-command -q 2>/dev/null | grep -q 'is active'; then
            session_locked="true"
        else
            session_locked="false"
        fi
    elif command -v loginctl >/dev/null 2>&1; then
        # Méthode 2 : loginctl (systemd)
        local session_id=$(loginctl | awk '/tty/ {print $1; exit}')
        if [ -n "$session_id" ]; then
            local lock_state=$(loginctl show-session $session_id -p Locked | cut -d'=' -f2)
            if [ "$lock_state" = "yes" ]; then
                session_locked="true"
            elif [ "$lock_state" = "no" ]; then
                session_locked="false"
            fi
        fi
    fi

    # --- CPU Usage ---
    # Méthode plus fiable : utiliser mpstat ou calculer depuis /proc/stat
    local cpu_idle=$(top -bn2 -d 0.5 | grep "Cpu(s)" | tail -1 | awk '{print $8}' | cut -d'%' -f1)
    if [ -z "$cpu_idle" ] || [ "$cpu_idle" = "id," ]; then
        # Fallback si top ne fonctionne pas comme prévu
        cpu_idle=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print 100-usage}')
    fi
    local cpu_percent=$(LC_NUMERIC=C awk "BEGIN {printf \"%.1f\", 100 - $cpu_idle}")

    # --- RAM Usage ---
    local ram_total=$(free -m | awk '/^Mem:/ {print $2}')
    local ram_used=$(free -m | awk '/^Mem:/ {print $3}')
    local ram_percent=$(LC_NUMERIC=C awk "BEGIN {if ($ram_total > 0) printf \"%.1f\", ($ram_used/$ram_total)*100; else print \"0.0\"}")
    local ram_used_gb=$(LC_NUMERIC=C awk "BEGIN {printf \"%.2f\", $ram_used/1024}")

    # --- Disk Usage (partition racine) ---
    local disk_percent=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    [ -z "$disk_percent" ] && disk_percent="0"

    # --- Construction du JSON (compact, sur une seule ligne) ---
    printf '{"device_id":"%s","hostname":"%s","mac_address":"%s","pc_running":true,"users_logged_in":%s,"logged_users_count":%s,"logged_users":"%s","session_locked":%s,"sensors":{"cpu_percent":%s,"ram_percent":%s,"ram_used_gb":%s,"disk_percent":%s}}' \
        "$device_id" "$hostname" "$mac" "$users_logged_in" "$users_count" "$users_list" "$session_locked" "$cpu_percent" "$ram_percent" "$ram_used_gb" "$disk_percent"
}

# Envoyer un ping
send_ping() {
    local device_id=$(get_device_id)
    local hostname=$(hostname)
    
    local json=$(cat <<EOF
{
  "device_id": "$device_id",
  "hostname": "$hostname",
  "status": "online"
}
EOF
)
    
    curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$json" > /dev/null 2>&1
}

# Envoyer les données complètes
send_data() {
    local json=$(get_system_data)
    
    # Debug: afficher le JSON généré
    echo "DEBUG - JSON envoyé:"
    echo "$json"
    echo "---"
    
    # Envoyer avec curl et capturer le code de statut HTTP
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$json")
    
    if [ "$http_code" = "200" ]; then
        echo "OK. Donnees envoyees avec succes."
    else
        echo "ERREUR: Webhook a retourne HTTP $http_code"
        # Essayer d'obtenir le détail de l'erreur
        local error_detail=$(curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$json")
        echo "Detail: $error_detail"
        send_error "Erreur HTTP $http_code lors de l'envoi des donnees"
    fi
}

# Envoyer une erreur
send_error() {
    local error_msg="$1"
    local device_id=$(get_device_id)
    local hostname=$(hostname)
    
    local json=$(cat <<EOF
{
  "device_id": "$device_id",
  "hostname": "$hostname",
  "status": "error",
  "error": "$error_msg"
}
EOF
)
    
    curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$json" > /dev/null 2>&1
}

# =============================================================================
# EXÉCUTION PRINCIPALE
# =============================================================================

echo ">> Demarrage HA-Agent (mode Webhook) - Linux"
echo "URL du Hook: $WEBHOOK_URL"
echo "Intervalle Donnees: $DATA_INTERVAL secondes / Ping: $PING_INTERVAL secondes"
echo "Appuyez sur Ctrl+C pour arreter."
echo ""

# Calculer combien de boucles de ping avant d'envoyer les données
loops_per_data_send=$((DATA_INTERVAL / PING_INTERVAL))
loop_counter=0

# Boucle principale
while true; do
    if [ $((loop_counter % loops_per_data_send)) -eq 0 ]; then
        echo "-> Collecte et envoi des donnees completes..."
        send_data
        echo "OK. Donnees envoyees avec succes."
    else
        echo "-> Envoi du ping..."
        send_ping
        echo "OK. Ping envoye."
    fi
    
    sleep $PING_INTERVAL
    ((loop_counter++))
done
