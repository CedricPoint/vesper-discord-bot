--- Les journaux des scripts : chaque script se déclare, le bot crée ses salons.
---
--- LE PARCOURS
---   1. Un script (vesper-lspd…) appelle `exports['vesper-discord']:declarer({...})`
---      avec ses sujets : { cle, nom, emoji, description }.
---   2. Au relevé suivant (≈ 15 s), le bot voit la déclaration dans /etat,
---      crée une catégorie réservée au staff, un salon par sujet et un
---      webhook par salon, puis nous les renvoie (POST /webhooks).
---   3. Le script appelle `exports['vesper-discord']:journal(id, sujet, embed)` :
---      on regroupe et on poste nous-mêmes, au rythme que Discord accepte.
---
--- ⚠️⚠️ LES WEBHOOKS SONT DES SECRETS : qui a l'URL écrit dans le salon. Ils
--- ne vivent que côté serveur (KVP de la ressource), n'arrivent que par le
--- point d'entrée local à jeton, et ne sont jamais affichés.
---
--- ⚠️ RIEN NE SE PERD AU PREMIER DÉMARRAGE. Tant que le bot n'a pas fourni
--- le webhook d'un sujet, ses journaux attendent ici (50 au plus par sujet).
--- Sans nouvelles du bot depuis 2 minutes, `journal` rend `false` : le
--- script se rabat alors sur ses propres webhooks s'il en a.

local modules = {}     -- id → déclaration
local webhooks = {}    -- id → { sujet → url }
local attente = {}     -- 'id|sujet' → { embeds }
local files = {}       -- url → { embeds = {}, prochain = ms, enVol = bool, id, sujet }
local dernierContactBot = 0

local MAX_ATTENTE = 50
local MAX_FILE = 200
local PAUSE_ENTRE_ENVOIS = 450   -- ms : Discord tolère 5 envois / 2 s par webhook
local SILENCE_BOT = 120          -- s sans relevé du bot : on ne garde plus rien

local function cleKvp(id) return 'webhooks:' .. id end

local function charger(id)
    local brut = GetResourceKvpString(cleKvp(id))
    local ok, t = pcall(json.decode, brut or '')
    return (ok and type(t) == 'table') and t or {}
end

local function enregistrer(id)
    SetResourceKvp(cleKvp(id), json.encode(webhooks[id] or {}))
end

local function urlValide(u)
    return type(u) == 'string'
        and (u:find('^https://discord%.com/api/webhooks/%d+/[%w_%-]+$')
          or u:find('^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+$')
          or u:find('^https://canary%.discord%.com/api/webhooks/%d+/[%w_%-]+$')
          or u:find('^https://ptb%.discord%.com/api/webhooks/%d+/[%w_%-]+$')) ~= nil
end

local function propre(texte, max)
    texte = tostring(texte or ''):gsub('[%c]', ' ')
    return texte:sub(1, max)
end

-- ══════════════════════════════════════════════════════════════════════
--  La déclaration
-- ══════════════════════════════════════════════════════════════════════

--- ⚠️ L'IDENTITÉ D'UN MODULE EST LA RESSOURCE QUI APPELLE, pas ce qu'elle
--- prétend : un script ne peut ni écrire dans les salons d'un autre, ni
--- en déclarer à sa place.
exports('declarer', function(m)
    local id = GetInvokingResource()
    if not id or type(m) ~= 'table' or type(m.salons) ~= 'table' then return false end

    local salons, vus = {}, {}
    for _, s in ipairs(m.salons) do
        local cle = type(s) == 'table' and tostring(s.cle or ''):match('^[%w_]+$')
        if cle and not vus[cle] and #salons < 20 then
            vus[cle] = true
            local nom = tostring(s.nom or cle):lower():gsub('[^%w%-]', '-'):gsub('%-+', '-'):sub(1, 40)
            salons[#salons + 1] = {
                cle = cle, nom = nom, emoji = propre(s.emoji or '📁', 8),
                description = propre(s.description, 200),
            }
        end
    end
    if #salons == 0 then return false end

    local prefixe = tostring(m.prefixe or id):lower():gsub('[^%w%-]', '-'):sub(1, 20)
    local decl = {
        id = id, titre = propre(m.titre or id, 40), emoji = propre(m.emoji or '📁', 8),
        prefixe = prefixe, salons = salons,
    }
    --  ⚠️ PAS DE json.encode ICI : l'ordre des clés d'une table Lua change
    --  d'un démarrage à l'autre, la signature aussi, et le bot croyait à
    --  chaque redémarrage que les salons avaient changé.
    local morceaux = { decl.titre, decl.emoji, decl.prefixe }
    for _, s in ipairs(salons) do
        morceaux[#morceaux + 1] = table.concat({ s.cle, s.nom, s.emoji, s.description }, '\31')
    end
    decl.signature = table.concat(morceaux, '\30')
    modules[id] = decl
    if not webhooks[id] then webhooks[id] = charger(id) end
    print(('[vesper-discord] journaux : %s déclaré (%d sujets)'):format(id, #salons))
    return true
end)

-- ══════════════════════════════════════════════════════════════════════
--  L'envoi
-- ══════════════════════════════════════════════════════════════════════

local function pousser(id, sujet, url, embed)
    local f = files[url]
    if not f then
        f = { embeds = {}, prochain = 0, enVol = false, id = id, sujet = sujet }
        files[url] = f
    end
    if #f.embeds >= MAX_FILE then table.remove(f.embeds, 1) end
    f.embeds[#f.embeds + 1] = embed
end

--- @return boolean pris en charge (sinon le script se rabat sur ses webhooks)
exports('journal', function(_, sujet, embed)
    local id = GetInvokingResource()
    local m = id and modules[id]
    if not m or type(embed) ~= 'table' or type(sujet) ~= 'string' then return false end

    local url = webhooks[id] and webhooks[id][sujet]
    if urlValide(url) then
        pousser(id, sujet, url, embed)
        return true
    end
    -- Le bot ne s'est pas manifesté : il ne viendra peut-être jamais.
    if os.time() - dernierContactBot > SILENCE_BOT then return false end
    local k = id .. '|' .. sujet
    attente[k] = attente[k] or {}
    if #attente[k] >= MAX_ATTENTE then table.remove(attente[k], 1) end
    attente[k][#attente[k] + 1] = embed
    return true
end)

--- La taille d'un message de webhook est plafonnée (10 embeds, 6000
--- caractères en tout) : on prend ce qui tient.
local function lot(f)
    local pris, taille = {}, 0
    while #f.embeds > 0 and #pris < 10 do
        local t = #json.encode(f.embeds[1])
        if #pris > 0 and taille + t > 5500 then break end
        pris[#pris + 1] = table.remove(f.embeds, 1)
        taille = taille + t
    end
    return pris
end

local function oublierWebhook(url, f)
    if webhooks[f.id] and webhooks[f.id][f.sujet] == url then
        webhooks[f.id][f.sujet] = nil
        enregistrer(f.id)
    end
    -- Ce qui restait repart en attente : le bot recréera le salon.
    local k = f.id .. '|' .. f.sujet
    attente[k] = attente[k] or {}
    for _, e in ipairs(f.embeds) do
        if #attente[k] < MAX_ATTENTE then attente[k][#attente[k] + 1] = e end
    end
    files[url] = nil
end

CreateThread(function()
    while true do
        local maintenant = GetGameTimer()
        for url, f in pairs(files) do
            if not f.enVol and #f.embeds > 0 and maintenant >= f.prochain then
                local envoi = lot(f)
                local m = modules[f.id]
                f.enVol = true
                PerformHttpRequest(url, function(code, corps, entetes)
                    f.enVol = false
                    if code == 429 then
                        -- On remet le lot en tête et on attend ce que Discord demande.
                        for i = #envoi, 1, -1 do table.insert(f.embeds, 1, envoi[i]) end
                        local ok, d = pcall(json.decode, corps or '')
                        local attendre = ok and type(d) == 'table' and tonumber(d.retry_after) or 2
                        f.prochain = GetGameTimer() + math.ceil(attendre * 1000) + 100
                    elseif code == 404 or code == 401 then
                        -- Webhook supprimé (salon effacé à la main) : on l'oublie,
                        -- le bot le recrée au prochain relevé.
                        for i = #envoi, 1, -1 do table.insert(f.embeds, 1, envoi[i]) end
                        oublierWebhook(url, f)
                    else
                        if code < 200 or code >= 300 then
                            print(('[vesper-discord] journal %s/%s refusé par Discord (%s)')
                                :format(f.id, f.sujet, tostring(code)))
                        end
                        f.prochain = GetGameTimer() + PAUSE_ENTRE_ENVOIS
                    end
                end, 'POST', json.encode({
                    username = ((m and m.titre) or f.id) .. ' — journaux',
                    embeds = envoi,
                    allowed_mentions = { parse = {} },
                }), { ['Content-Type'] = 'application/json' })
            end
        end
        Wait(250)
    end
end)

-- ══════════════════════════════════════════════════════════════════════
--  Le dialogue avec le bot (appelé par server.lua)
-- ══════════════════════════════════════════════════════════════════════

--- Les modules des ressources lancées, et les sujets qui n'ont pas encore
--- de webhook : c'est ce qui dit au bot quoi créer.
function VesperJournauxEtat()
    dernierContactBot = os.time()
    local liste = {}
    for id, m in pairs(modules) do
        if GetResourceState(id) == 'started' then
            local manquants = {}
            for _, s in ipairs(m.salons) do
                if not urlValide(webhooks[id] and webhooks[id][s.cle]) then
                    manquants[#manquants + 1] = s.cle
                end
            end
            liste[#liste + 1] = {
                id = id, titre = m.titre, emoji = m.emoji, prefixe = m.prefixe,
                salons = m.salons, signature = m.signature, manquants = manquants,
            }
        end
    end
    table.sort(liste, function(a, b) return a.id < b.id end)
    return liste
end

--- POST /webhooks { id, webhooks = { sujet = url } }
function VesperJournauxRecevoir(d)
    if type(d) ~= 'table' or type(d.id) ~= 'string' or type(d.webhooks) ~= 'table' then
        return false, 'requête invalide'
    end
    local m = modules[d.id]
    if not m then return false, 'module inconnu' end
    webhooks[d.id] = webhooks[d.id] or charger(d.id)
    local recus = 0
    for _, s in ipairs(m.salons) do
        local url = d.webhooks[s.cle]
        if urlValide(url) then
            webhooks[d.id][s.cle] = url
            recus = recus + 1
            -- Ce qui attendait part maintenant, dans l'ordre.
            local k = d.id .. '|' .. s.cle
            for _, e in ipairs(attente[k] or {}) do pousser(d.id, s.cle, url, e) end
            attente[k] = nil
        end
    end
    enregistrer(d.id)
    print(('[vesper-discord] journaux : %d webhook(s) reçus pour %s'):format(recus, d.id))
    return true, recus
end

--  Les scripts lancés AVANT nous ne nous ont pas trouvés : on les appelle.
CreateThread(function()
    Wait(500)
    TriggerEvent('vesper-discord:pret')
end)
