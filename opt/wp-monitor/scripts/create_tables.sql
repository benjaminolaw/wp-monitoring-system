-- /opt/wp-monitor/scripts/create_tables.sql
-- Database schema for WordPress Monitor

-- Main monitoring table for service-level settings
CREATE TABLE IF NOT EXISTS `mod_wordpress_monitor` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `service_id` int(11) NOT NULL,
    `monitoring_enabled` tinyint(1) DEFAULT '0',
    `last_check` datetime DEFAULT NULL,
    `last_status` varchar(50) DEFAULT NULL,
    `failure_count` int(11) DEFAULT '0',
    `last_notification_sent` datetime DEFAULT NULL,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_service` (`service_id`),
    KEY `idx_last_check` (`last_check`),
    KEY `idx_status` (`last_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Domains table for tracking all domains per account
CREATE TABLE IF NOT EXISTS `mod_monitored_domains` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `service_id` int(11) NOT NULL,
    `domain` varchar(255) NOT NULL,
    `domain_type` enum('primary','addon','subdomain','parked') DEFAULT 'addon',
    `doc_root` varchar(255) NOT NULL,
    `server_host` varchar(255) NOT NULL,
    `cpanel_user` varchar(100) NOT NULL,
    `last_check` datetime DEFAULT NULL,
    `last_status` varchar(50) DEFAULT NULL,
    `failure_count` int(11) DEFAULT '0',
    `last_notification_sent` datetime DEFAULT NULL,
    `is_active` tinyint(1) DEFAULT '1',
    `discovered_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_service_domain` (`service_id`, `domain`),
    KEY `idx_last_check` (`last_check`),
    KEY `idx_status` (`last_status`),
    KEY `idx_service` (`service_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Monitoring lock table to prevent duplicate checks
CREATE TABLE IF NOT EXISTS `wp_monitoring_lock` (
    `domain_id` int(11) NOT NULL,
    `lock_time` datetime NOT NULL,
    `server_host` varchar(255) DEFAULT NULL,
    PRIMARY KEY (`domain_id`),
    KEY `idx_lock_time` (`lock_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Reports table for tracking sent reports
CREATE TABLE IF NOT EXISTS `mod_monitor_reports` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `report_type` varchar(50) NOT NULL,
    `report_data` longtext NOT NULL,
    `sent_at` datetime DEFAULT NULL,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_sent` (`sent_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Alert history table
CREATE TABLE IF NOT EXISTS `mod_monitor_alerts` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `domain_id` int(11) NOT NULL,
    `alert_type` varchar(50) NOT NULL,
    `alert_message` text,
    `sent_to_client` tinyint(1) DEFAULT '0',
    `sent_to_support` tinyint(1) DEFAULT '1',
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_domain` (`domain_id`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Performance stats table
CREATE TABLE IF NOT EXISTS `mod_monitor_stats` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `stat_date` date NOT NULL,
    `total_checks` int(11) DEFAULT '0',
    `total_errors` int(11) DEFAULT '0',
    `avg_response_time` decimal(10,2) DEFAULT NULL,
    `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_date` (`stat_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;