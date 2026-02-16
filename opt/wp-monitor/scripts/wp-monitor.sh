#!/bin/bash
# /opt/wp-monitor/scripts/wp-monitor.sh
# Main monitoring script

# Load configuration
source /opt/wp-monitor/config/monitor.conf

# Source modules
source /opt/wp-monitor/scripts/domain_discovery.sh
source /opt/wp-monitor/scripts/reporting.sh

# Logging function
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="${LOG_DIR}/monitor_$(date +%Y%m%d).log"
    
    # Create log directory if it doesn't exist
    mkdir -p "${LOG_DIR}"
    
    # Only log if level meets threshold
    case $LOG_LEVEL in
        DEBUG) ;;
        INFO)  [ "$level" == "DEBUG" ] && return ;;
        WARNING) [ "$level" == "DEBUG" ] || [ "$level" == "INFO" ] && return ;;
        ERROR) [ "$level" != "ERROR" ] && return ;;
    esac
    
    echo "$timestamp [$level] $message" >> "$log_file"
    
    # Also log to system logger if enabled
    if [ "$LOG_TO_SYSLOG" == "true" ]; then
        logger -t wp-monitor "$level: $message"
    fi
    
    # Log errors to separate file
    if [ "$level" == "ERROR" ]; then
        echo "$timestamp $message" >> "${LOG_DIR}/error.log"
    fi
}

# Check MySQL connection
check_mysql_connection() {
    mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
          -P "$WHMCS_DB_PORT" -e "SELECT 1" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Cannot connect to WHMCS database"
        return 1
    fi
    return 0
}

# Initialize database tables
init_database() {
    log_message "INFO" "Initializing database tables"
    
    mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" "$WHMCS_DB_NAME" < "${BASE_DIR}/scripts/create_tables.sql" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_message "INFO" "Database initialized successfully"
    else
        log_message "ERROR" "Failed to initialize database"
        return 1
    fi
}

# Get cPanel accounts to scan
get_cpanel_accounts() {
    log_message "INFO" "Fetching active cPanel accounts from WHMCS"
    
    mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
          -P "$WHMCS_DB_PORT" -N -e "
        SELECT DISTINCT
            s.id as service_id,
            d.domain as primary_domain,
            sv.hostname as server_host,
            s.username,
            s.password,
            sv.username as server_user,
            sv.password as server_pass,
            p.configoption1 as server_type
        FROM tblhosting s
        JOIN tblproducts p ON s.packageid = p.id
        JOIN tblservers sv ON p.server = sv.id
        LEFT JOIN tbldomains d ON s.domain = d.domain
        WHERE s.domainstatus = 'Active'
        AND s.id IN (SELECT service_id FROM mod_wordpress_monitor WHERE monitoring_enabled = 1)
        LIMIT 25" 2>/dev/null | while read -r line; do
        
        if [ ! -z "$line" ]; then
            echo "$line"
        fi
    done
}

# Check if domain discovery is needed
needs_domain_discovery() {
    local service_id=$1
    
    local last_discovery=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -N -e "SELECT MAX(discovered_at) FROM mod_monitored_domains WHERE service_id = $service_id" 2>/dev/null)
    
    if [ -z "$last_discovery" ] || [ "$last_discovery" == "NULL" ]; then
        return 0  # No discovery ever done
    fi
    
    local discovery_epoch=$(date -d "$last_discovery" +%s 2>/dev/null)
    if [ -z "$discovery_epoch" ]; then
        return 0
    fi
    
    local now_epoch=$(date +%s)
    local discovery_age=$((now_epoch - discovery_epoch))
    local discovery_threshold=$((DISCOVERY_FREQUENCY * 3600))
    
    if [ $discovery_age -gt $discovery_threshold ]; then
        return 0  # Needs rediscovery
    else
        return 1  # Recent enough
    fi
}

# Check a single domain
check_domain_health() {
    local domain_id=$1
    local service_id=$2
    local domain=$3
    local doc_root=$4
    local server_host=$5
    local cpanel_user=$6
    local server_user=$7
    
    log_message "DEBUG" "Checking $domain (ID: $domain_id)"
    
    # Create lock
    mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -e "INSERT INTO wp_monitoring_lock (domain_id, lock_time, server_host) 
            VALUES ($domain_id, NOW(), '$server_host')
            ON DUPLICATE KEY UPDATE lock_time = NOW(), server_host = '$server_host'" 2>/dev/null
    
    # HTTP check
    local protocol="http"
    if [ "$CHECK_HTTPS_FIRST" == "true" ]; then
        local https_status=$(curl -o /dev/null -s -w "%{http_code}" -L \
            --max-time $CURL_TIMEOUT \
            --connect-timeout $CURL_CONNECT_TIMEOUT \
            --insecure \
            --user-agent "$USER_AGENT" \
            "https://$domain" 2>/dev/null)
        
        if [ "$https_status" != "000" ] && [ "$https_status" != "502" ] && [ "$https_status" != "503" ] && [ "$https_status" != "404" ]; then
            protocol="https"
            working_status=$https_status
        fi
    fi
    
    if [ "$protocol" == "http" ]; then
        working_status=$(curl -o /dev/null -s -w "%{http_code}" -L \
            --max-time $CURL_TIMEOUT \
            --connect-timeout $CURL_CONNECT_TIMEOUT \
            --user-agent "$USER_AGENT" \
            "http://$domain" 2>/dev/null)
    fi
    
    log_message "DEBUG" "$domain returned HTTP $working_status"
    
    # Check if site is down
    if [ "$working_status" != "200" ] && [ "$working_status" != "301" ] && [ "$working_status" != "302" ]; then
        log_message "WARNING" "$domain is down (HTTP $working_status)"
        update_domain_status "$domain_id" "HTTP_ERROR_$working_status" 1
        return 1
    fi
    
    # WordPress check via SSH
    local wp_check_result=$(ssh -o ConnectTimeout=$SSH_TIMEOUT \
        -o StrictHostKeyChecking=no \
        -o PasswordAuthentication=no \
        -i $SSH_KEY_PATH \
        "${server_user}@${server_host}" \
        "cd /home/$cpanel_user/$doc_root 2>/dev/null && \
         if command -v wp &>/dev/null; then
            wp core verify --quiet 2>&1;
            wp db check --quiet 2>&1;
         else
            echo 'WP_CLI_NOT_FOUND';
         fi" 2>&1)
    
    local ssh_exit_code=$?
    
    # Analyze results
    if echo "$wp_check_result" | grep -q "WP_CLI_NOT_FOUND"; then
        log_message "DEBUG" "$domain: WP-CLI not available"
        update_domain_status "$domain_id" "OK" 0
    elif echo "$wp_check_result" | grep -q "Error establishing a database connection"; then
        log_message "WARNING" "$domain: Database connection error"
        update_domain_status "$domain_id" "DB_CONNECTION_ERROR" 1
    elif echo "$wp_check_result" | grep -q "WordPress database error"; then
        log_message "WARNING" "$domain: WordPress database error"
        update_domain_status "$domain_id" "DB_ERROR" 1
    elif echo "$wp_check_result" | grep -q "Fatal error"; then
        log_message "WARNING" "$domain: WordPress fatal error"
        update_domain_status "$domain_id" "FATAL_ERROR" 1
    elif [ $ssh_exit_code -ne 0 ] && [ ! -z "$wp_check_result" ]; then
        log_message "WARNING" "$domain: WordPress error (Code: $ssh_exit_code)"
        update_domain_status "$domain_id" "WORDPRESS_ERROR" 1
    else
        log_message "INFO" "$domain is healthy"
        update_domain_status "$domain_id" "OK" 0
    fi
    
    # Remove lock
    mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -e "DELETE FROM wp_monitoring_lock WHERE domain_id = $domain_id" 2>/dev/null
}

# Update domain status
update_domain_status() {
    local domain_id=$1
    local status=$2
    local failed=$3
    
    if [ $failed -eq 1 ]; then
        mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
            -e "UPDATE mod_monitored_domains 
                SET last_status = '$status',
                    last_check = NOW(),
                    failure_count = failure_count + 1
                WHERE id = $domain_id" 2>/dev/null
        
        local failure_count=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
            -N -e "SELECT failure_count FROM mod_monitored_domains WHERE id = $domain_id" 2>/dev/null)
        
        if [ $failure_count -ge $FAILURE_THRESHOLD ]; then
            queue_domain_alert "$domain_id" "$status"
        fi
    else
        mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
            -e "UPDATE mod_monitored_domains 
                SET last_status = 'OK',
                    last_check = NOW(),
                    failure_count = 0
                WHERE id = $domain_id" 2>/dev/null
    fi
}

# Queue domain alert for reporting
queue_domain_alert() {
    local domain_id=$1
    local status=$2
    
    local domain_info=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -N -e "SELECT domain, service_id FROM mod_monitored_domains WHERE id = $domain_id" 2>/dev/null)
    
    local domain=$(echo "$domain_info" | cut -f1)
    local service_id=$(echo "$domain_info" | cut -f2)
    
    # Check if we've already queued this domain recently
    local last_queued=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -N -e "SELECT MAX(created_at) FROM mod_monitor_reports 
                WHERE report_type = 'individual' 
                AND report_data LIKE '%$domain%'
                AND created_at > DATE_SUB(NOW(), INTERVAL $SUPPRESS_DUPLICATE_ALERTS SECOND)" 2>/dev/null)
    
    if [ -z "$last_queued" ]; then
        mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
            -e "INSERT INTO mod_monitor_reports (report_type, report_data) 
                VALUES ('individual', '{\"domain_id\":$domain_id,\"domain\":\"$domain\",\"service_id\":$service_id,\"status\":\"$status\",\"time\":\"$(date +%Y-%m-%d\ %H:%M:%S)\"}')" 2>/dev/null
    fi
}

# Main execution
main() {
    log_message "INFO" "=== Starting WordPress Monitor Run ==="
    
    # Create required directories
    mkdir -p "$LOG_DIR" "$STATE_DIR" "$REPORT_DIR" "$TEMP_DIR"
    
    # Check MySQL connection
    if ! check_mysql_connection; then
        log_message "ERROR" "Cannot continue without database connection"
        exit 1
    fi
    
    # Initialize database
    init_database
    
    # Get accounts to process
    accounts=$(get_cpanel_accounts)
    
    if [ -z "$accounts" ]; then
        log_message "INFO" "No accounts need checking"
    else
        log_message "INFO" "Processing accounts"
        
        echo "$accounts" | while read service_id primary_domain server_host username password server_user server_pass server_type; do
            # Clean variables
            service_id=$(echo "$service_id" | tr -d ' ')
            primary_domain=$(echo "$primary_domain" | tr -d ' ')
            server_host=$(echo "$server_host" | tr -d ' ')
            username=$(echo "$username" | tr -d ' ')
            server_user=$(echo "$server_user" | tr -d ' ')
            
            log_message "INFO" "Processing account: $username on $server_host"
            
            # Discover domains if needed
            if needs_domain_discovery "$service_id"; then
                log_message "INFO" "Discovering domains for $username"
                discover_all_domains "$service_id" "$server_host" "$username" "$server_user" "$server_pass" "$primary_domain"
            fi
            
            # Get domains to check
            domains=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
                -N -e "SELECT id, domain, doc_root, server_host, cpanel_user 
                       FROM mod_monitored_domains 
                       WHERE service_id = $service_id 
                       AND is_active = 1
                       AND (last_check IS NULL OR last_check < DATE_SUB(NOW(), INTERVAL $CHECK_INTERVAL MINUTE))
                       AND id NOT IN (SELECT domain_id FROM wp_monitoring_lock WHERE lock_time > DATE_SUB(NOW(), INTERVAL 30 MINUTE))
                       LIMIT $SITES_PER_BATCH" 2>/dev/null)
            
            if [ ! -z "$domains" ]; then
                echo "$domains" | while read domain_id domain doc_root server_host cpanel_user; do
                    domain_id=$(echo "$domain_id" | tr -d ' ')
                    domain=$(echo "$domain" | tr -d ' ')
                    doc_root=$(echo "$doc_root" | tr -d ' ')
                    
                    check_domain_health "$domain_id" "$service_id" "$domain" "$doc_root" \
                                      "$server_host" "$cpanel_user" "$server_user"
                    
                    sleep $DELAY_BETWEEN_CHECKS
                done
            fi
        done
    fi
    
    # Send reports
    send_consolidated_report
    
    # Cleanup
    mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -e "DELETE FROM wp_monitoring_lock WHERE lock_time < DATE_SUB(NOW(), INTERVAL 1 HOUR)" 2>/dev/null
    
    find "$LOG_DIR" -name "*.log" -mtime +$LOG_RETENTION_DAYS -delete
    
    log_message "INFO" "=== WordPress Monitor Run Complete ==="
}

# Run main function
main "$@"