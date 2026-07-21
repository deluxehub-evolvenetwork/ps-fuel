PSFuelDatabase = PSFuelDatabase or {}
PSFuelDatabase.Ready = false

local function ensureColumn(tableName, columnName, definition)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })

    if tonumber(count) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    end
end

local function ensureIndex(tableName, indexName, columns)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
    ]], { tableName, indexName })

    if tonumber(count) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD INDEX `%s` (%s)'):format(tableName, indexName, columns))
    end
end

function PSFuelDatabase.Audit(action, source, citizenid, details)
    if PSFuelDatabase.Ready ~= true or (PSFuelConfig.Logging or {}).DatabaseAudit ~= true then return end
    local encoded = type(details) == 'string' and details or json.encode(details or {})
    MySQL.insert([[INSERT INTO ps_fuel_audit_logs (action, source, citizenid, details)
        VALUES (?, ?, ?, ?)]], {
        tostring(action or 'unknown'):sub(1, 64),
        tonumber(source) or 0,
        citizenid and tostring(citizenid):sub(1, 64) or nil,
        encoded,
    })
end

function PSFuelDatabase.Ensure()
    local ok, err = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_vehicles` (
            `plate` varchar(16) NOT NULL,
            `fuel` decimal(6,2) NOT NULL DEFAULT 100.00,
            `leak_level` tinyint unsigned NOT NULL DEFAULT 0,
            `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_stations` (
            `station_id` varchar(64) NOT NULL,
            `label` varchar(100) NOT NULL,
            `owner_citizenid` varchar(64) DEFAULT NULL,
            `owner_name` varchar(100) DEFAULT NULL,
            `balance` bigint NOT NULL DEFAULT 0,
            `price_multiplier` decimal(4,2) NOT NULL DEFAULT 1.00,
            `total_sales` bigint NOT NULL DEFAULT 0,
            `total_litres` decimal(12,2) NOT NULL DEFAULT 0.00,
            `stock` decimal(12,2) NOT NULL DEFAULT 10000.00,
            `capacity` decimal(12,2) NOT NULL DEFAULT 10000.00,
            PRIMARY KEY (`station_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_transactions` (
            `id` bigint unsigned NOT NULL AUTO_INCREMENT,
            `station_id` varchar(64) NOT NULL,
            `citizenid` varchar(64) DEFAULT NULL,
            `player_name` varchar(100) DEFAULT NULL,
            `amount_paid` int NOT NULL DEFAULT 0,
            `fuel_amount` decimal(8,2) NOT NULL DEFAULT 0.00,
            `transaction_type` varchar(32) NOT NULL DEFAULT 'fuel',
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`),
            KEY `idx_station_created` (`station_id`,`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_settings` (
            `setting_key` varchar(64) NOT NULL,
            `setting_value` varchar(255) NOT NULL,
            PRIMARY KEY (`setting_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])


        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_audit_logs` (
            `id` bigint unsigned NOT NULL AUTO_INCREMENT,
            `action` varchar(64) NOT NULL,
            `source` int NOT NULL DEFAULT 0,
            `citizenid` varchar(64) DEFAULT NULL,
            `details` longtext DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`),
            KEY `idx_ps_fuel_audit_action_created` (`action`,`created_at`),
            KEY `idx_ps_fuel_audit_citizen` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_vehicle_profiles` (
            `model_hash` bigint NOT NULL,
            `model_name` varchar(80) NOT NULL,
            `fuel_type` varchar(16) NOT NULL DEFAULT 'petrol',
            `fast_charge_enabled` tinyint(1) NOT NULL DEFAULT 0,
            `updated_by` varchar(64) DEFAULT NULL,
            `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`model_hash`),
            KEY `idx_ps_fuel_vehicle_type` (`fuel_type`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        ensureColumn('ps_fuel_vehicles', 'leak_level', 'tinyint unsigned NOT NULL DEFAULT 0')
        ensureColumn('ps_fuel_stations', 'stock', 'decimal(12,2) NOT NULL DEFAULT 10000.00')
        ensureColumn('ps_fuel_stations', 'capacity', 'decimal(12,2) NOT NULL DEFAULT 10000.00')
        ensureIndex('ps_fuel_vehicles', 'idx_ps_fuel_vehicles_updated', '`updated_at`')
        ensureIndex('ps_fuel_stations', 'idx_ps_fuel_stations_owner', '`owner_citizenid`')
        ensureIndex('ps_fuel_transactions', 'idx_ps_fuel_transactions_citizen', '`citizenid`,`created_at`')

        MySQL.query.await([[
            INSERT INTO ps_fuel_settings (setting_key, setting_value)
            VALUES ('market_multiplier', '1.0')
            ON DUPLICATE KEY UPDATE setting_key = VALUES(setting_key)
        ]])
    end)

    if not ok then
        PSFuelDatabase.Ready = false
        print(('[ps-fuel] Database initialisation failed: %s'):format(err))
        return false
    end

    PSFuelDatabase.Ready = true
    print('[ps-fuel] Database ready. Standalone fuel system active.')
    return true
end
