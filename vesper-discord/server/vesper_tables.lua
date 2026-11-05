-- ===========================================================================
--  Tables VESPER : migration automatique des anciens noms vers vesper_*.
--  (fichier ajouté par l'outil de renommage du hub ; ne pas modifier à la main)
--
--  Toutes les tables de la base VESPER portent un nom vesper_*. Un serveur
--  qui a encore des données sous l'ancien nom (Quasar, ancienne version d'un
--  script VESPER…) les retrouve automatiquement :
--    - au premier accès à la base de CETTE ressource, chaque ancienne table
--      est renommée vers son nouveau nom (RENAME TABLE : instantané, aucune
--      ligne copiée, rien de perdu) ;
--    - une VUE garde l'ancien nom, pour que les autres scripts qui le lisent
--      encore continuent de marcher (set vesper_tables_vues false pour ne
--      pas la créer).
--  Toutes les requêtes de la ressource attendent la fin de la migration :
--  aucune ne part sur une table pas encore renommée.
--  Si quelque chose échoue, on le dit dans la console et la ressource
--  démarre quand même : une migration ne doit jamais bloquer un serveur.
-- ===========================================================================

local RENOMMAGES = {
    ['bank_cards'] = 'vesper_bank_cards',
    ['houselocations'] = 'vesper_houselocations',
    ['inventory_glovebox'] = 'vesper_inventory_glovebox',
    ['inventory_stash'] = 'vesper_inventory_stash',
    ['inventory_trunk'] = 'vesper_inventory_trunk',
    ['player_houses'] = 'vesper_player_houses',
    ['qs_dealership_catalog'] = 'vesper_dealership_catalog',
    ['qs_motel_rentals'] = 'vesper_motel_rentals',
    ['qs_multicharacter_slots'] = 'vesper_multicharacter_slots',
}

local RES = GetCurrentResourceName()
local VUES = GetConvar('vesper_tables_vues', 'true') ~= 'false'
local oxmysql = exports.oxmysql
local fini = next(RENOMMAGES) == nil

local function requete(sql, params)
    local p = promise.new()
    oxmysql:query(sql, params or {}, function(r, err)
        if err then p:reject(err) else p:resolve(r) end
    end, RES, true)
    return Citizen.Await(p)
end

local function etatDesTables()
    local noms = {}
    for ancien, nouveau in pairs(RENOMMAGES) do noms[#noms + 1] = ancien; noms[#noms + 1] = nouveau end
    local marques = {}
    for i = 1, #noms do marques[i] = '?' end
    local lignes = requete(('SELECT table_name AS n, table_type AS t FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name IN (%s)'):format(table.concat(marques, ',')), noms) or {}
    local etat = {}
    for _, l in ipairs(lignes) do etat[l.n] = l.t end
    return etat
end

local function compter(t)
    local r = requete(('SELECT COUNT(*) AS n FROM `%s`'):format(t))
    return r and r[1] and tonumber(r[1].n) or 0
end

local function migrer()
    local etat = etatDesTables()
    for ancien, nouveau in pairs(RENOMMAGES) do
        local ok, err = pcall(function()
            local a, n = etat[ancien], etat[nouveau]
            if a == 'BASE TABLE' and n == 'BASE TABLE' and compter(nouveau) == 0 and compter(ancien) > 0 then
                -- Une version précédente a créé la nouvelle table vide : les vraies données sont dans l'ancienne.
                requete(('DROP TABLE `%s`'):format(nouveau))
                n = nil
            end
            if a == 'BASE TABLE' and not n then
                requete(('RENAME TABLE `%s` TO `%s`'):format(ancien, nouveau))
                print(('^2[%s]^7 table %s renommée en %s'):format(RES, ancien, nouveau))
                a, n = nil, 'BASE TABLE'
            end
            if VUES and not a and n == 'BASE TABLE' then
                requete(('CREATE OR REPLACE VIEW `%s` AS SELECT * FROM `%s`'):format(ancien, nouveau))
            elseif a == 'BASE TABLE' and n == 'BASE TABLE' then
                print(('^3[%s]^7 %s et %s existent toutes les deux avec des données : rien n\'est déplacé, vérifiez à la main.'):format(RES, ancien, nouveau))
            end
        end)
        if not ok then
            -- Une autre ressource qui partage la table l'a peut-être renommée au même moment.
            local apres = etatDesTables()
            if apres[nouveau] ~= 'BASE TABLE' then
                print(('^1[%s]^7 migration de %s impossible : %s'):format(RES, ancien, tostring(err)))
            end
        end
    end
end

Citizen.CreateThreadNow(function()
    if fini then return end
    while GetResourceState('oxmysql') ~= 'started' do Wait(50) end
    local ok, err = pcall(function()
        oxmysql:awaitConnection()
        migrer()
    end)
    if not ok then print(('^1[%s]^7 migration des tables : %s'):format(RES, tostring(err))) end
    fini = true
end)

-- Toute requête de la ressource attend la fin de la migration.
if MySQL and MySQL.query then
    local function attendre()
        while not fini do Wait(0) end
    end
    for _, m in ipairs({ 'scalar', 'single', 'query', 'insert', 'update', 'prepare', 'transaction', 'rawExecute' }) do
        local t = MySQL[m]
        if type(t) == 'table' and t.await then
            local original = t.await
            t.await = function(...)
                attendre()
                return original(...)
            end
        end
    end
    local mt = getmetatable(MySQL.query)
    if mt and mt.__call and not mt.__vesperTables then
        local original = mt.__call
        mt.__vesperTables = true
        mt.__call = function(self, query, parameters, cb)
            if fini then return original(self, query, parameters, cb) end
            Citizen.CreateThreadNow(function()
                attendre()
                original(self, query, parameters, cb)
            end)
        end
    end
end
