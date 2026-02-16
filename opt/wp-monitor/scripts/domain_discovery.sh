#!/bin/bash
# /opt/wp-monitor/scripts/domain_discovery.sh
# Domain discovery module

# Discover all domains in a cPanel account
discover_all_domains() {
    local service_id=$1
    local server_host=$2
    local cpanel_user=$3
    local server_user=$4
    local server_pass=$5
    local primary_domain=$6
    
    log_message "INFO" "Starting domain discovery for $cpanel_user on $server_host"
    
    # Create temporary file for results
    local tmp_file="${TEMP_DIR}/discovery_${service_id}_$$.tmp"
    
    # Method 1: cPanel API via WHM
    log_message "DEBUG" "Attempting cPanel API discovery"
    
    ssh -o ConnectTimeout=$SSH_TIMEOUT \
        -o StrictHostKeyChecking=no \
        -i $SSH_KEY_PATH \
        "${server_user}@${server_host}" \
        "sudo -u $cpanel_user /usr/local/cpanel/bin/whmapi1 --output=json list_domains 2>/dev/null | \
         python3 -c '
import sys,json
try:
    data = json.load(sys.stdin)
    for domain in data.get(\"data\", {}).get(\"domains\", []):
        print(f\"{domain.get(\"domain\")}|{domain.get(\"documentroot\")}|{domain.get(\"domain_type\")}\")
except:
    pass'" > "$tmp_file" 2>/dev/null
    
    # Process discovered domains
    if [ -s "$tmp_file" ]; then
        while IFS='|' read -r domain doc_root domain_type; do
            if [ ! -z "$domain" ]; then
                # Clean up paths
                doc_root=$(echo "$doc_root" | sed "s|^/home/$cpanel_user/||" | sed 's|^/||')
                
                # Insert into database
                mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
                    -e "INSERT INTO mod_monitored_domains 
                        (service_id, domain, domain_type, doc_root, server_host, cpanel_user, is_active)
                        VALUES ($service_id, '$domain', '$domain_type', '$doc_root', '$server_host', '$cpanel_user', 1)
                        ON DUPLICATE KEY UPDATE 
                            domain_type = '$domain_type',
                            doc_root = '$doc_root',
                            server_host = '$server_host',
                            cpanel_user = '$cpanel_user',
                            is_active = 1,
                            discovered_at = NOW()" 2>/dev/null
                
                log_message "DEBUG" "Added domain: $domain ($domain_type)"
            fi
        done < "$tmp_file"
    fi
    
    # Method 2: Filesystem scan for WordPress
    log_message "DEBUG" "Scanning filesystem for WordPress installations"
    
    ssh -o ConnectTimeout=$SSH_TIMEOUT \
        -i $SSH_KEY_PATH \
        "${server_user}@${server_host}" \
        "find /home/$cpanel_user -type f -name 'wp-config.php' -exec dirname {} \; 2>/dev/null | \
         sed 's|/home/$cpanel_user/||'" > "${tmp_file}.wp" 2>/dev/null
    
    if [ -s "${tmp_file}.wp" ]; then
        while IFS= read -r wp_path; do
            if [ ! -z "$wp_path" ]; then
                local domain=""
                local domain_type="addon"
                
                if [ "$wp_path" == "public_html" ]; then
                    domain="$primary_domain"
                    domain_type="primary"
                elif [[ "$wp_path" == public_html/* ]]; then
                    local subpath=$(basename "$wp_path")
                    if [[ "$subpath" == *.* ]]; then
                        domain="$subpath"
                        domain_type="addon"
                    else
                        domain="$subpath.$primary_domain"
                        domain_type="subdomain"
                    fi
                fi
                
                if [ ! -z "$domain" ]; then
                    mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
                        -e "INSERT INTO mod_monitored_domains 
                            (service_id, domain, domain_type, doc_root, server_host, cpanel_user, is_active)
                            VALUES ($service_id, '$domain', '$domain_type', '$wp_path', '$server_host', '$cpanel_user', 1)
                            ON DUPLICATE KEY UPDATE 
                                domain_type = '$domain_type',
                                doc_root = '$wp_path',
                                is_active = 1" 2>/dev/null
                fi
            fi
        done < "${tmp_file}.wp"
    fi
    
    # Clean up
    rm -f "$tmp_file" "${tmp_file}.wp"
    
    log_message "INFO" "Domain discovery complete for $cpanel_user"
}