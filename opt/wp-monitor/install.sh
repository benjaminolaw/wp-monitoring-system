#!/bin/bash
# /opt/wp-monitor/install.sh
# Main installation script - Ubuntu Version

set -e

echo "========================================="
echo "WordPress Monitor Installation"
echo "Enhanced Version - Full Domain Discovery"
echo "Ubuntu Version"
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

# Update package list
echo ""
echo "Updating package lists..."
apt-get update

# Install required packages - Ubuntu specific
echo ""
echo "Installing required packages..."
apt-get install -y curl wget mysql-client sshpass \
    apache2-utils jq htop ntpdate \
    python3 python3-pip mailutils sendmail \
    netcat-openbsd openssh-client

# Note: netcat-openbsd is used instead of netcat
# For Ubuntu, we use netcat-openbsd which is the maintained version

# Set permissions
echo ""
echo "Setting permissions..."
chmod 755 /opt/wp-monitor/scripts
chmod 750 /opt/wp-monitor/config

# Copy configuration template if it doesn't exist
if [ ! -f /opt/wp-monitor/config/monitor.conf ]; then
    echo ""
    echo "Creating configuration file from template..."
    if [ -f /opt/wp-monitor/config/monitor.conf.example ]; then
        cp /opt/wp-monitor/config/monitor.conf.example /opt/wp-monitor/config/monitor.conf
        echo "✓ Configuration template created"
    else
        echo "⚠ Warning: monitor.conf.example not found"
        echo "Creating minimal configuration file..."
        cat > /opt/wp-monitor/config/monitor.conf << 'EOF'
#!/bin/bash
# /opt/wp-monitor/config/monitor.conf
# Main configuration file

# WHMCS Database Configuration
WHMCS_DB_HOST="your-whmcs-server-ip"
WHMCS_DB_NAME="whmcs"
WHMCS_DB_USER="whmcs_monitor"
WHMCS_DB_PASS="your-password"
WHMCS_DB_PORT="3306"

# Your Dedicated Servers
declare -A SERVERS=(
    ["server1"]="192.168.1.101:root:password:cpanel"
)

# SSH Configuration
SSH_KEY_PATH="/root/.ssh/monitoring_key"
SSH_TIMEOUT="10"

# Monitoring Settings
CHECK_INTERVAL="15"
SITES_PER_BATCH="100"
DELAY_BETWEEN_CHECKS="1"
FAILURE_THRESHOLD="2"

# Email Reports
REPORT_EMAIL="support@harmonweb.com"
REPORT_FREQUENCY="hourly"

# Domain Discovery Settings
DISCOVERY_FREQUENCY="24"
CACHE_DOMAINS="true"

# Logging
LOG_LEVEL="INFO"
LOG_RETENTION_DAYS="30"

# Paths
BASE_DIR="/opt/wp-monitor"
LOG_DIR="${BASE_DIR}/logs"
STATE_DIR="${BASE_DIR}/state"
REPORT_DIR="${BASE_DIR}/reports"
TEMP_DIR="/tmp/wp-monitor"
EOF
        echo "✓ Minimal configuration file created"
    fi
    echo "⚠ Please edit /opt/wp-monitor/config/monitor.conf with your settings"
fi

# Make scripts executable
echo ""
echo "Making scripts executable..."
find /opt/wp-monitor/scripts -type f -name "*.sh" -exec chmod +x {} \;
find /opt/wp-monitor/scripts -type f -name "*.php" -exec chmod +x {} \ 2>/dev/null || true

# Create log files
echo ""
echo "Creating log files..."
touch /var/log/wp-monitor/monitor.log
touch /var/log/wp-monitor/error.log
touch /var/log/wp-monitor/discovery.log
touch /var/log/wp-monitor/cron.log
touch /var/log/wp-monitor/cleanup.log
chmod 644 /var/log/wp-monitor/*.log

# Set up cron job
echo ""
echo "Setting up cron jobs..."

# Check if crontab exists for root
if ! crontab -l -u root &>/dev/null; then
    echo "" | crontab -u root -
fi

# Add cron jobs (check if they already exist)
current_crontab=$(crontab -l -u root 2>/dev/null || echo "")

if ! echo "$current_crontab" | grep -q "wp-monitor.sh"; then
    (echo "$current_crontab"; echo "*/5 * * * * /opt/wp-monitor/scripts/wp-monitor.sh >> /var/log/wp-monitor/cron.log 2>&1") | crontab -u root -
    echo "✓ Added main monitoring cron job"
fi

if ! echo "$current_crontab" | grep -q "force_discovery.sh"; then
    (crontab -l -u root 2>/dev/null; echo "0 2 * * * /opt/wp-monitor/scripts/force_discovery.sh >> /var/log/wp-monitor/discovery.log 2>&1") | crontab -u root -
    echo "✓ Added discovery cron job"
fi

if ! echo "$current_crontab" | grep -q "emergency_cleanup.sh"; then
    (crontab -l -u root 2>/dev/null; echo "0 * * * * /opt/wp-monitor/scripts/emergency_cleanup.sh >> /var/log/wp-monitor/cleanup.log 2>&1") | crontab -u root -
    echo "✓ Added cleanup cron job"
fi

# Set up log rotation
echo ""
echo "Setting up log rotation..."
cat > /etc/logrotate.d/wp-monitor << 'EOF'
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

# Create a test script to verify installation
echo ""
echo "Creating verification script..."
cat > /opt/wp-monitor/scripts/verify_installation.sh << 'EOF'
#!/bin/bash
# /opt/wp-monitor/scripts/verify_installation.sh

echo "========================================="
echo "WordPress Monitor - Installation Verification"
echo "========================================="

# Check configuration file
echo -n "Configuration file: "
if [ -f /opt/wp-monitor/config/monitor.conf ]; then
    echo "✓ Found"
else
    echo "✗ Missing"
fi

# Check required directories
echo -n "Log directory: "
if [ -d /var/log/wp-monitor ]; then
    echo "✓ Found"
else
    echo "✗ Missing"
fi

# Check required packages
echo -n "MySQL client: "
if command -v mysql &>/dev/null; then
    echo "✓ Installed"
else
    echo "✗ Missing"
fi

echo -n "SSH client: "
if command -v ssh &>/dev/null; then
    echo "✓ Installed"
else
    echo "✗ Missing"
fi

echo -n "Curl: "
if command -v curl &>/dev/null; then
    echo "✓ Installed"
else
    echo "✗ Missing"
fi

echo -n "Mail command: "
if command -v mail &>/dev/null; then
    echo "✓ Installed"
else
    echo "✗ Missing"
fi

# Check script permissions
echo -n "Main script permissions: "
if [ -x /opt/wp-monitor/scripts/wp-monitor.sh ]; then
    echo "✓ Executable"
else
    echo "✗ Not executable"
fi

# Check cron jobs
echo -n "Cron jobs: "
if crontab -l -u root 2>/dev/null | grep -q "wp-monitor"; then
    echo "✓ Configured"
else
    echo "✗ Not found"
fi

echo ""
echo "To complete setup:"
echo "1. Edit /opt/wp-monitor/config/monitor.conf with your database credentials"
echo "2. Run /opt/wp-monitor/scripts/setup_ssh_keys.sh"
echo "3. Test with: /opt/wp-monitor/scripts/test_discovery.sh"
echo "========================================="
EOF

chmod +x /opt/wp-monitor/scripts/verify_installation.sh

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
echo "3. Verify installation:"
echo "   /opt/wp-monitor/scripts/verify_installation.sh"
echo ""
echo "4. Test the setup:"
echo "   /opt/wp-monitor/scripts/test_discovery.sh"
echo ""
echo "5. Start monitoring:"
echo "   /opt/wp-monitor/scripts/wp-monitor.sh"
echo ""
echo "6. Check logs:"
echo "   tail -f /var/log/wp-monitor/monitor.log"
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