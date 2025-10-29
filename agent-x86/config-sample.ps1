
# ===============================
# Fichier de configuration ha-agent.ps1
# ===============================
# Modifiez les valeurs ci-dessous selon vos besoins.
#
# $WebhookURL           : URL du serveur webhook Node.js (ex : http://192.168.100.190:3000/ha-agent)
# $DataIntervalSeconds  : Intervalle (en secondes) entre chaque envoi complet de données (statut, capteurs, lock...)
# $PingIntervalSeconds  : Intervalle (en secondes) entre chaque ping de présence (statut minimal)
# $DebugMode            : true pour activer les logs détaillés, false pour un mode silencieux
# ===============================

$WebhookURL = "http://192.168.100.190:3000/ha-agent"   # URL du webhook
$DataIntervalSeconds = 60                               # Envoi complet toutes les 60s
$PingIntervalSeconds = 10                               # Ping toutes les 10s
$DebugMode = $true                                      # true = logs détaillés, false = silencieux
