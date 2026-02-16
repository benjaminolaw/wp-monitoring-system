#!/bin/bash
# /opt/wp-monitor/scripts/force_discovery.sh
# Force domain discovery for all accounts

source /opt/wp-monitor/config/monitor.conf
source /opt/wp-monitor/scripts/domain_discovery.sh

LOG_FILE="${LOG_DIR}/discovery.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" >> "$LOG_FILE"
}

log_message "INFO" "Starting forced domain discovery"

# Get all active accounts
accounts=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
    -N -e "
    SELECT DISTINCT
        s.id,
        d.domain,
        sv.hostname,
        s.username,
        sv.username,
        sv.password
    FROM tblhosting s
    JOIN tblproducts p ON s.packageid = p.id
    JOIN tblservers sv ON p.server = sv.id
    LEFT JOIN tbldomains d ON s.domain = d.domain
    WHERE s.domainstatus = 'Active'
    AND s.id IN (SELECT service_id FROM mod_wordpress_monitor WHERE monitoring_enabled = 1)" 2>/dev/null)

count=0
echo "$accounts" | while read service_id primary_domain server_host username server_user server_pass; do
    if [ ! -z "$service_id" ]; then
        service_id=$(echo "$service_id" | tr -d ' ')
        primary_domain=$(echo "$primary_domain" | tr -d ' ')
        server_host=$(echo "$server_host" | tr -d ' ')
        username=$(echo "$username" | tr -d ' ')
        server_user=$(echo "$server_user" | tr -d ' ')
        
        log_message "INFO" "Discovering domains for $username on $server_host"
        discover_all_domains "$service_id" "$server_host" "$username" "$server_user" "$server_pass" "$primary_domain"
        
        count=$((count + 1))
    fi
done

log_message "INFO" "Forced discovery complete for $count accounts"