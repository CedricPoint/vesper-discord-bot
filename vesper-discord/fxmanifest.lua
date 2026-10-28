fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vesper-discord'
author 'VESPER RP'
description "Pont vers le bot Discord : etat du serveur, joueurs, metiers, connexions, annonce en jeu, fiche joueur (/id), et journaux des scripts (salons et webhooks crees par le bot)."
version '1.3.0'

-- ⚠️ FICHIERS AJOUTÉS (journaux.lua, puis fiche.lua et MySQL.lua en 1.2.0) :
-- `refresh` AVANT `restart`, sinon l'ancien manifeste reste en cache.
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'journaux.lua',
    'fiche.lua',
}

dependency 'oxmysql'
