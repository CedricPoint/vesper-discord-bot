--- Inventaires pour la commande /inventaire du bot Discord.
---
--- · /inventaire coffre : le contenu d'un coffre (stash), d'un coffre de
---   véhicule ou d'une boîte à gants, et le propriétaire du véhicule ;
--- · /inventaire objet : qui détient un objet, et combien (joueurs connectés
---   EN DIRECT, personnages hors ligne, coffres, véhicules). L'outil pour
---   repérer une duplication.
---
--- Les tables sont celles de qs-inventory (et de ses remplaçants, qui
--- gardent les mêmes) : users.inventory, inventory_stash (stash, items),
--- inventory_trunk et inventory_glovebox (plate, items). Chacune est
--- facultative : une table absente est simplement sautée.
---
--- ⚠️ Un coffre se lit EN BASE : l'inventaire l'y écrit une seconde après
--- chaque changement. Les poches d'un joueur connecté se lisent en direct.

local INVENTAIRE = 'qs-inventory'   -- nom des exports (provide pour les remplaçants)

local function requete(sql, params)
    local ok, lignes = pcall(MySQL.query.await, sql, params or {})
    if not ok then
        print(('[vesper-discord] inventaire : requête refusée (%s)'):format(tostring(lignes)))
        return {}
    end
    return lignes or {}
end

local tables = nil
local function aLaTable(nom)
    if not tables then
        tables = {}
        for _, l in ipairs(requete('SELECT table_name AS t FROM information_schema.tables WHERE table_schema = DATABASE()')) do
            tables[l.t] = true
        end
    end
    return tables[nom] == true
end

local function decoderJson(texte)
    if type(texte) ~= 'string' or texte == '' then return nil end
    local ok, v = pcall(json.decode, texte)
    return ok and v or nil
end

-- ── Objets connus : nom → libellé ────────────────────────────────────────

local objets, objetsQuand = nil, 0
local function listeObjets()
    if objets and os.time() - objetsQuand < 600 then return objets end
    objets, objetsQuand = {}, os.time()
    local ok, liste = pcall(function() return exports[INVENTAIRE]:GetItemList() end)
    if ok and type(liste) == 'table' then
        for nom, d in pairs(liste) do
            if type(d) == 'table' then objets[tostring(d.name or nom)] = tostring(d.label or nom) end
        end
    end
    if not next(objets) and aLaTable('items') then
        for _, l in ipairs(requete('SELECT name, label FROM items')) do objets[l.name] = l.label end
    end
    return objets
end

local function libelle(nom) return listeObjets()[nom] or nom end

--- { { objet, label, quantite } } trié par libellé.
local function contenu(brut)
    local cumul, ordre = {}, {}
    for _, o in pairs(brut or {}) do
        if type(o) == 'table' and o.name then
            local n = tonumber(o.amount or o.count) or 1
            if not cumul[o.name] then
                cumul[o.name] = { objet = o.name, label = o.label or libelle(o.name), quantite = 0 }
                ordre[#ordre + 1] = o.name
            end
            cumul[o.name].quantite = cumul[o.name].quantite + n
        end
    end
    local t = {}
    for _, nom in ipairs(ordre) do t[#t + 1] = cumul[nom] end
    table.sort(t, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
    return t
end

local function nomDe(identifier)
    if not identifier or not aLaTable('users') then return nil end
    local u = requete('SELECT firstname, lastname FROM users WHERE identifier = ? LIMIT 1', { identifier })[1]
    if not u then return nil end
    local n = (('%s %s'):format(u.firstname or '', u.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n or nil
end

local function plaque(p) return (tostring(p or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')) end

-- Un texte cherché par LIKE : % et _ y sont des jokers, on les échappe
-- (\ est le caractère d'échappement par défaut de MySQL). Les retirer
-- cassait la recherche de « water_bottle » ou de « gang_ballas ».
local function pourLike(t) return (tostring(t or ''):gsub('[\\%%_]', '\\%0')) end

local GENRES = {
    stash = { table = 'inventory_stash', col = 'stash', emoji = '🗄️', nom = 'Coffre' },
    trunk = { table = 'inventory_trunk', col = 'plate', emoji = '🚗', nom = 'Coffre de véhicule' },
    glovebox = { table = 'inventory_glovebox', col = 'plate', emoji = '🧤', nom = 'Boîte à gants' },
}

-- ── /inventaire coffre ───────────────────────────────────────────────────

--- Autocomplétion : { label, valeur = 'trunk:AB123CD' | 'stash:nom' }.
function VesperInventaireRecherche(texte, max)
    max = max or 25
    texte = tostring(texte or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local res, vus = {}, {}
    local motif = '%' .. pourLike(texte) .. '%'
    local function ajouter(genre, id, extra)
        local valeur = genre .. ':' .. id
        if vus[valeur] or #res >= max then return end
        vus[valeur] = true
        local g = GENRES[genre]
        res[#res + 1] = { label = ('%s %s · %s%s'):format(g.emoji, g.nom, id, extra or ''):sub(1, 100), valeur = valeur:sub(1, 100) }
    end
    for _, genre in ipairs({ 'trunk', 'glovebox', 'stash' }) do
        local g = GENRES[genre]
        if aLaTable(g.table) then
            for _, l in ipairs(requete(('SELECT `%s` AS id FROM `%s` WHERE `%s` LIKE ? ORDER BY id DESC LIMIT 25'):format(g.col, g.table, g.col), { motif })) do
                ajouter(genre, genre == 'stash' and tostring(l.id) or plaque(l.id))
            end
        end
    end
    -- Un véhicule possédé dont le coffre n'a encore jamais servi.
    if #texte >= 2 and aLaTable('owned_vehicles') then
        for _, l in ipairs(requete('SELECT plate FROM owned_vehicles WHERE plate LIKE ? LIMIT 10', { motif })) do
            ajouter('trunk', plaque(l.plate), ' (jamais ouvert)')
        end
    end
    return res
end

function VesperInventaireCoffre(valeur)
    valeur = tostring(valeur or '')
    local genre, id = valeur:match('^(%a+):(.+)$')
    if not genre or not GENRES[genre] then
        -- Texte libre : une plaque ou un nom de coffre.
        local r = VesperInventaireRecherche(valeur, 10)
        if #r == 1 then genre, id = r[1].valeur:match('^(%a+):(.+)$')
        else return { candidats = r } end
    end
    local g = GENRES[genre]
    if genre ~= 'stash' then id = plaque(id) end
    local c = { genre = genre, nom = g.nom, emoji = g.emoji, id = id, objets = {} }
    if aLaTable(g.table) then
        local l = requete(('SELECT items FROM `%s` WHERE `%s` = ? LIMIT 1'):format(g.table, g.col), { id })[1]
        c.existe = l ~= nil
        c.objets = contenu(decoderJson(l and l.items) or {})
    end
    if genre ~= 'stash' and aLaTable('owned_vehicles') then
        local v = requete('SELECT owner, vehicle, type FROM owned_vehicles WHERE TRIM(UPPER(plate)) = ? LIMIT 1', { id })[1]
        if v then
            c.proprietaire = { identifier = v.owner, nom = nomDe(v.owner) }
            local d = decoderJson(v.vehicle)
            -- Le modèle n'est utile que nommé (un hachage ne dit rien au staff).
            c.modele = type(d) == 'table' and type(d.model) == 'string' and d.model or nil
            -- Le coffre de l'autre type (boîte à gants ↔ coffre) : pour l'afficher en plus.
            local autre = genre == 'trunk' and 'glovebox' or 'trunk'
            local ga = GENRES[autre]
            if aLaTable(ga.table) then
                local la = requete(('SELECT items FROM `%s` WHERE `%s` = ? LIMIT 1'):format(ga.table, ga.col), { id })[1]
                if la then c.autre = { genre = autre, nom = ga.nom, emoji = ga.emoji, objets = contenu(decoderJson(la.items) or {}) } end
            end
        end
    end
    if not c.existe and not c.proprietaire then return nil, 'aucun coffre ni véhicule à ce nom' end
    return c
end

-- ── /inventaire historique ───────────────────────────────────────────────
-- Chaque gain / perte d'objet d'un personnage, avec sa raison : table
-- `vesper_inventory_mouvements` de vesper-inventory (1.6.0 ou plus). Sans
-- elle, la commande répond que l'historique n'existe pas sur ce serveur.

--- p = { licence, objet, texte, depuis, limite, decalage }
function VesperInventaireHistorique(p)
    if not aLaTable('vesper_inventory_mouvements') then
        return nil, "pas d'historique des objets sur ce serveur (vesper-inventory 1.6.0 ou plus)"
    end
    local licence = tostring(p.licence or '')
    local h = licence:match('(%x+)$')
    if not h or #h < 16 then return nil, 'licence invalide' end
    local cond, params = { 'licence = ?' }, { 'license:' .. h }
    if p.objet and p.objet ~= '' then
        cond[#cond + 1] = 'objet = ?'
        params[#params + 1] = p.objet
    end
    if p.texte and p.texte ~= '' then
        cond[#cond + 1] = 'raison LIKE ?'
        params[#params + 1] = '%' .. pourLike(p.texte) .. '%'
    end
    if tonumber(p.depuis) then
        cond[#cond + 1] = 'quand >= ?'
        params[#params + 1] = math.floor(tonumber(p.depuis))
    end
    local ou = table.concat(cond, ' AND ')
    local total = requete('SELECT COUNT(*) AS n FROM vesper_inventory_mouvements WHERE ' .. ou, params)[1]
    local limite = math.max(1, math.min(1000, math.floor(tonumber(p.limite) or 15)))
    local decalage = math.max(0, math.floor(tonumber(p.decalage) or 0))
    local lignes = requete(('SELECT quand, identifiant, objet, quantite, solde, raison FROM vesper_inventory_mouvements WHERE %s ORDER BY quand DESC, id DESC LIMIT %d OFFSET %d')
        :format(ou, limite, decalage), params)
    local noms = {}
    for _, l in ipairs(lignes) do
        l.label = libelle(l.objet)
        if noms[l.identifiant] == nil then noms[l.identifiant] = nomDe(l.identifiant) or false end
        l.personnage = noms[l.identifiant] or nil
    end
    return { total = total and tonumber(total.n) or 0, lignes = lignes }
end

-- ── /inventaire objet ────────────────────────────────────────────────────

--- Autocomplétion des objets : { label, valeur = nom }.
function VesperInventaireObjets(texte, max)
    max = max or 25
    local t = tostring(texte or ''):lower()
    local res = {}
    for nom, label in pairs(listeObjets()) do
        if t == '' or nom:lower():find(t, 1, true) or tostring(label):lower():find(t, 1, true) then
            res[#res + 1] = { label = ('%s (%s)'):format(label, nom):sub(1, 100), valeur = nom }
        end
    end
    table.sort(res, function(a, b) return a.label:lower() < b.label:lower() end)
    while #res > max do table.remove(res) end
    return res
end

local function quantiteDans(brut, nom)
    local n = 0
    for _, o in pairs(brut or {}) do
        if type(o) == 'table' and o.name == nom then n = n + (tonumber(o.amount or o.count) or 1) end
    end
    return n
end

function VesperInventaireObjet(nom)
    nom = tostring(nom or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if nom == '' then return nil, 'objet vide' end
    if not listeObjets()[nom] then
        local r = VesperInventaireObjets(nom, 10)
        if #r == 1 then nom = r[1].valeur
        elseif #r == 0 then return nil, 'objet inconnu'
        else return { candidats = r } end
    end
    local o = { objet = nom, label = libelle(nom), detenteurs = {}, total = 0 }
    local function ajouter(d)
        if d.quantite > 0 then
            o.detenteurs[#o.detenteurs + 1] = d
            o.total = o.total + d.quantite
        end
    end

    -- Joueurs connectés : en direct.
    local enLigne = {}
    local ESX = nil
    pcall(function() ESX = exports['es_extended']:getSharedObject() end)
    for _, src in ipairs(GetPlayers()) do
        local ok, inv = pcall(function() return exports[INVENTAIRE]:GetInventory(tonumber(src)) end)
        local x = ESX and ESX.GetPlayerFromId(tonumber(src))
        local ident = x and x.identifier
        if ident then enLigne[ident] = true end
        if ok and type(inv) == 'table' then
            local okn, n = pcall(function() return x and x.getName() end)
            ajouter({ genre = 'joueur', en_ligne = true, id = tonumber(src), identifier = ident,
                nom = okn and n or GetPlayerName(src), quantite = quantiteDans(inv, nom) })
        end
    end

    -- Le texte JSON contient "name":"<nom>" : un filtre SQL grossier, puis le compte exact.
    local motif = '%"' .. pourLike((nom:gsub('"', ''))) .. '"%'
    if aLaTable('users') then
        for _, u in ipairs(requete('SELECT identifier, firstname, lastname, inventory FROM users WHERE inventory LIKE ? LIMIT 500', { motif })) do
            if not enLigne[u.identifier] then
                ajouter({ genre = 'joueur', identifier = u.identifier,
                    nom = (('%s %s'):format(u.firstname or '', u.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
                    quantite = quantiteDans(decoderJson(u.inventory), nom) })
            end
        end
    end
    for genre, g in pairs(GENRES) do
        if aLaTable(g.table) then
            for _, l in ipairs(requete(('SELECT `%s` AS id, items FROM `%s` WHERE items LIKE ? LIMIT 500'):format(g.col, g.table), { motif })) do
                ajouter({ genre = genre, id = genre == 'stash' and tostring(l.id) or plaque(l.id), quantite = quantiteDans(decoderJson(l.items), nom) })
            end
        end
    end
    table.sort(o.detenteurs, function(a, b) return a.quantite > b.quantite end)
    o.nombre = #o.detenteurs
    while #o.detenteurs > 40 do table.remove(o.detenteurs) end
    return o
end
