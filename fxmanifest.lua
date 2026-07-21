fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ps-fuel'
author 'Techy / PLUUUX Solutions'
description 'Premium Qbox fuel economy with a luxury tablet management interface, deliveries, robberies, EV charging, leaks and dynamic pricing'
version '3.2.1'

ui_page 'web/dist/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

files {
    'web/dist/index.html',
    'web/dist/assets/*',
    'locales/*.json'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'Renewed-Banking'
}
