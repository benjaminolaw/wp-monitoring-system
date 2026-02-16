#!/bin/bash
# /opt/wp-monitor/scripts/test_discovery.sh
# Test domain discovery on a single account

source /opt/wp-monitor/config/monitor.conf
source /opt/wp-monitor/scripts/domain_discovery.sh

echo "========================================="
echo "WordPress Monitor - Domain Discovery Test"
echo "========================================="

# Get a test account
echo "Fetching test account..."
test_account=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
    -N -e "
    SELECT 
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
    AND s.id IN (SELECT service_id FROM mod_wordpress_monitor WHERE monitoring_enabled = 1)
    LIMIT 1" 2>/dev/null)

if [ -z "$test_account" ]; then
    echo "No active accounts found with monitoring enabled"
    exit 1
fi

# Parse test account
service_id=$(echo "$test_account" | awk '{print $1}')
primary_domain=$(echo "$test_account" | awk '{print $2}')
server_host=$(echo "$test_account" | awk '{print $3}')
username=$(echo "$test_account" | awk '{print $4}')
server_user=$(echo "$test_account" | awk '{print $5}')
server_pass=$(echo "$test_account" | awk '{print $6}')

echo ""
echo "Test Account Details:"
echo "  Service ID: $service_id"
echo "  Primary Domain: $primary_domain"
echo "  Server: $server_host"
echo "  cPanel User: $username"
echo ""

# Run discovery
echo "Running domain discovery..."
discover_all_domains "$service_id" "$server_host" "$username" "$server_user" "$server_pass" "$primary_domain"

# Show results
echo ""
echo "Discovered Domains:"
echo "-------------------"
mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
    -e "SELECT id, domain, domain_type, doc_root, last_status 
        FROM mod_monitored_domains 
        WHERE service_id = $service_id 
        ORDER BY domain_type, domain" 2>/dev/null

echo ""
echo "Test complete!"