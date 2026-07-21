local migrations = {
    {
        version = 1,
        statements = {
            [[
                CREATE TABLE IF NOT EXISTS `ps_fuel_stations` (
                    `id` INT NOT NULL,
                    `name` VARCHAR(100) NOT NULL,
                    `owner_citizenid` VARCHAR(64) DEFAULT NULL,
                    `balance` DECIMAL(12, 2) NOT NULL DEFAULT 0,
                    `stock` DECIMAL(12, 2) NOT NULL DEFAULT 0,
                    `capacity` DECIMAL(12, 2) NOT NULL DEFAULT 10000,
                    `price_multiplier` DECIMAL(6, 3) NOT NULL DEFAULT 1,
                    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                        ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (`id`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
            ]],
        },
    },

    {
        version = 2,
        statements = {
            [[
                CREATE TABLE IF NOT EXISTS `ps_fuel_transactions` (
                    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    `station_id` INT DEFAULT NULL,
                    `citizenid` VARCHAR(64) DEFAULT NULL,
                    `transaction_type` VARCHAR(32) NOT NULL,
                    `fuel_type` VARCHAR(32) DEFAULT NULL,
                    `amount` DECIMAL(12, 2) NOT NULL DEFAULT 0,
                    `price` DECIMAL(12, 2) NOT NULL DEFAULT 0,
                    `metadata` LONGTEXT DEFAULT NULL,
                    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (`id`),
                    INDEX `idx_station_id` (`station_id`),
                    INDEX `idx_citizenid` (`citizenid`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
            ]],
        },
    },

    {
        version = 3,
        statements = {
            [[
                CREATE TABLE IF NOT EXISTS `ps_fuel_vehicle_profiles` (
                    `model_hash` BIGINT NOT NULL,
                    `model_name` VARCHAR(100) DEFAULT NULL,
                    `fuel_type` VARCHAR(32) NOT NULL DEFAULT 'automatic',
                    `fast_charge_enabled` TINYINT(1) NOT NULL DEFAULT 1,
                    `updated_by` VARCHAR(64) DEFAULT NULL,
                    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                        ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (`model_hash`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
            ]],
        },
    },
}

local function runMigrations()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ps_fuel_migrations` (
            `version` INT NOT NULL,
            `installed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`version`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    local installedRows = MySQL.query.await(
        'SELECT `version` FROM `ps_fuel_migrations`'
    ) or {}

    local installed = {}

    for index = 1, #installedRows do
        installed[tonumber(installedRows[index].version)] = true
    end

    for index = 1, #migrations do
        local migration = migrations[index]

        if not installed[migration.version] then
            print(('[ps-fuel] Installing database migration %s...')
                :format(migration.version))

            local success, migrationError = pcall(function()
                for statementIndex = 1, #migration.statements do
                    MySQL.query.await(migration.statements[statementIndex])
                end

                MySQL.insert.await(
                    'INSERT INTO `ps_fuel_migrations` (`version`) VALUES (?)',
                    { migration.version }
                )
            end)

            if not success then
                error(('[ps-fuel] Migration %s failed: %s')
                    :format(migration.version, migrationError))
            end

            print(('[ps-fuel] Database migration %s installed.')
                :format(migration.version))
        end
    end

    print('[ps-fuel] Database is ready.')
end

MySQL.ready(function()
    local success, databaseError = pcall(runMigrations)

    if not success then
        print(('^1[ps-fuel] Database setup failed: %s^7')
            :format(databaseError))

        return
    end

    GlobalState['ps-fuel:databaseReady'] = true
end)
