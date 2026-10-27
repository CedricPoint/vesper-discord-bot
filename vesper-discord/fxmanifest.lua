fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vesper-discord'
author 'VESPER RP'
description "Pont vers le bot Discord : etat du serveur, joueurs, metiers, connexions, annonce en jeu, et journaux des scripts (salons et webhooks crees par le bot)."
version '1.1.0'

-- ⚠️ FICHIER AJOUTÉ (journaux.lua) : `refresh` AVANT `restart`.
server_scripts {
    'server.lua',
    'journaux.lua',
}
