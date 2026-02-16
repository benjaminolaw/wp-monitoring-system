#!/usr/bin/php
<?php
/**
 * /opt/wp-monitor/scripts/send_whmcs_alert.php
 * Send alerts through WHMCS
 */

if ($argc < 3) {
    die("Usage: send_whmcs_alert.php <service_id> <error_type>\n");
}

$service_id = $argv[1];
$error_type = $argv[2];

// Configuration - load from environment or config file
$config_file = '/opt/wp-monitor/config/monitor.conf';
$config = parse_ini_file($config_file);

$db_host = $config['WHMCS_DB_HOST'] ?? 'localhost';
$db_name = $config['WHMCS_DB_NAME'] ?? 'whmcs';
$db_user = $config['WHMCS_DB_USER'] ?? 'whmcs_monitor';
$db_pass = $config['WHMCS_DB_PASS'] ?? '';

try {
    $pdo = new PDO(
        "mysql:host=$db_host;dbname=$db_name;charset=utf8",
        $db_user,
        $db_pass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    
    // Get service and client info
    $stmt = $pdo->prepare("
        SELECT h.id, h.domain, h.userid, c.firstname, c.lastname, c.email
        FROM tblhosting h
        JOIN tblclients c ON h.userid = c.id
        WHERE h.id = ?
    ");
    $stmt->execute([$service_id]);
    $service = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$service) {
        die("Service not found\n");
    }
    
    // Log the alert
    $log_entry = sprintf(
        "[%s] Alert for Service %d (%s): %s\n",
        date('Y-m-d H:i:s'),
        $service_id,
        $service['domain'],
        $error_type
    );
    file_put_contents('/opt/wp-monitor/logs/alerts.log', $log_entry, FILE_APPEND);
    
    echo "Alert logged for {$service['domain']}: {$error_type}\n";
    
} catch (PDOException $e) {
    die("Database error: " . $e->getMessage() . "\n");
}