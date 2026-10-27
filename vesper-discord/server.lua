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
---   POST /annonce         {"message": "...", "auteur": "..."} → tchat en jeu
---   POST /webhooks        {"id": "ressource", "webhooks": {sujet: url}} → journaux
---                         (voir journaux.lua : les scripts déclarent leurs salons)

local JETON = GetConvar('vesper_discord_jeton', '')

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

local function noter(evt)
    numero = numero + 1
    evt.n = numero
    evt.t = os.time()
    evenements[#evenements + 1] = evt
    if #evenements > MAX_EVENEMENTS then table.remove(evenements, 1) end
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
        end
    end

    connus[id] = info
    return info
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

AddEventHandler('esx:playerLoaded', function(playerId)
    -- Le métier n'est connu qu'une fois le personnage chargé.
    infoJoueur(playerId)
end)

AddEventHandler('playerDropped', function(raison)
    local src = tonumber(source)
    local info = connus[src] or { id = src }
    info.nom = GetPlayerName(source) or info.nom
    if arrivees[src] then info.duree = os.time() - arrivees[src] end
    noter({ type = 'depart', joueur = info, raison = raison })
    connus[src] = nil
    arrivees[src] = nil
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
    }
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
