#!/bin/bash
# /opt/wp-monitor/scripts/reporting.sh
# Reporting module

# Send consolidated report to support
send_consolidated_report() {
    log_message "INFO" "Checking if report should be sent"
    
    local current_minute=$(date +%M)
    local send_report=0
    
    case $REPORT_FREQUENCY in
        "hourly")
            if [ "$current_minute" -eq 5 ]; then
                send_report=1
            fi
            ;;
        "daily")
            if [ "$(date +%H)" -eq 9 ] && [ "$current_minute" -eq 5 ]; then
                send_report=1
            fi
            ;;
        "instant")
            send_report=1
            ;;
    esac
    
    if [ $send_report -eq 1 ]; then
        generate_and_send_report
    fi
}

# Generate and send the report
generate_and_send_report() {
    log_message "INFO" "Generating consolidated report"
    
    local report_file="${REPORT_DIR}/report_$(date +%Y%m%d_%H%M%S).html"
    local text_file="${REPORT_DIR}/report_$(date +%Y%m%d_%H%M%S).txt"
    
    # Get down domains
    local down_domains=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -e "SELECT 
                d.domain,
                d.last_status as error,
                d.failure_count as failures,
                DATE_FORMAT(d.last_check, '%Y-%m-%d %H:%i') as last_checked,
                h.domain as main_account,
                c.firstname,
                c.lastname,
                c.email as client_email
            FROM mod_monitored_domains d
            JOIN tblhosting h ON d.service_id = h.id
            JOIN tblclients c ON h.userid = c.id
            WHERE d.last_status != 'OK'
            AND d.last_status IS NOT NULL
            AND d.failure_count >= $FAILURE_THRESHOLD
            ORDER BY d.last_check DESC" 2>/dev/null | tail -n +2)
    
    # Get statistics
    local total_domains=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -N -e "SELECT COUNT(*) FROM mod_monitored_domains WHERE is_active = 1" 2>/dev/null)
    
    local total_down=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -N -e "SELECT COUNT(*) FROM mod_monitored_domains WHERE last_status != 'OK' AND last_status IS NOT NULL" 2>/dev/null)
    
    local critical_down=$(mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
        -N -e "SELECT COUNT(*) FROM mod_monitored_domains WHERE last_status != 'OK' AND failure_count >= $FAILURE_THRESHOLD" 2>/dev/null)
    
    # Generate HTML report
    cat > "$report_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f44336; color: white; padding: 20px; text-align: center; }
        .summary { background: #f5f5f5; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .critical { color: #f44336; font-weight: bold; }
        .warning { color: #ff9800; font-weight: bold; }
        table { width: 100%%; border-collapse: collapse; margin-top: 20px; }
        th { background: #333; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; text-align: center; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚨 WordPress Monitor Alert Report</h1>
        <p>Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>
    </div>
    
    <div class="summary">
        <h2>📊 Summary</h2>
        <table>
            <tr><td>Total Monitored Domains:</td><td><strong>$total_domains</strong></td></tr>
            <tr><td>Domains with Issues:</td><td class="warning"><strong>$total_down</strong></td></tr>
            <tr><td>Critical Failures:</td><td class="critical"><strong>$critical_down</strong></td></tr>
        </table>
    </div>
    
    <h2>⚠️ Currently Down Domains</h2>
    <table>
        <tr>
            <th>Domain</th>
            <th>Error</th>
            <th>Failures</th>
            <th>Client</th>
            <th>Main Account</th>
            <th>Last Checked</th>
        </tr>
EOF
    
    # Add down domains to HTML
    if [ ! -z "$down_domains" ]; then
        echo "$down_domains" | while read line; do
            if [ ! -z "$line" ]; then
                domain=$(echo "$line" | awk '{print $1}')
                error=$(echo "$line" | awk '{print $2}')
                failures=$(echo "$line" | awk '{print $3}')
                last_checked=$(echo "$line" | awk '{print $4}')
                main_account=$(echo "$line" | awk '{print $5}')
                firstname=$(echo "$line" | awk '{print $6}')
                lastname=$(echo "$line" | awk '{print $7}')
                email=$(echo "$line" | awk '{print $8}')
                
                cat >> "$report_file" <<EOF
        <tr>
            <td><a href="http://$domain" target="_blank">$domain</a></td>
            <td class="critical">$error</td>
            <td>$failures</td>
            <td>$firstname $lastname<br><small>$email</small></td>
            <td>$main_account</td>
            <td>$last_checked</td>
        </tr>
EOF
            fi
        done
    else
        cat >> "$report_file" <<EOF
        <tr>
            <td colspan="6" style="text-align: center; color: #4CAF50;">
                ✅ No critical issues found at this time
            </td>
        </tr>
EOF
    fi
    
    # Close HTML
    cat >> "$report_file" <<EOF
    </table>
    
    <div class="footer">
        <p>This is an automated report from your WordPress Monitoring System.</p>
        <p>To configure alert settings, visit: https://client.harmonweb.com/clientarea.php</p>
    </div>
</body>
</html>
EOF
    
    # Generate plain text version
    {
        echo "WORDPRESS MONITOR ALERT REPORT"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "SUMMARY"
        echo "======="
        echo "Total Monitored Domains: $total_domains"
        echo "Domains with Issues: $total_down"
        echo "Critical Failures: $critical_down"
        echo ""
        echo "CRITICAL DOMAINS"
        echo "================"
        
        if [ ! -z "$down_domains" ]; then
            echo "$down_domains" | while read line; do
                domain=$(echo "$line" | awk '{print $1}')
                error=$(echo "$line" | awk '{print $2}')
                failures=$(echo "$line" | awk '{print $3}')
                echo "$domain - $error ($failures failures)"
            done
        else
            echo "No critical issues found"
        fi
    } > "$text_file"
    
    # Send email
    send_report_email "$report_file" "$text_file"
    
    log_message "INFO" "Report sent to $REPORT_EMAIL"
}

# Send email with both HTML and text versions
send_report_email() {
    local html_file=$1
    local text_file=$2
    local subject="[WordPress Monitor] Consolidated Report - $(date '+%Y-%m-%d %H:%M')"
    
    # Check if we have a valid email address
    if [ -z "$REPORT_EMAIL" ]; then
        log_message "ERROR" "No report email configured"
        return 1
    fi
    
    # Send email using mail command
    if command -v mail &>/dev/null; then
        {
            echo "To: $REPORT_EMAIL"
            echo "Subject: $subject"
            echo "MIME-Version: 1.0"
            echo "Content-Type: multipart/alternative; boundary=boundary123"
            echo ""
            echo "--boundary123"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            cat "$text_file"
            echo ""
            echo "--boundary123"
            echo "Content-Type: text/html; charset=UTF-8"
            echo ""
            cat "$html_file"
            echo ""
            echo "--boundary123--"
        } | sendmail -t
    else
        log_message "ERROR" "Mail command not found"
        return 1
    fi
}