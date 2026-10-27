--- Fiche joueur pour la commande /id du bot Discord.
---
--- On part d'une LICENCE (un compte FiveM) et on rassemble tout ce que le
--- serveur sait de ses personnages : identité, métier, argent, inventaire,
--- véhicules, propriétés, banque, gang, casier, factures, assurances.
---
--- ⚠️ CONNECTÉ OU NON. Pour un personnage en jeu, l'argent et l'inventaire
--- se lisent EN DIRECT (ESX, qs-inventory) : la base n'est réécrite qu'aux
--- sauvegardes et peut avoir plusieurs minutes de retard. Hors ligne, c'est
--- la base qui fait foi.
---
--- ⚠️ CHAQUE TABLE EST FACULTATIVE. On relève une fois la liste des tables
--- et une section dont la table manque est simplement absente de la fiche :
--- la ressource tourne aussi sur un serveur sans vesper-lspd ou sans lb-phone.
---
--- Identifiants : qs-multicharacter range les personnages sous
--- `char<N>:<licence sans préfixe>` ; un serveur sans multipersonnage les
--- range sous la licence elle-même. On cherche les deux.

local ESX = nil
CreateThread(function()
    local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
    if ok then ESX = obj end
end)

local function requete(sql, params)
    local ok, lignes = pcall(MySQL.query.await, sql, params or {})
    if not ok then
        print(('[vesper-discord] fiche : requête refusée (%s)'):format(tostring(lignes)))
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

-- ── Libellés : objets, métiers, modèles de véhicules ──────────────────────

local libellesObjets = nil
local function libelleObjet(nom)
    if not libellesObjets then
        libellesObjets = {}
        if aLaTable('items') then
            for _, l in ipairs(requete('SELECT name, label FROM items')) do libellesObjets[l.name] = l.label end
        end
    end
    return libellesObjets[nom] or nom
end

local metiers = nil
local function libelleMetier(nom, grade)
    if not metiers then
        metiers = {}
        if aLaTable('jobs') then
            for _, l in ipairs(requete('SELECT name, label FROM jobs')) do metiers[l.name] = { label = l.label, grades = {} } end
        end
        if aLaTable('job_grades') then
            for _, l in ipairs(requete('SELECT job_name, grade, label FROM job_grades')) do
                if metiers[l.job_name] then metiers[l.job_name].grades[tonumber(l.grade)] = l.label end
            end
        end
    end
    local m = metiers[nom]
    if not m then return nom, nil end
    return m.label, m.grades[tonumber(grade)]
end

-- Les modèles sont rangés en hachage : on refait le hachage des noms connus
-- (catalogues des concessions) pour retrouver un nom lisible.
local function nonSigne(h)
    h = tonumber(h)
    if not h then return nil end
    if h < 0 then h = h + 4294967296 end
    return math.floor(h)
end

local modeles = nil
local function nomModele(hachage)
    if not modeles then
        modeles = {}
        local function ajouter(modele, libelle)
            if type(modele) == 'string' and modele ~= '' then
                modeles[nonSigne(GetHashKey(modele))] = libelle or modele
            end
        end
        if aLaTable('vehicles') then
            for _, v in ipairs(requete('SELECT model, name FROM vehicles')) do ajouter(v.model, v.name) end
        end
        if aLaTable('qs_dealership_catalog') then
            for _, v in ipairs(requete('SELECT model, label, brand FROM qs_dealership_catalog')) do
                local marque = (type(v.brand) == 'string' and v.brand ~= '') and (v.brand .. ' ') or ''
                ajouter(v.model, marque .. (v.label or v.model))
            end
        end
    end
    return modeles[nonSigne(hachage)]
end

-- ── Joueurs en ligne ──────────────────────────────────────────────────────

local function licenceDe(src)
    for _, ident in ipairs(GetPlayerIdentifiers(src) or {}) do
        if ident:sub(1, 8) == 'license:' then return ident:sub(9) end
    end
    return nil
end

local function discordDe(src)
    for _, ident in ipairs(GetPlayerIdentifiers(src) or {}) do
        if ident:sub(1, 8) == 'discord:' then return ident:sub(9) end
    end
    return nil
end

local function xJoueur(src)
    if not ESX then return nil end
    local ok, xp = pcall(ESX.GetPlayerFromId, tonumber(src))
    return ok and xp or nil
end

local function identifiantDe(xp)
    local ok, id = pcall(xp.getIdentifier)
    if ok and type(id) == 'string' then return id end
    return xp.identifier
end

local function nomPersonnage(xp)
    local ok, nom = pcall(xp.getName)
    return ok and type(nom) == 'string' and nom ~= '' and nom or nil
end

local function enLigne(hachage)
    for _, src in ipairs(GetPlayers()) do
        if licenceDe(src) == hachage then return tonumber(src) end
    end
    return nil
end

-- ── Recherche (autocomplétion) ────────────────────────────────────────────

local function hachageDe(texte)
    local h = texte:match('^license2?:(%x+)$') or texte:match('^char%d+:(%x+)$')
    if h then return h end
    if #texte == 40 and texte:match('^%x+$') then return texte end
    return nil
end

--- Rend jusqu'à `max` joueurs { label, valeur = 'license:…' }, en ligne d'abord.
function VesperRecherche(texte, max)
    max = max or 25
    texte = (texte or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local t = texte:lower()
    local res, vus = {}, {}
    local function ajouter(h, label)
        if h and not vus[h] and #res < max then
            vus[h] = true
            res[#res + 1] = { label = label:sub(1, 100), valeur = 'license:' .. h }
        end
    end

    for _, src in ipairs(GetPlayers()) do
        local h = licenceDe(src)
        local xp = xJoueur(src)
        local perso = xp and nomPersonnage(xp) or nil
        local nom = GetPlayerName(src) or '?'
        local cherche = (src .. ' ' .. nom .. ' ' .. (perso or '') .. ' ' .. (h or '')):lower()
        if t == '' or cherche:find(t, 1, true) then
            ajouter(h, ('🟢 #%s %s%s'):format(src, nom, perso and (' — ' .. perso) or ''))
        end
    end

    local h = hachageDe(texte)
    if h then ajouter(h, '🔑 license:' .. h) end

    if #texte >= 2 and aLaTable('users') then
        local motif = '%' .. texte .. '%'
        for _, u in ipairs(requete([[SELECT identifier, firstname, lastname FROM users
            WHERE CONCAT_WS(' ', firstname, lastname) LIKE ? OR identifier LIKE ? LIMIT 25]], { motif, motif })) do
            local hu = (u.identifier or ''):match(':(%x+)$') or u.identifier
            ajouter(hu, ('⚫ %s %s'):format(u.firstname or '?', u.lastname or ''))
        end
    end
    if #texte >= 2 and aLaTable('cpa_playtime') then
        for _, p in ipairs(requete('SELECT license, last_name FROM cpa_playtime WHERE last_name LIKE ? LIMIT 25',
            { '%' .. texte .. '%' })) do
            ajouter((p.license or ''):match(':(%x+)$'), ('⚫ %s (pseudo FiveM)'):format(p.last_name or '?'))
        end
    end
    return res
end

-- ── Fiche complète ───────────────────────────────────────────────────────

local FACTURE_CLOSE = { payee = true, annulee = true, remboursee = true }

local function inventaireDe(brut)
    local cumul, ordre = {}, {}
    for _, o in pairs(brut or {}) do
        if type(o) == 'table' and o.name then
            local n = tonumber(o.amount or o.count) or 1
            if not cumul[o.name] then
                cumul[o.name] = { objet = o.name, label = o.label or libelleObjet(o.name), quantite = 0 }
                ordre[#ordre + 1] = o.name
            end
            cumul[o.name].quantite = cumul[o.name].quantite + n
        end
    end
    local liste = {}
    for _, nom in ipairs(ordre) do liste[#liste + 1] = cumul[nom] end
    table.sort(liste, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
    return liste
end

local function comptesDe(xp, accountsJson)
    local argent = { liquide = 0, banque = 0, sale = 0 }
    local brut = decoderJson(accountsJson) or {}
    argent.liquide = tonumber(brut.money) or 0
    argent.banque = tonumber(brut.bank) or 0
    argent.sale = tonumber(brut.black_money) or 0
    if xp then
        for nom, cle in pairs({ money = 'liquide', bank = 'banque', black_money = 'sale' }) do
            local ok, compte = pcall(xp.getAccount, nom)
            if ok and type(compte) == 'table' and tonumber(compte.money) then argent[cle] = tonumber(compte.money) end
        end
    end
    return argent
end

local function personnage(u, src, xp)
    local id = u.identifier
    local p = {
        identifiant = id,
        emplacement = id:match('^(char%d+):') or 'principal',
        prenom = u.firstname, nom = u.lastname,
        naissance = u.dateofbirth, sexe = u.sex, taille = tonumber(u.height),
        groupe = u.group, cree_le = u.created_at,
        en_jeu = xp ~= nil,
    }

    local job, grade = u.job, u.job_grade
    if xp and xp.job then job, grade = xp.job.name, xp.job.grade end
    p.metier, p.grade = libelleMetier(job, grade)

    p.argent = comptesDe(xp, u.accounts)

    local inv = nil
    if xp and src then
        local ok, liste = pcall(function() return exports['qs-inventory']:GetInventory(src) end)
        if ok and type(liste) == 'table' then inv = liste end
    end
    p.inventaire = inventaireDe(inv or decoderJson(u.inventory))
    p.inventaire_direct = inv ~= nil

    local meta = decoderJson(u.metadata) or {}
    if type(meta.bloodType) == 'string' then p.groupe_sanguin = meta.bloodType end

    if aLaTable('phone_phones') then
        local t = requete('SELECT phone_number FROM phone_phones WHERE owner_id = ? LIMIT 1', { id })[1]
        p.telephone = t and t.phone_number or u.phone_number
    else
        p.telephone = u.phone_number
    end

    if aLaTable('owned_vehicles') then
        p.vehicules = {}
        for _, v in ipairs(requete('SELECT plate, type, garage, stored, vehicle FROM owned_vehicles WHERE owner = ? ORDER BY plate', { id })) do
            local props = decoderJson(v.vehicle) or {}
            local etatV = ({ [0] = 'sorti', [1] = 'au garage', [2] = 'en fourrière' })[tonumber(v.stored) or -1] or '?'
            p.vehicules[#p.vehicules + 1] = {
                plaque = (v.plate or ''):gsub('%s+$', ''),
                modele = nomModele(props.model) or ('modèle ' .. tostring(props.model or '?')),
                type = v.type, garage = v.garage, etat = etatV,
            }
        end
    end

    p.proprietes = {}
    if aLaTable('player_houses') then
        local libelles = {}
        if aLaTable('houselocations') then
            for _, h in ipairs(requete([[SELECT hl.name, hl.label FROM houselocations hl
                JOIN player_houses ph ON ph.house = hl.name WHERE ph.owner = ? OR ph.citizenid = ?]], { id, id })) do
                libelles[h.name] = h.label
            end
        end
        for _, h in ipairs(requete('SELECT house, rented FROM player_houses WHERE owner = ? OR citizenid = ?', { id, id })) do
            p.proprietes[#p.proprietes + 1] = { nom = libelles[h.house] or h.house, type = (tonumber(h.rented) == 1) and 'location' or 'maison' }
        end
    end
    if aLaTable('qs_motel_rentals') then
        for _, m in ipairs(requete('SELECT motel_id, room_id, rent_debt FROM qs_motel_rentals WHERE tenant_identifier = ?', { id })) do
            p.proprietes[#p.proprietes + 1] = {
                nom = ('Motel %s, chambre %s'):format(tostring(m.motel_id), tostring(m.room_id)),
                type = 'motel', dette = tonumber(m.rent_debt) or 0,
            }
        end
    end

    if aLaTable('bank_cards') then
        p.cartes = {}
        for _, c in ipairs(requete('SELECT cardNumber, cardType, active FROM bank_cards WHERE identifier = ?', { id })) do
            -- Les 4 derniers chiffres suffisent pour reconnaître une carte.
            p.cartes[#p.cartes + 1] = { fin = tostring(c.cardNumber or ''):sub(-4), type = c.cardType, active = tonumber(c.active) == 1 }
        end
    end

    if aLaTable('vesper_gangs_membres') and aLaTable('vesper_gangs_gangs') then
        local g = requete([[SELECT g.nom, g.donnees, m.grade FROM vesper_gangs_membres m
            JOIN vesper_gangs_gangs g ON g.id = m.gang_id WHERE m.identifier = ? LIMIT 1]], { id })[1]
        if g then
            local gradeNom = nil
            local d = decoderJson(g.donnees) or {}
            for _, gr in ipairs(d.grades or {}) do
                if tonumber(gr.niveau) == tonumber(g.grade) then gradeNom = gr.nom end
            end
            p.gang = { nom = g.nom, grade = gradeNom or tostring(g.grade) }
        end
    end

    if aLaTable('vesper_lspd_casier') then
        local lignes = requete('SELECT infractions, amende, prison, fait_le FROM vesper_lspd_casier WHERE identifier = ? ORDER BY fait_le DESC', { id })
        p.casier = { total = #lignes, derniers = {} }
        for i = 1, math.min(3, #lignes) do
            local titres = {}
            for _, inf in ipairs(decoderJson(lignes[i].infractions) or {}) do titres[#titres + 1] = inf.titre end
            p.casier.derniers[#p.casier.derniers + 1] = {
                quand = tonumber(lignes[i].fait_le), infractions = table.concat(titres, ', '),
                amende = tonumber(lignes[i].amende) or 0, prison = tonumber(lignes[i].prison) or 0,
            }
        end
    end
    if aLaTable('vesper_lspd_amendes') then
        local a = requete('SELECT COUNT(*) AS n, COALESCE(SUM(montant), 0) AS total FROM vesper_lspd_amendes WHERE identifier = ? AND paye = 0', { id })[1]
        p.amendes_impayees = { nombre = tonumber(a and a.n) or 0, total = tonumber(a and a.total) or 0 }
    end
    if aLaTable('vesper_billing_factures') then
        local n, reste = 0, 0
        for _, f in ipairs(requete('SELECT statut, total, paye FROM vesper_billing_factures WHERE cible_id = ?', { id })) do
            if not FACTURE_CLOSE[f.statut] then
                n = n + 1
                reste = reste + math.max(0, (tonumber(f.total) or 0) - (tonumber(f.paye) or 0))
            end
        end
        p.factures_ouvertes = { nombre = n, reste = reste }
    end

    p.assurances = {}
    if aLaTable('vesper_ems_assurances') then
        local a = requete('SELECT jusqu_a FROM vesper_ems_assurances WHERE identifier = ?', { id })[1]
        if a then p.assurances[#p.assurances + 1] = { nom = 'Assurance santé (EMS)', jusqu_a = tonumber(a.jusqu_a) } end
    end
    if aLaTable('health_insurances') then
        local a = requete('SELECT insurance, duration FROM health_insurances WHERE owner = ?', { id })[1]
        if a then p.assurances[#p.assurances + 1] = { nom = 'Assurance ' .. tostring(a.insurance), jusqu_a = tonumber(a.duration) } end
    end
    if aLaTable('vesper_lspd_personnel') then
        local m = requete('SELECT metier, matricule FROM vesper_lspd_personnel WHERE identifier = ?', { id })[1]
        if m then p.matricule = ('%s %s'):format(tostring(m.metier):upper(), tostring(m.matricule)) end
    end
    if aLaTable('casino_memberships') then
        local c = requete('SELECT chips, vip FROM casino_memberships WHERE identifier = ?', { id })[1]
        if c then p.casino = { jetons = tonumber(c.chips) or 0, vip = tonumber(c.vip) == 1 } end
    end

    return p
end

--- Rend la fiche d'une licence, la liste des candidats si la recherche est
--- ambiguë, ou nil + raison.
function VesperFiche(texte)
    texte = (texte or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('^<@!?(%d+)>$', '%1')
    if texte == '' then return nil, 'recherche vide' end

    local hachage = hachageDe(texte)
    if not hachage and texte:match('^%d+$') then
        if #texte <= 5 and GetPlayerName(texte) then
            hachage = licenceDe(texte)
        elseif #texte >= 17 then
            -- Un identifiant Discord : seuls les joueurs connectés l'exposent.
            for _, src in ipairs(GetPlayers()) do
                if discordDe(src) == texte then hachage = licenceDe(src) end
            end
            if not hachage then return nil, 'aucun joueur connecté avec ce compte Discord' end
        end
    end
    if not hachage then
        local candidats = VesperRecherche(texte, 10)
        if #candidats == 1 then
            hachage = candidats[1].valeur:match(':(%x+)$')
        else
            return { candidats = candidats }
        end
    end

    local licence = 'license:' .. hachage
    local src = enLigne(hachage)
    local xpEnLigne = src and xJoueur(src) or nil
    local idEnLigne = xpEnLigne and identifiantDe(xpEnLigne) or nil

    local fiche = { licence = licence, personnages = {} }

    if src then
        fiche.en_ligne = {
            id = src, nom = GetPlayerName(src), ping = GetPlayerPing(src),
            discord = discordDe(src), personnage = idEnLigne,
        }
        fiche.discord = fiche.en_ligne.discord
    end

    if aLaTable('cpa_playtime') then
        local t = requete('SELECT seconds, last_name, first_seen, last_seen FROM cpa_playtime WHERE license = ?', { licence })[1]
        if t then
            fiche.temps_de_jeu = tonumber(t.seconds)
            fiche.pseudo = t.last_name
            fiche.premiere_vue = t.first_seen
            fiche.derniere_vue = t.last_seen
        end
    end
    if not fiche.temps_de_jeu and aLaTable('qs_adminmenu_playtime') then
        local t = requete('SELECT seconds FROM qs_adminmenu_playtime WHERE license = ?', { licence })[1]
        if t then fiche.temps_de_jeu = tonumber(t.seconds) end
    end
    fiche.pseudo = (src and GetPlayerName(src)) or fiche.pseudo

    if aLaTable('qs_multicharacter_slots') then
        local s = requete('SELECT activated_slots FROM qs_multicharacter_slots WHERE license = ?', { licence })[1]
        if s then fiche.emplacements = tonumber(s.activated_slots) end
    end
    if aLaTable('vesper_staff') then
        local s = requete('SELECT rang FROM vesper_staff WHERE licence = ?', { licence })[1]
        if s then fiche.staff = s.rang end
    end

    fiche.sanctions = {}
    for _, t in ipairs({ 'qs_admin_bans', 'cpa_bans' }) do
        if aLaTable(t) then
            for _, b in ipairs(requete(('SELECT reason, banned_by, created_at, expires_at, revoked_at FROM %s WHERE license = ? ORDER BY created_at DESC LIMIT 5'):format(t), { licence })) do
                fiche.sanctions[#fiche.sanctions + 1] = {
                    raison = b.reason, par = b.banned_by,
                    le = b.created_at,
                    jusqu_a = b.expires_at,
                    levee = b.revoked_at ~= nil,
                }
            end
        end
    end

    if aLaTable('users') then
        local lignes = requete([[SELECT * FROM users WHERE identifier LIKE ? OR identifier = ? OR identifier = ?
            ORDER BY identifier]], { 'char%:' .. hachage, hachage, licence })
        for _, u in ipairs(lignes) do
            local xp = (idEnLigne == u.identifier) and xpEnLigne or nil
            fiche.personnages[#fiche.personnages + 1] = personnage(u, xp and src or nil, xp)
        end
    end

    if #fiche.personnages == 0 and not src and not fiche.temps_de_jeu then
        return nil, 'aucun joueur connu avec cette licence'
    end
    return fiche
end
