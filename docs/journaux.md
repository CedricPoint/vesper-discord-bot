# Brancher un script sur les journaux du bot

Un script n'a que **deux appels** à faire. Le bot s'occupe du reste :
catégorie réservée au staff, salons, webhooks, envoi.

## 1. Se déclarer (au démarrage)

```lua
local BOT = 'vesper-discord'

local function declarer()
    if GetResourceState(BOT) ~= 'started' then return end
    exports[BOT]:declarer({
        titre = 'LSPD',      -- catégorie « 🚔 LOGS — LSPD »
        emoji = '🚔',
        prefixe = 'lspd',    -- salons « 🟢・lspd-service »…
        salons = {
            { cle = 'service', nom = 'service', emoji = '🟢',
              description = 'Prises et fins de service.' },
            -- … 20 sujets au plus
        },
    })
end

CreateThread(function() Wait(2000) declarer() end)
-- Le bot démarre après nous : il demande qui est là.
AddEventHandler('vesper-discord:pret', declarer)
AddEventHandler('onResourceStart', function(nom)
    if nom == BOT then SetTimeout(1500, declarer) end
end)
```

⚠️ L'identité d'un module est **la ressource qui appelle**
(`GetInvokingResource()`), pas ce qu'elle annonce : un script ne peut ni
écrire dans les salons d'un autre, ni en déclarer à sa place.

## 2. Journaliser

```lua
local pris = exports[BOT]:journal(GetCurrentResourceName(), 'service', {
    title = 'Prise de service', color = 0x22c55e,
    fields = { { name = 'Agent', value = '**Jean Dupont** `#12`', inline = true } },
    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
})
-- pris == false : pas de bot joignable → se rabattre sur ses propres webhooks.
```

L'embed est un [embed Discord](https://discord.com/developers/docs/resources/message#embed-object)
tel quel. La ressource regroupe jusqu'à 10 embeds par message et respecte
les limites de Discord (429 → attente demandée).

## Ce qui se passe ensuite

1. Au relevé suivant (≈ 15 s), le bot voit la déclaration dans `/etat`
   (`modules`), crée la catégorie, les salons (staff en lecture seule) et un
   webhook par salon, puis les envoie à la ressource (`POST /webhooks`).
2. La ressource garde les webhooks en **KVP** (ils survivent aux
   redémarrages) et poste elle-même.
3. Tant qu'un webhook n'existe pas, les journaux attendent (50 par sujet).
   Sans nouvelles du bot depuis 2 minutes, `journal` rend `false`.
4. Un salon supprimé à la main : Discord répond 404, la ressource oublie le
   webhook, le bot recrée salon et webhook au relevé suivant.
5. `/journaux` sur Discord : état de chaque script ; option
   `resynchroniser` pour tout revérifier.
6. **Un serveur ne voit que les scripts qu'il fait tourner.** Seules les
   ressources démarrées figurent dans `/etat` : un serveur qui n'a que
   `vesper-lspd` n'aura que la catégorie LSPD, et `vesper-ems` ajoutera la
   sienne le jour où il démarre.
7. Un script arrêté garde ses salons (une maintenance n'efface pas
   l'historique). Désinstallé pour de bon : `/journaux retirer:<script>`
   supprime sa catégorie et ses salons. Seuls les scripts absents sont
   proposés ; s'il redémarre un jour, tout est recréé.

## Scripts compatibles

| Script | Catégorie | Salons |
|---|---|---|
| `vesper-lspd` | 🚔 LOGS — LSPD | service, procedures, interpellations, armurerie, dispatch, radars-cameras, commandement, admin |
| `vesper-ems` | 🚑 LOGS — EMS | service, patients, soins, transport, dispatch, radio, finances, logistique, direction, admin |

## Pièges rencontrés

- ⚠️ **La signature d'un module ne passe pas par `json.encode`** : l'ordre
  des clés d'une table Lua change d'un démarrage à l'autre, et le bot
  croyait à chaque redémarrage que les salons avaient changé.
- ⚠️ **Un journal ne doit jamais casser l'action qu'il raconte** : côté
  script, tout appel est protégé (`pcall`) et rien n'attend Discord.
