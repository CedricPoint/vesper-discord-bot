fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vesper-discord'
author 'VESPER RP'
description "Pont vers le bot Discord : etat du serveur, joueurs, metiers, connexions, annonce en jeu, fiche joueur (/id), historique des journaux (/logs), et journaux des scripts (salons et webhooks crees par le bot)."
version '1.5.0'

-- ⚠️ FICHIERS AJOUTÉS (journaux.lua ; fiche.lua et MySQL.lua en 1.2.0 ; historique.lua en 1.4.0 ; inventaire.lua en 1.5.0) :
-- `refresh` AVANT `restart`, sinon l'ancien manifeste reste en cache.
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'journaux.lua',
    'fiche.lua',
    'historique.lua',
    'inventaire.lua',
}

dependency 'oxmysql'
