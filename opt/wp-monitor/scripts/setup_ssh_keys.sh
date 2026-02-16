#!/bin/bash
# /opt/wp-monitor/scripts/setup_ssh_keys.sh

source /opt/wp-monitor/config/monitor.conf

echo "========================================="
echo "SSH Key Setup for WordPress Monitor"
echo "========================================="

# Generate SSH key if it doesn't exist
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "wp-monitor@$(hostname)"
    echo "✓ SSH key generated"
fi

# Install sshpass if needed
if ! command -v sshpass &> /dev/null; then
    echo "Installing sshpass..."
    apt-get install -y sshpass
fi

# Loop through servers
for server_name in "${!SERVERS[@]}"; do
    IFS=':' read -r server_ip server_user server_pass server_type <<< "${SERVERS[$server_name]}"
    
    echo ""
    echo "Setting up $server_name ($server_ip)"
    echo "----------------------------------------"
    
    # Copy SSH key
    echo -n "Copying SSH key... "
    sshpass -p "$server_pass" ssh-copy-id -o StrictHostKeyChecking=no \
        -i "${SSH_KEY_PATH}.pub" "${server_user}@${server_ip}" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✓ Success"
        
        # Test connection
        echo -n "Testing connection... "
        if ssh -o ConnectTimeout=5 -o BatchMode=yes -i "$SSH_KEY_PATH" \
           "${server_user}@${server_ip}" "echo OK" 2>/dev/null | grep -q "OK"; then
            echo "✓ OK"
            
            # Check for wp-cli
            echo -n "Checking for wp-cli... "
            if ssh -i "$SSH_KEY_PATH" "${server_user}@${server_ip}" "command -v wp" >/dev/null 2>&1; then
                echo "✓ Found"
            else
                echo "✗ Not found (optional)"
            fi
        else
            echo "✗ Failed"
        fi
    else
        echo "✗ Failed to copy SSH key"
    fi
done

echo ""
echo "========================================="
echo "SSH key setup complete!"
echo "========================================="