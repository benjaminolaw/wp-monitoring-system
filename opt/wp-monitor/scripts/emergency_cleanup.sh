#!/bin/bash
# /opt/wp-monitor/scripts/emergency_cleanup.sh
# Emergency cleanup script for stuck locks and stale data

source /opt/wp-monitor/config/monitor.conf

echo "========================================="
echo "Emergency Cleanup - $(date)"
echo "========================================="

# Clean old locks (older than 2 hours)
echo "Cleaning old locks..."
mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
    -e "DELETE FROM wp_monitoring_lock WHERE lock_time < DATE_SUB(NOW(), INTERVAL 2 HOUR)" 2>/dev/null
echo "✓ Locks cleaned"

# Reset stuck domains (failure_count > 10)
echo "Resetting stuck domains..."
mysql -h "$WHMCS_DB_HOST" -u "$WHMCS_DB_USER" -p"$WHMCS_DB_PASS" \
    -e "UPDATE mod_monitored_domains SET failure_count = 0 WHERE failure_count > 10" 2>/dev/null
echo "✓ Stuck domains reset"

# Clean old temp files
echo "Cleaning temp files..."
find /tmp -name "wp-monitor-*" -type f -mtime +1 -delete 2>/dev/null
find "$TEMP_DIR" -type f -mtime +1 -delete 2>/dev/null
echo "✓ Temp files cleaned"

# Clean old logs
echo "Cleaning old logs..."
find "$LOG_DIR" -name "*.log" -mtime +$LOG_RETENTION_DAYS -delete
echo "✓ Old logs cleaned"

echo ""
echo "Emergency cleanup complete!"