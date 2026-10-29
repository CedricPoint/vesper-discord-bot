--- Pont vers le bot Discord de VESPER RP.
---
--- POURQUOI UNE RESSOURCE ET PAS SEULEMENT /players.json : sur cet
--- artefact, /players.json rend chaque joueur sous le nom « Player », avec
--- l'id 0 et sans identifiant. Le bot ne pourrait ni nommer les joueurs, ni
--- compter la police ou les secours, ni relier un joueur à son compte
--- Discord. Ici on lit tout ça côté serveur et on le rend en JSON.
---
--- ⚠️ ACCÈS : uniquement depuis la machine elle-même (127.0.0.1) ET avec
--- le jeton `vesper_discord_jeton` (déclaré avec `set`, jamais `sets` : un
--- `sets` est publié dans la liste des serveurs). Sans jeton déclaré, tout
--- est refusé.
---
--- Points d'entrée (sous http://127.0.0.1:30120/vesper-discord/) :
---   GET  /etat?depuis=N   état complet + événements numérotés après N
---   GET  /fiche?q=…       fiche complète d'un joueur (fiche.lua, commande /id)
---   GET  /recherche?q=…   joueurs correspondants (autocomplétion de /id)
---   GET  /historique?…    journaux rangés en base (historique.lua, commande /logs)
---   GET  /historique/resume?…  nombre de journaux par script et sujet
---   POST /annonce         {"message": "...", "auteur": "..."} → tchat en jeu
---   POST /maj             {"version": "...", "fichiers": {nom: contenu}} → se met à jour
---   POST /webhooks        {"id": "ressource", "webhooks": {sujet: url}} → journaux
---                         (voir journaux.lua : les scripts déclarent leurs salons)

local JETON = GetConvar('vesper_discord_jeton', '')

-- ⚠️ La version du code QUI TOURNE, lue une fois au chargement. Relue plus
-- tard, GetResourceMetadata donne celle du manifeste sur le disque, qu'un
-- simple `refresh` met à jour sans recharger le code : le bot a cru le
-- 29/10 qu'une mise à jour était chargée alors que l'ancien code tournait.
local VERSION_CHARGEE = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)

local ESX = nil
CreateThread(function()
    local ok, obj = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)
    if ok then ESX = obj end
end)

-- Dernières infos connues par joueur : à `playerDropped`, ESX a parfois
-- déjà retiré le joueur, et on veut quand même dire quel métier il avait.
local connus = {}
local arrivees = {}

-- Anneau d'événements : le bot repart du dernier numéro qu'il a vu, on
-- ne perd donc rien entre deux interrogations.
local evenements = {}
local numero = 0
local MAX_EVENEMENTS = 200

-- Ce que l'historique (/logs) garde d'un événement du salon logs-joueurs.
local TITRES = { arrivee = 'Connexion', personnage = 'Personnage chargé', metier = 'Changement de métier',
    mort = 'Mort', depart = 'Déconnexion' }

local function historiser(evt)
    if not VesperHistoriqueEnregistrer then return end
    local j = evt.joueur or {}
    local lignes = { ('%s (`#%s`)'):format(tostring(j.nom or '?'), tostring(j.id or '?')) }
    if j.personnage then lignes[#lignes + 1] = 'Personnage : ' .. j.personnage end
    if j.metier_label then lignes[#lignes + 1] = ('Métier : %s (%s)'):format(j.metier_label, tostring(j.grade or '?')) end
    if evt.type == 'personnage' and evt.nouveau then lignes[#lignes + 1] = 'Nouveau personnage' end
    if evt.type == 'metier' then lignes[#lignes + 1] = ('%s → %s'):format(tostring(evt.avant or '?'), tostring(evt.apres)) end
    if evt.tueur then lignes[#lignes + 1] = ('Tué par %s (`#%s`)'):format(tostring(evt.tueur.nom), tostring(evt.tueur.id)) end
    if evt.cause then lignes[#lignes + 1] = 'Cause : ' .. evt.cause end
    if evt.raison then lignes[#lignes + 1] = 'Raison : ' .. tostring(evt.raison) end
    if j.duree then lignes[#lignes + 1] = ('Session : %d min'):format(math.floor(j.duree / 60)) end
    if j.liquide or j.banque then
        lignes[#lignes + 1] = ('Argent : %s liquide, %s banque'):format(tostring(j.liquide or '?'), tostring(j.banque or '?'))
    end
    VesperHistoriqueEnregistrer('vesper-discord', 'joueurs',
        { title = TITRES[evt.type] or evt.type, description = table.concat(lignes, '\n') },
        { j.licence, evt.tueur and evt.tueur.licence })
end

local function noter(evt)
    numero = numero + 1
    evt.n = numero
    evt.t = os.time()
    evenements[#evenements + 1] = evt
    if #evenements > MAX_EVENEMENTS then table.remove(evenements, 1) end
    pcall(historiser, evt)
end

local function infoJoueur(src)
    local id = tonumber(src)
    local info = {
        id = id,
        nom = GetPlayerName(src) or ('Joueur ' .. tostring(src)),
        ping = GetPlayerPing(src),
    }

    for _, ident in ipairs(GetPlayerIdentifiers(src) or {}) do
        if ident:sub(1, 8) == 'discord:' then info.discord = ident:sub(9) end
        if ident:sub(1, 8) == 'license:' then info.licence = ident end
    end

    if arrivees[id] then info.connecte_depuis = arrivees[id] end

    if ESX then
        local ok, xp = pcall(ESX.GetPlayerFromId, id)
        if ok and xp then
            local job = xp.job
            if job then
                info.metier = job.name
                info.metier_label = job.label
                info.grade = job.grade_label
                info.en_service = job.onDuty
            end
            local okNom, nomRp = pcall(xp.getName)
            if okNom and type(nomRp) == 'string' and nomRp ~= '' then
                info.personnage = nomRp
            end
            -- Pour le journal des départs : avec quoi le joueur est parti.
            local okL, liquide = pcall(xp.getAccount, 'money')
            local okB, banque = pcall(xp.getAccount, 'bank')
            if okL and type(liquide) == 'table' then info.liquide = tonumber(liquide.money) end
            if okB and type(banque) == 'table' then info.banque = tonumber(banque.money) end
        end
    end

    connus[id] = info
    return info
end

-- Noms lisibles des causes de mort les plus courantes (GetPedCauseOfDeath
-- rend un hachage d'arme). Le reste s'affiche « autre cause ».
local CAUSES = {}
for nom, libelle in pairs({
    WEAPON_UNARMED = 'à mains nues', WEAPON_KNIFE = 'couteau', WEAPON_BAT = 'batte',
    WEAPON_PISTOL = 'pistolet', WEAPON_COMBATPISTOL = 'pistolet de combat', WEAPON_STUNGUN = 'taser',
    WEAPON_SMG = 'SMG', WEAPON_MICROSMG = 'micro-SMG', WEAPON_ASSAULTRIFLE = 'fusil d’assaut',
    WEAPON_CARBINERIFLE = 'carabine', WEAPON_PUMPSHOTGUN = 'fusil à pompe', WEAPON_SNIPERRIFLE = 'fusil de précision',
    WEAPON_RUN_OVER_BY_CAR = 'renversé par un véhicule', WEAPON_RAMMED_BY_CAR = 'percuté par un véhicule',
    WEAPON_FALL = 'chute', WEAPON_DROWNING = 'noyade', WEAPON_DROWNING_IN_VEHICLE = 'noyade (véhicule)',
    WEAPON_EXPLOSION = 'explosion', WEAPON_FIRE = 'feu', WEAPON_BLEEDING = 'hémorragie',
    WEAPON_ANIMAL = 'animal', WEAPON_COUGAR = 'puma', WEAPON_BARBED_WIRE = 'barbelés',
    WEAPON_ELECTRIC_FENCE = 'clôture électrique', WEAPON_EXHAUSTION = 'épuisement',
}) do
    local h = GetHashKey(nom)
    CAUSES[h] = libelle
    CAUSES[h < 0 and h + 4294967296 or h - 4294967296] = libelle
end

local function ressourcesLancees()
    local liste = {}
    for i = 0, GetNumResources() - 1 do
        local nom = GetResourceByFindIndex(i)
        if nom and GetResourceState(nom) == 'started' then
            liste[#liste + 1] = nom
        end
    end
    table.sort(liste)
    return liste
end

AddEventHandler('playerJoining', function()
    local src = source
    arrivees[tonumber(src)] = os.time()
    local info = infoJoueur(src)
    noter({ type = 'arrivee', joueur = info })
end)

AddEventHandler('esx:playerLoaded', function(playerId, _, nouveau)
    -- Le métier n'est connu qu'une fois le personnage chargé.
    noter({ type = 'personnage', joueur = infoJoueur(playerId), nouveau = nouveau == true })
end)

AddEventHandler('esx:setJob', function(src, job, ancien)
    -- Une prise ou fin de service rappelle setJob avec le même métier et le
    -- même grade : les scripts de métier la journalisent déjà, on l'ignore.
    if type(job) ~= 'table' then return end
    if type(ancien) == 'table' and ancien.name == job.name and ancien.grade == job.grade then return end
    noter({
        type = 'metier', joueur = infoJoueur(src),
        avant = type(ancien) == 'table' and ((ancien.label or ancien.name) .. ' — ' .. (ancien.grade_label or '?')) or nil,
        apres = (job.label or job.name) .. ' — ' .. (job.grade_label or '?'),
    })
end)

-- ⚠️ Envoyé par le CLIENT (es_extended/client/modules/death.lua) : on le
-- journalise sans s'y fier pour autre chose, et un client qui le répète en
-- boucle n'inonde pas le salon.
local derniereMort = {}
RegisterNetEvent('esx:onPlayerDeath')
AddEventHandler('esx:onPlayerDeath', function(data)
    local src = tonumber(source)
    if not src or (derniereMort[src] and os.time() - derniereMort[src] < 10) then return end
    derniereMort[src] = os.time()
    data = type(data) == 'table' and data or {}
    local evt = { type = 'mort', joueur = infoJoueur(src) }
    local tueur = data.killedByPlayer and tonumber(data.killerServerId)
    if tueur and tueur ~= src and GetPlayerName(tueur) then evt.tueur = infoJoueur(tueur) end
    evt.cause = CAUSES[tonumber(data.deathCause) or 0] or (data.deathCause and 'autre cause' or nil)
    noter(evt)
end)

AddEventHandler('playerDropped', function(raison)
    local src = tonumber(source)
    local info = connus[src] or { id = src }
    info.nom = GetPlayerName(source) or info.nom
    if arrivees[src] then info.duree = os.time() - arrivees[src] end
    noter({ type = 'depart', joueur = info, raison = raison })
    connus[src] = nil
    arrivees[src] = nil
    derniereMort[src] = nil
end)

local function etat(depuis)
    local joueurs = {}
    for _, src in ipairs(GetPlayers()) do
        joueurs[#joueurs + 1] = infoJoueur(src)
    end

    local nouveaux = {}
    for _, evt in ipairs(evenements) do
        if evt.n > depuis then nouveaux[#nouveaux + 1] = evt end
    end

    return {
        nom = GetConvar('sv_projectName', 'VESPER RP'),
        max = GetConvarInt('sv_maxclients', 48),
        -- Côté serveur, GetGameTimer compte depuis le lancement de FXServer.
        en_ligne_depuis = math.floor(GetGameTimer() / 1000),
        ressources = ressourcesLancees(),
        joueurs = joueurs,
        evenements = nouveaux,
        dernier = numero,
        -- Les scripts qui ont déclaré des journaux (journaux.lua).
        modules = VesperJournauxEtat and VesperJournauxEtat() or {},
        -- Le bot compare cette version à la dernière publiée (mises à jour).
        version = VERSION_CHARGEE,
        -- Lignes server.cfg qui manquent pour se mettre à jour seule (vide = prête).
        droits_manquants = VesperDroitsMiseAJour and VesperDroitsMiseAJour() or {},
    }
end

-- ── Mise à jour de la ressource par le bot ───────────────────────────────
--
-- Le bot n'a pas le droit d'écrire dans le dossier des ressources (autre
-- utilisateur système) : il nous ENVOIE les nouveaux fichiers, et c'est la
-- ressource qui les écrit avec SaveResourceFile, puis se recharge.
--
-- ⚠️ Rien n'est écrit tant que TOUS les fichiers Lua ne compilent pas : une
-- mise à jour à moitié posée laisserait la ressource hors service.
-- ⚠️ `refresh` AVANT `restart` : un fichier ajouté au manifeste n'est pas
-- chargé sans lui, et rien ne le signale.

local FICHIER_PERMIS = '^[%w_%-]+%.lua$'

-- ⚠️ Une ressource n'a pas le droit de lancer `refresh` ni `restart` sans
-- ACE dans server.cfg (« Access denied for command refresh »). Et `restart`
-- relance lui-même `stop` puis `start` sous le même principal : il faut les
-- quatre (le 29/10, refresh et restart seuls → « Access denied for command
-- stop » et l'ancien code continuait de tourner). Sans eux, les fichiers
-- seraient écrits mais jamais chargés : on refuse AVANT d'écrire.
local function droitsManquants()
    local principal = 'resource.' .. GetCurrentResourceName()
    local manque = {}
    for _, commande in ipairs({ 'refresh', 'restart', 'stop', 'start' }) do
        if not IsPrincipalAceAllowed(principal, 'command.' .. commande) then
            manque[#manque + 1] = ('add_ace %s command.%s allow'):format(principal, commande)
        end
    end
    return manque
end
VesperDroitsMiseAJour = droitsManquants

function installerMiseAJour(donnees)
    local manque = droitsManquants()
    if #manque > 0 then
        return false, ('la ressource n’a pas le droit de se recharger. Ajoutez dans server.cfg puis redémarrez le serveur : %s')
            :format(table.concat(manque, ' / '))
    end
    local fichiers = donnees.fichiers
    if type(fichiers) ~= 'table' or next(fichiers) == nil then return false, 'aucun fichier' end
    if not fichiers['fxmanifest.lua'] then return false, 'fxmanifest.lua manquant' end

    for nom, contenu in pairs(fichiers) do
        if type(nom) ~= 'string' or not nom:match(FICHIER_PERMIS) then
            return false, ('nom de fichier refusé : %s'):format(tostring(nom))
        end
        if type(contenu) ~= 'string' or contenu == '' then
            return false, ('fichier vide : %s'):format(nom)
        end
        local fonction, erreur = load(contenu, '=' .. nom, 't', {})
        if not fonction then return false, ('%s ne compile pas : %s'):format(nom, tostring(erreur)) end
    end

    local ressource = GetCurrentResourceName()
    local avant = GetResourceMetadata(ressource, 'version', 0) or 'inconnue'
    local ecrits = {}
    for nom, contenu in pairs(fichiers) do
        -- La version précédente reste à côté, sous un nom que le manifeste
        -- ne charge jamais, pour un retour arrière à la main.
        local ancien = LoadResourceFile(ressource, nom)
        if ancien then SaveResourceFile(ressource, nom .. '.avant-maj-' .. avant, ancien, -1) end
        if not SaveResourceFile(ressource, nom, contenu, -1) then
            return false, ('écriture impossible : %s'):format(nom)
        end
        ecrits[#ecrits + 1] = nom
    end

    print(('[vesper-discord] mise à jour %s → %s (%d fichiers), rechargement…'):format(
        avant, tostring(donnees.version or '?'), #ecrits))
    -- Laisser partir la réponse HTTP avant de nous arrêter.
    SetTimeout(1000, function()
        ExecuteCommand('refresh')
        SetTimeout(1000, function() ExecuteCommand('restart ' .. ressource) end)
    end)
    return true, ecrits
end

local function parametre(chemin, nom)
    local v = chemin:match('[?&]' .. nom .. '=([^&]*)')
    if not v then return '' end
    v = v:gsub('+', ' ')
    return (v:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

local function entete(req, nom)
    for cle, valeur in pairs(req.headers or {}) do
        if cle:lower() == nom then return valeur end
    end
    return nil
end

SetHttpHandler(function(req, res)
    local function repondre(code, corps)
        res.writeHead(code, { ['Content-Type'] = 'application/json; charset=utf-8' })
        res.send(json.encode(corps))
    end

    local adresse = tostring(req.address or '')
    if JETON == '' or entete(req, 'x-vesper-jeton') ~= JETON
        or not (adresse:find('^127%.0%.0%.1') or adresse:find('^%[?::1')) then
        return repondre(403, { erreur = 'refuse' })
    end

    local chemin = (req.path or '/'):gsub('%?.*$', '')

    if req.method == 'GET' and chemin == '/etat' then
        local depuis = tonumber((req.path or ''):match('depuis=(%d+)')) or 0
        local ok, corps = pcall(etat, depuis)
        if not ok then return repondre(500, { erreur = tostring(corps) }) end
        return repondre(200, corps)
    end

    -- Fiche joueur (/id) et autocomplétion : requêtes SQL, donc dans un
    -- fil à part (MySQL.query.await exige une coroutine).
    if req.method == 'GET' and (chemin == '/fiche' or chemin == '/recherche') then
        local q = parametre(req.path or '', 'q')
        CreateThread(function()
            local ok, corps, raison
            if chemin == '/fiche' then
                ok, corps, raison = pcall(VesperFiche, q)
            else
                ok, corps = pcall(VesperRecherche, q, 25)
                corps = { resultats = corps }
            end
            if not ok then return repondre(500, { erreur = tostring(corps) }) end
            if corps == nil then return repondre(404, { erreur = raison or 'introuvable' }) end
            repondre(200, corps)
        end)
        return
    end

    -- Inventaires (/inventaire) : coffres et objets, SQL aussi.
    if req.method == 'GET' and chemin:find('^/inventaire/') then
        local q = parametre(req.path or '', 'q')
        local fonctions = {
            ['/inventaire/coffre'] = VesperInventaireCoffre,
            ['/inventaire/objet'] = VesperInventaireObjet,
            ['/inventaire/recherche-coffre'] = function(t) return { resultats = VesperInventaireRecherche(t, 25) } end,
            ['/inventaire/recherche-objet'] = function(t) return { resultats = VesperInventaireObjets(t, 25) } end,
        }
        local f = fonctions[chemin]
        if not f then return repondre(404, { erreur = 'inconnu' }) end
        CreateThread(function()
            local ok, corps, raison = pcall(f, q)
            if not ok then return repondre(500, { erreur = tostring(corps) }) end
            if corps == nil then return repondre(404, { erreur = raison or 'introuvable' }) end
            repondre(200, corps)
        end)
        return
    end

    -- Historique des journaux (/logs) : SQL aussi, donc dans un fil à part.
    if req.method == 'GET' and (chemin == '/historique' or chemin == '/historique/resume') then
        local p = {}
        for _, cle in ipairs({ 'licence', 'ressource', 'sujet', 'texte', 'depuis', 'limite', 'decalage', 'complet' }) do
            local v = parametre(req.path or '', cle)
            if v ~= '' then p[cle] = v end
        end
        CreateThread(function()
            local f = chemin == '/historique' and VesperHistoriqueChercher or VesperHistoriqueResume
            local ok, corps, raison = pcall(f, p)
            if not ok then return repondre(500, { erreur = tostring(corps) }) end
            if corps == nil then return repondre(503, { erreur = raison or 'indisponible' }) end
            repondre(200, corps)
        end)
        return
    end

    if req.method == 'POST' and chemin == '/annonce' then
        req.setDataHandler(function(brut)
            local ok, donnees = pcall(json.decode, brut)
            local message = ok and type(donnees) == 'table' and donnees.message
            if type(message) ~= 'string' or message == '' then
                return repondre(400, { erreur = 'message vide' })
            end
            message = message:sub(1, 400)
            TriggerClientEvent('chat:addMessage', -1, {
                color = { 168, 85, 247 },
                multiline = true,
                args = { '📢 VESPER — Annonce', message },
            })
            print(('[vesper-discord] annonce de %s : %s'):format(
                tostring(donnees.auteur or 'Discord'), message))
            repondre(200, { ok = true })
        end)
        return
    end

    if req.method == 'POST' and chemin == '/maj' then
        req.setDataHandler(function(brut)
            local ok, donnees = pcall(json.decode, brut)
            if not ok or type(donnees) ~= 'table' then return repondre(400, { erreur = 'json' }) end
            local reussi, info = installerMiseAJour(donnees)
            if not reussi then return repondre(400, { erreur = info }) end
            repondre(200, { ok = true, fichiers = info })
        end)
        return
    end

    if req.method == 'POST' and chemin == '/webhooks' then
        req.setDataHandler(function(brut)
            local ok, donnees = pcall(json.decode, brut)
            if not ok then return repondre(400, { erreur = 'json' }) end
            local reussi, info = VesperJournauxRecevoir(donnees)
            if not reussi then return repondre(400, { erreur = info }) end
            repondre(200, { ok = true, recus = info })
        end)
        return
    end

    repondre(404, { erreur = 'inconnu' })
end)
