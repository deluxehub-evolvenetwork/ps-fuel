fx_version 'cerulean'
game 'gta5'

name 'ps-fuel'
author 'PS Development / Techy / PLUUUX Solutions'
description 'Standalone physical fuel and EV charging system with runtime vehicle profiles, fast charging, stations and ownership'
version '3.2.0'


ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/nozzle.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/security.lua',
    'server/inventory.lua',
    'server/database.lua',
    'server/main.lua'
}

files {
    'web/index.html',
    'web/assets/*',
    'web/sounds/fuel/*',
    'locales/*.json',
    'stream/*.ydr',
    'stream/*.ytyp'
}

data_file 'DLC_ITYP_REQUEST' 'stream/electric_charger_typ.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/electric_nozzle_typ.ytyp'

provide 'cdn-fuel'
provide 'LegacyFuel'

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_target',
    '/onesync'
}
