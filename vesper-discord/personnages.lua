-- /wipe (bot) : les personnages d'une licence, et leur suppression.
-- Tout le travail est fait par vesper-personnages (exports ListePersonnages
-- et Wipe) : il connaît ses tables, expulse le joueur s'il est en jeu sur ce
-- personnage, et refuse de deviner le numéro.

local RESSOURCE = 'vesper-personnages'

--- Rend (true) ou (false, raison) selon que vesper-personnages répond.
local function disponible()
    if GetResourceState(RESSOURCE) ~= 'started' then
        return false, 'vesper-personnages ne tourne pas sur ce serveur'
    end
    return true
end

--- Un texte libre (pseudo, personnage, id…) → une licence, par la même
--- recherche que /id. Plusieurs réponses : on rend les candidats.
local function licenceDe(q)
    q = tostring(q or '')
    if q:find('^license2?:%x+$') or q:find('^char%d+:%x+$') or q:find('^%x+$') and #q >= 20 then return q end
    local trouves = VesperRecherche(q, 10) or {}
    if #trouves == 1 then return trouves[1].valeur end
    return nil, trouves
end

--- GET /personnages?q=… → { licence, personnages = { {numero, prenom, nom, metier, enJeu}… } }
function VesperPersonnagesListe(q, rappel)
    local ok, raison = disponible()
    if not ok then return rappel(503, { erreur = raison }) end
    local licence, candidats = licenceDe(q)
    if not licence then
        if candidats and #candidats > 1 then return rappel(200, { candidats = candidats }) end
        return rappel(404, { erreur = 'aucun joueur trouvé' })
    end
    exports[RESSOURCE]:ListePersonnages(licence, function(r)
        if not r then return rappel(404, { erreur = 'licence invalide' }) end
        if not r.personnages then return rappel(503, { erreur = 'la base de données ne répond pas' }) end
        rappel(200, r)
    end)
end

--- POST /wipe { licence, numero, auteur } → { ok, message, personnage }
function VesperPersonnagesWipe(d, rappel)
    local ok, raison = disponible()
    if not ok then return rappel(503, { erreur = raison }) end
    if type(d) ~= 'table' or type(d.licence) ~= 'string' or not tonumber(d.numero) then
        return rappel(400, { erreur = 'licence et numéro requis' })
    end
    local auteur = ('Discord : %s'):format(tostring(d.auteur or '?'):sub(1, 60))
    exports[RESSOURCE]:Wipe(d.licence, tonumber(d.numero), auteur, function(r)
        if not r then return rappel(500, { erreur = 'pas de réponse de vesper-personnages' }) end
        if not r.ok then return rappel(400, { erreur = r.message }) end
        rappel(200, r)
    end)
end
