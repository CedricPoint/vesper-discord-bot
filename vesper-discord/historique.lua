--- Historique des journaux : tout ce qui part sur Discord est aussi rangé en
--- base, pour que le staff puisse le retrouver avec /logs.
---
--- CE QUI EST RANGÉ
---   - chaque journal d'un script (journaux.lua), avec le message Discord où
---     il a été posté (lien direct) ;
---   - les événements du salon 📋 logs-joueurs (connexions, morts, métiers…).
---
--- ⚠️ LE RATTACHEMENT AUX JOUEURS SE FAIT SUR LE TEXTE. Les scripts écrivent
--- déjà qui est concerné : l'identifiant du personnage (`char0:<licence>`),
--- la licence (`license:<licence>`) ou l'id en jeu entre accents graves
--- (`#12`, traduit en licence s'il est connecté). On en tire la licence ;
--- aucun script n'a besoin d'être modifié. Un journal qui ne cite personne
--- reste trouvable par script, sujet et texte.
---
--- Durée de conservation : `set vesper_discord_historique_jours 30` (0 = sans
--- limite). Une base indisponible coupe l'historique, jamais les journaux.

local JOURS = GetConvarInt('vesper_discord_historique_jours', 30)
local pret = false

local function licenceDe(src)
    for _, ident in ipairs(GetPlayerIdentifiers(src) or {}) do
        if ident:sub(1, 8) == 'license:' then return ident:sub(9) end
    end
    return nil
end

local function purger()
    if JOURS <= 0 then return end
    local limite = os.time() - JOURS * 86400
    local ok, r = pcall(MySQL.update.await, 'DELETE FROM vesper_discord_journaux WHERE quand < ?', { limite })
    if ok and (tonumber(r) or 0) > 0 then
        print(('[vesper-discord] historique : %d journal(aux) de plus de %d jours effacé(s)'):format(r, JOURS))
    end
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS vesper_discord_journaux (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            quand INT UNSIGNED NOT NULL,
            ressource VARCHAR(64) NOT NULL,
            sujet VARCHAR(64) NOT NULL,
            titre VARCHAR(256) NULL,
            texte TEXT NOT NULL,
            salon VARCHAR(24) NULL,
            message VARCHAR(24) NULL,
            KEY quand (quand),
            KEY origine (ressource, sujet, quand)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS vesper_discord_journaux_joueurs (
            journal BIGINT UNSIGNED NOT NULL,
            licence CHAR(40) NOT NULL,
            PRIMARY KEY (licence, journal),
            KEY journal (journal),
            CONSTRAINT vesper_discord_journaux_joueurs_journal FOREIGN KEY (journal)
                REFERENCES vesper_discord_journaux (id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    end)
    if not ok then
        print(('[vesper-discord] historique désactivé : base indisponible (%s)'):format(tostring(err)))
        return
    end
    pret = true
    purger()
    while true do
        Wait(6 * 60 * 60 * 1000)
        purger()
    end
end)

-- ── Enregistrer ──────────────────────────────────────────────────────────

local function aplatir(e)
    local morceaux = {}
    local function ajouter(v) if type(v) == 'string' and v ~= '' then morceaux[#morceaux + 1] = v end end
    ajouter(e.title)
    ajouter(e.description)
    if type(e.author) == 'table' then ajouter(e.author.name) end
    if type(e.fields) == 'table' then
        for _, f in ipairs(e.fields) do
            if type(f) == 'table' then ajouter(('%s : %s'):format(tostring(f.name or ''), tostring(f.value or ''))) end
        end
    end
    if type(e.footer) == 'table' then ajouter(e.footer.text) end
    return table.concat(morceaux, '\n'):sub(1, 4000)
end

local function licencesDe(texte, autres)
    local vues, liste = {}, {}
    local function ajouter(h)
        h = type(h) == 'string' and h:lower():match('^%x+$') or nil
        if h and #h == 40 and not vues[h] then vues[h] = true; liste[#liste + 1] = h end
    end
    for h in texte:gmatch('char%d+:(%x+)') do ajouter(h) end
    for h in texte:gmatch('license:(%x+)') do ajouter(h) end
    for id in texte:gmatch('`#(%d+)`') do
        local src = tonumber(id)
        if src and GetPlayerName(src) then ajouter(licenceDe(src)) end
    end
    for _, h in ipairs(autres or {}) do ajouter((tostring(h):match('(%x+)$'))) end
    return liste
end

local function lierMessage(ids, salon, message)
    if #ids == 0 then return end
    local marques = ('?,'):rep(#ids):sub(1, -2)
    local params = { salon, message }
    for _, id in ipairs(ids) do params[#params + 1] = id end
    MySQL.update(('UPDATE vesper_discord_journaux SET salon = ?, message = ? WHERE id IN (%s)'):format(marques), params)
end

--- Range un journal. `entree` (facultative) est l'objet de la file d'envoi :
--- il reçoit l'id en base, pour qu'on y accroche le message Discord ensuite.
function VesperHistoriqueEnregistrer(ressource, sujet, embed, autresLicences, entree)
    if not pret or type(embed) ~= 'table' then return end
    local texte = aplatir(embed)
    if texte == '' then return end
    local licences = licencesDe(texte, autresLicences)
    local titre = type(embed.title) == 'string' and embed.title:sub(1, 256) or nil
    MySQL.insert('INSERT INTO vesper_discord_journaux (quand, ressource, sujet, titre, texte) VALUES (?, ?, ?, ?, ?)',
        { os.time(), ressource, sujet, titre, texte }, function(id)
            if not id then return end
            if entree then
                entree.id = id
                -- Le message est parti avant que la base ait répondu.
                if entree.message then lierMessage({ id }, entree.salon, entree.message) end
            end
            if #licences > 0 then
                local params = {}
                for _, h in ipairs(licences) do params[#params + 1] = id; params[#params + 1] = h end
                MySQL.insert(('INSERT IGNORE INTO vesper_discord_journaux_joueurs (journal, licence) VALUES %s')
                    :format(('(?, ?),'):rep(#licences):sub(1, -2)), params)
            end
        end)
end

--- Le message Discord où un lot de journaux a été posté.
function VesperHistoriqueMessage(entrees, salon, message)
    if not pret then return end
    local ids = {}
    for _, e in ipairs(entrees) do
        if e.id then ids[#ids + 1] = e.id
        else e.salon, e.message = salon, message end
    end
    lierMessage(ids, salon, message)
end

-- ── Chercher ─────────────────────────────────────────────────────────────

local function hachage(v)
    v = tostring(v or ''):lower()
    local h = v:match('^license:(%x+)$') or v:match('^char%d+:(%x+)$') or v:match('^(%x+)$')
    return h and #h == 40 and h or nil
end

local function conditions(p)
    local depuis = 'vesper_discord_journaux j'
    local ou, params = {}, {}
    local h = hachage(p.licence)
    if p.licence and p.licence ~= '' then
        if not h then return nil, 'licence invalide' end
        depuis = depuis .. ' JOIN vesper_discord_journaux_joueurs jj ON jj.journal = j.id'
        ou[#ou + 1] = 'jj.licence = ?'; params[#params + 1] = h
    end
    if p.ressource and p.ressource ~= '' then ou[#ou + 1] = 'j.ressource = ?'; params[#params + 1] = p.ressource end
    if p.sujet and p.sujet ~= '' then ou[#ou + 1] = 'j.sujet = ?'; params[#params + 1] = p.sujet end
    if p.texte and p.texte ~= '' then ou[#ou + 1] = 'j.texte LIKE ?'; params[#params + 1] = '%' .. p.texte .. '%' end
    if tonumber(p.depuis) then ou[#ou + 1] = 'j.quand >= ?'; params[#params + 1] = tonumber(p.depuis) end
    return depuis .. (#ou > 0 and (' WHERE ' .. table.concat(ou, ' AND ')) or ''), params
end

--- { total, lignes = [{ id, quand, ressource, sujet, titre, texte, salon, message }] }
function VesperHistoriqueChercher(p)
    if not pret then return nil, 'historique indisponible (base de données)' end
    local source, params = conditions(p)
    if not source then return nil, params end
    local limite = math.min(math.max(tonumber(p.limite) or 10, 1), 500)
    local decalage = math.max(tonumber(p.decalage) or 0, 0)
    local longueur = p.complet and 4000 or 400

    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM %s'):format(source), params)
    local args = {}
    for _, v in ipairs(params) do args[#args + 1] = v end
    args[#args + 1] = limite
    args[#args + 1] = decalage
    local lignes = MySQL.query.await(([[SELECT j.id, j.quand, j.ressource, j.sujet, j.titre,
        LEFT(j.texte, %d) AS texte, j.salon, j.message FROM %s
        ORDER BY j.quand DESC, j.id DESC LIMIT ? OFFSET ?]]):format(longueur, source), args)
    return { total = tonumber(total) or 0, lignes = lignes or {} }
end

--- Ce qu'on a sur un joueur, script par script.
function VesperHistoriqueResume(p)
    if not pret then return nil, 'historique indisponible (base de données)' end
    local source, params = conditions(p)
    if not source then return nil, params end
    local lignes = MySQL.query.await(([[SELECT j.ressource, j.sujet, COUNT(*) AS n,
        MIN(j.quand) AS premier, MAX(j.quand) AS dernier FROM %s
        GROUP BY j.ressource, j.sujet ORDER BY n DESC LIMIT 25]]):format(source), params)
    return { sujets = lignes or {}, conservation = JOURS }
end
