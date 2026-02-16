#!/bin/bash
# /opt/wp-monitor/install.sh
# Main installation script

set -e

echo "========================================="
echo "WordPress Monitor VPS Installation"
echo "Enhanced Version - Full Domain Discovery"
echo "========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Create directory structure
echo ""
echo "Creating directory structure..."
mkdir -p /opt/wp-monitor/{config,scripts,logs,state,reports,temp}
mkdir -p /var/log/wp-monitor
mkdir -p /root/.ssh

# Install required packages
echo ""
echo "Installing required packages..."
apt-get update
apt-get install -y curl wget mysql-client sshpass \
    apache2-utils jq htop ntpdate \
    python3 python3-pip mailutils sendmail \
    netcat openssh-client

# Set permissions
echo ""
echo "Setting permissions..."
chmod 755 /opt/wp-monitor/scripts
chmod 750 /opt/wp-monitor/config

# Copy configuration template if it doesn't exist
if [ ! -f /opt/wp-monitor/config/monitor.conf ]; then
    echo ""
    echo "Creating configuration file from template..."
    cp /opt/wp-monitor/config/monitor.conf.example /opt/wp-monitor/config/monitor.conf
    echo "✓ Please edit /opt/wp-monitor/config/monitor.conf with your settings"
fi

# Make scripts executable
echo ""
echo "Making scripts executable..."
chmod +x /opt/wp-monitor/scripts/*.sh
chmod +x /opt/wp-monitor/scripts/*.php

# Create log files
echo ""
echo "Creating log files..."
touch /var/log/wp-monitor/monitor.log
touch /var/log/wp-monitor/error.log
touch /var/log/wp-monitor/discovery.log
chmod 644 /var/log/wp-monitor/*.log

# Set up cron job
echo ""
echo "Setting up cron jobs..."
cat > /etc/cron.d/wp-monitor <<EOF
# WordPress Monitor - Main monitoring (every 5 minutes)
*/5 * * * * root /opt/wp-monitor/scripts/wp-monitor.sh >> /var/log/wp-monitor/cron.log 2>&1

# Full domain discovery (daily at 2 AM)
0 2 * * * root /opt/wp-monitor/scripts/force_discovery.sh >> /var/log/wp-monitor/discovery.log 2>&1

# Emergency cleanup (hourly)
0 * * * * root /opt/wp-monitor/scripts/emergency_cleanup.sh >> /var/log/wp-monitor/cleanup.log 2>&1
EOF

chmod 644 /etc/cron.d/wp-monitor

# Set up log rotation
echo ""
echo "Setting up log rotation..."
cat > /etc/logrotate.d/wp-monitor <<EOF
/var/log/wp-monitor/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    sharedscripts
    postrotate
        systemctl restart cron >/dev/null 2>&1 || true
    endscript
}

/opt/wp-monitor/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Edit configuration:"
echo "   nano /opt/wp-monitor/config/monitor.conf"
echo ""
echo "2. Set up SSH keys:"
echo "   /opt/wp-monitor/scripts/setup_ssh_keys.sh"
echo ""
echo "3. Test the setup:"
echo "   /opt/wp-monitor/scripts/test_discovery.sh"
echo ""
echo "4. Start monitoring:"
echo "   /opt/wp-monitor/scripts/wp-monitor.sh"
echo ""
echo "5. Check logs:"
echo "   tail -f /var/log/wp-monitor/monitor.log"
echo ""
echo "6. Monitor reports will be sent to: support@harmonweb.com"
echo ""
echo "Directory Structure:"
echo "  /opt/wp-monitor/"
echo "  ├── config/     - Configuration files"
echo "  ├── scripts/    - All monitoring scripts"
echo "  ├── logs/       - Local log files"
echo "  ├── state/      - Runtime state files"
echo "  ├── reports/    - Generated reports"
echo "  └── temp/       - Temporary files"
echo ""
echo "========================================="