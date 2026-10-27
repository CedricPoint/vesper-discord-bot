# Bot Discord VESPER — documentation complète

> Bot **1.3.0** · ressource **`vesper-discord` 1.2.0** · serveur Discord VESPER RP.
>
> Pour brancher un script sur les salons de journaux, voir aussi
> [`journaux.md`](journaux.md).

---

## Sommaire

1. [Ce que fait le bot](#1-ce-que-fait-le-bot)
2. [Comment ça marche](#2-comment-ça-marche)
3. [Salons et rôles créés](#3-salons-et-rôles-créés)
4. [Commandes](#4-commandes)
5. [La fiche joueur : `/id`](#5-la-fiche-joueur--id)
6. [Le salon `📋・logs-joueurs`](#6-le-salon-logs-joueurs)
7. [Le panneau de statut](#7-le-panneau-de-statut)
8. [Les journaux des scripts](#8-les-journaux-des-scripts)
9. [Cohabitation avec Toastie](#9-cohabitation-avec-toastie)
10. [Configuration](#10-configuration)
11. [Installation, mise à jour, exploitation](#11-installation-mise-à-jour-exploitation)
12. [Sécurité](#12-sécurité)
13. [Dépannage](#13-dépannage)
14. [Référence : points d'accès de la ressource](#14-référence--points-daccès-de-la-ressource)
15. [Historique des versions](#15-historique-des-versions)

---

## 1. Ce que fait le bot

| Pour qui | Quoi |
|---|---|
| **Joueurs** | Panneau d'état du serveur en direct (en ligne, joueurs, services en ville, pic du jour, record), bouton « Se connecter », compteurs en salons vocaux, rôle « 🎮 En jeu » quand on est connecté, notifications de retour du serveur et des mises à jour. |
| **Staff** | Journal des joueurs (connexions, déconnexions, personnages, métiers, morts, redémarrages), **fiche complète d'un joueur avec `/id`**, annonces en jeu depuis Discord, mises à jour, maintenance, journaux de chaque script (LSPD, EMS, facturation, gangs…). |
| **Le serveur** | Le bot crée et entretient **seul** ses salons, ses rôles, ses webhooks et ses commandes. |

Le bot ne fonctionne que sur **un** serveur Discord (`GUILD_ID`). Invité
ailleurs, il en repart immédiatement.

## 2. Comment ça marche

```
 Serveur FiveM (VPS)                               Discord
┌────────────────────────────┐   HTTP local    ┌───────────────────────┐
│ ressource vesper-discord   │◄────────────────│ bot (service systemd) │──► salons, rôles,
│  • état, joueurs, métiers  │  toutes les 15 s│  vesper-discord-bot   │    commandes, panneau
│  • événements (connexions…)│  + à la demande │                       │
│  • fiche joueur (/id)      │   (jeton + 127.0.0.1)                   │
│  • journaux des scripts ───┼──── webhooks Discord ─────────────────────► salons « LOGS — … »
└────────────────────────────┘                 └───────────────────────┘
```

- **La ressource FiveM** (`resources/[standalone]/vesper-discord`) lit ce que
  seul le serveur connaît : vrais noms des joueurs, métiers ESX, comptes
  Discord liés, argent, inventaire, base de données. Elle l'expose en JSON
  sur `http://127.0.0.1:30120/vesper-discord/…`, **à la machine elle-même et
  avec un jeton**.
- **Le bot** (Node.js 18, discord.js 14) interroge la ressource toutes les
  `INTERVALLE` secondes (15 par défaut) et met Discord à jour.
- Pourquoi une ressource ? Sur cet artefact, l'adresse publique
  `/players.json` rend chaque joueur sous le nom « Player », id 0, sans
  identifiant : impossible de nommer quelqu'un ou de compter la police.
- Si la ressource est arrêtée, le bot se rabat sur `/dynamic.json` : il garde
  le nombre de joueurs mais perd les noms, les services et la fiche.

## 3. Salons et rôles créés

### Catégorie « 📡 VESPER RP — SERVEUR » (joueurs)

| Salon | Visible par | Contenu |
|---|---|---|
| `📊・statut-serveur` | Citoyen + staff (lecture seule) | Panneau en direct + annonces de panne, retour, redémarrage, maintenance. |
| `📢・mises-à-jour` | Citoyen + staff (lecture seule) | Mises à jour publiées par le staff avec `/update`. |
| `🎮 En jeu : X/48` (vocal) | Citoyen + staff (connexion interdite) | Compteur de joueurs. |
| `👥 Membres : N` (vocal) | Citoyen + staff (connexion interdite) | Compteur de membres du Discord. |

### Catégorie « 🛡️ VESPER — STAFF » (privée)

| Salon | Contenu |
|---|---|
| `📋・logs-joueurs` | Tout ce que font les joueurs côté serveur : voir [§ 6](#6-le-salon-logs-joueurs). |
| `🤖・journal-bot` | Démarrages du bot, redémarrages et pannes du serveur, ressources lancées ou arrêtées, annonces en jeu envoyées, **consultations de fiches `/id`**. |

### Catégories « LOGS — … » (privées, une par script)

Créées automatiquement pour chaque script qui se déclare (LSPD, EMS,
facturation, gangs…) : voir [§ 8](#8-les-journaux-des-scripts).

### Rôles

| Rôle | Rôle du rôle |
|---|---|
| `🔔 Notif serveur` | Chacun le prend ou le rend avec le bouton **🔔 Notifications** du panneau. Mentionné au retour du serveur, en fin de maintenance et aux mises à jour. |
| `🎮 En jeu` | Donné automatiquement aux membres connectés en jeu (compte Discord relié à FiveM), retiré à leur départ. Affiché à part dans la liste des membres s'il est placé au-dessus des autres rôles. |

> **Visibilité.** Les salons publics suivent la règle du serveur : cachés à
> `@everyone`, visibles du rôle **🎟️ Citoyen** (donné par Toastie quand le
> règlement est accepté) et du staff. C'est réglé par `ROLES_LECTURE` et
> `STAFF_ROLE_IDS` (voir [§ 10](#10-configuration)).
>
> **Vos réglages sont respectés.** Un salon déjà créé n'est jamais renommé ni
> déplacé par le bot, et ses permissions ne sont réécrites que si
> `ROLES_LECTURE` ou `STAFF_ROLE_IDS` changent. Vous pouvez le ranger ou le
> renommer à la main.

## 4. Commandes

Toutes les réponses marquées « privée » ne sont visibles que de la personne
qui lance la commande.

| Commande | Qui | Ce qu'elle fait |
|---|---|---|
| `/statut` | tous | Affiche le panneau d'état. |
| `/joueurs` | tous | Liste des joueurs en ville (privée). Le staff voit en plus personnage, métier, ping et compte Discord. |
| `/connexion` | tous | Comment rejoindre le serveur. |
| `/id joueur:<…>` | staff | **Fiche complète d'un joueur** (privée) : voir [§ 5](#5-la-fiche-joueur--id). |
| `/update [notifier]` | staff | Ouvre un formulaire (titre, version, changements, image) et publie dans `📢・mises-à-jour`. Une ligne = une puce. `notifier` (oui par défaut) mentionne `🔔 Notif serveur`. |
| `/annonce-jeu message:<…>` | staff | Écrit dans le tchat **en jeu** de tous les joueurs (400 caractères au plus). Tracé dans `🤖・journal-bot`. |
| `/maintenance activer [raison]` | staff | Passe le panneau en 🟠 maintenance et l'annonce. |
| `/maintenance terminer` | staff | Fin de maintenance, annonce avec mention `🔔 Notif serveur`. |
| `/journaux [resynchroniser] [retirer]` | staff | État des journaux de chaque script ; `resynchroniser` revérifie salons et webhooks ; `retirer` supprime les salons d'un script désinstallé. |
| `/installer` | administrateurs | Recrée les salons et rôles du bot qui manqueraient. |

> ⚠️ **Les commandes staff n'apparaissent qu'aux membres ayant la permission
> « Gérer le serveur ».** Pour les montrer à d'autres rôles staff :
> *Paramètres du serveur → Intégrations → VESPER RP*, puis autoriser ces rôles
> commande par commande. Le bot accepte de toute façon les rôles de
> `STAFF_ROLE_IDS`.

## 5. La fiche joueur : `/id`

### Chercher un joueur

L'option `joueur` propose des résultats **pendant la frappe**. Les joueurs
connectés apparaissent en premier (🟢), puis ceux de la base (⚫). On peut
taper :

| On tape | Exemple |
|---|---|
| l'id en jeu | `2` |
| la licence | `license:1c19488d…` ou les 40 caractères seuls |
| l'identifiant d'un personnage | `char0:1c19488d…` |
| un nom de personnage | `Gustavo`, `Marillo` |
| un pseudo FiveM | `pitt51` |
| un compte Discord (mention ou id) | `@Pitt51tv` (seulement s'il est en jeu) |

Si plusieurs joueurs correspondent sans qu'on ait choisi dans la liste, le
bot les énumère avec leur licence.

### Ce que contient la fiche

**Carte « compte »** (le joueur FiveM) : pseudo, en jeu ou non (id, ping) ou
date de dernière visite, licence, compte Discord, temps de jeu total, nombre
de personnages et d'emplacements, première connexion relevée, rang staff,
**sanctions** (bannissements actifs ou levés, auteur, durée).

**Une carte par personnage :**

| Rubrique | Détail | Source |
|---|---|---|
| 🪪 Identité | date de naissance, sexe, taille, groupe sanguin, téléphone, date de création | `users`, `phone_phones` (lb-phone) |
| 💼 Métier | métier et grade, matricule LSPD/EMS, groupe ESX, gang et grade | ESX, `vesper_lspd_personnel`, `vesper_gangs_*` |
| 💰 Argent | liquide, banque, argent sale, cartes bancaires (4 derniers chiffres, bloquée ou non), jetons de casino | ESX en direct / `users.accounts`, `bank_cards`, `casino_memberships` |
| ⚖️ Justice, factures, assurances | entrées au casier (3 dernières : infractions, amende, prison), amendes impayées, factures ouvertes et reste dû, assurances santé et leur échéance | `vesper_lspd_casier`, `vesper_lspd_amendes`, `vesper_billing_factures`, `vesper_ems_assurances`, `health_insurances` |
| 🚗 Véhicules | plaque, modèle (nom réel : « Pegassi Zentorno »), état (au garage, sorti, en fourrière) et garage | `owned_vehicles` + catalogues des concessions |
| 🏠 Propriétés | maisons, locations, chambres de motel (avec dette de loyer) | `player_houses`, `houselocations`, `qs_motel_rentals` |
| 🎒 Inventaire | chaque objet avec sa quantité, libellé en français | qs-inventory en direct / `users.inventory`, `items` |

### En direct ou d'après la base ?

- **Personnage en jeu** : l'argent et l'inventaire sont lus **en direct**
  (ESX, qs-inventory). Le pied de la carte l'indique.
- **Hors ligne** : tout vient de la base, c'est-à-dire de la **dernière
  sauvegarde** du personnage.
- Une rubrique dont la table n'existe pas sur le serveur est simplement
  absente : la ressource fonctionne aussi sans lb-phone, sans vesper-lspd…

### Confidentialité

- Réponse **privée**, visible uniquement du membre du staff qui consulte.
- Chaque consultation est **tracée** dans `🤖・journal-bot` (qui a consulté quel
  joueur).
- Le numéro de carte bancaire n'est jamais affiché en entier, le code jamais.
- Pas d'adresse IP, ni dans la fiche ni dans les journaux.

## 6. Le salon `📋・logs-joueurs`

| Pastille | Événement | Ce qui est affiché |
|---|---|---|
| 🟢 ➡️ | Connexion | pseudo, id, compte Discord, licence |
| 🔵 🧍 | Personnage chargé (ou **nouveau personnage créé**) | nom du personnage, métier, argent liquide et banque |
| 🟣 💼 | Changement de métier | ancien → nouveau métier et grade |
| ⚫ 💀 | Mort | victime, **tueur** s'il s'agit d'un joueur, cause (arme, chute, véhicule, noyade…) |
| 🔴 ⬅️ | Déconnexion | personnage, métier, durée de session, argent au départ, raison, licence |
| 🟠 🔄 | Redémarrage ou panne | la liste des joueurs qui étaient en ville au moment de l'arrêt |

À savoir :

- Les **prises et fins de service** ne figurent pas ici : chaque métier les
  journalise déjà dans sa propre catégorie (`LOGS — LSPD`, `LOGS — EMS`).
- Un arrêt du serveur emporte la ressource avec lui : les départs individuels
  sont alors impossibles à transmettre. Le bot les **reconstitue** au
  redémarrage, en un seul message 🔄.
- La mort est signalée **par le jeu du joueur** (événement ESX
  `esx:onPlayerDeath`). C'est fiable pour un journal, mais pas une preuve. Un
  client qui la répète en boucle est limité à une mort toutes les 10 secondes.
- Les messages arrivent avec un décalage de 15 secondes au plus (l'intervalle
  de relevé). Rien n'est perdu entre deux relevés : la ressource numérote ses
  200 derniers événements.

## 7. Le panneau de statut

Le panneau est **un seul message**, réécrit seulement quand quelque chose
change. Il est toujours reposé en dernier dans le salon après une annonce.

| État | Couleur | Quand |
|---|---|---|
| 🟢 Serveur en ligne | vert | le serveur répond |
| 🟠 En maintenance | orange | `/maintenance activer` |
| 🔴 Hors ligne | rouge | 3 relevés manqués d'affilée (≈ 45 s) |

Il affiche : joueurs `X / 48` avec une jauge, durée depuis le démarrage, pic
du jour et record, **qui est en service** (👮 Police, 🚑 Secours, 🔧 Mécanos,
🚕 Taxis, 🏠 Immobilier), la liste des joueurs en ville et l'adresse F8.
Boutons : **🎮 Se connecter** (`cfx.re/join/…`), **👥 Joueurs**,
**🔔 Notifications**.

Annonces automatiques : 🔴 hors ligne, 🟢 de retour (avec mention
`🔔 Notif serveur`), 🔄 redémarrage détecté. La présence du bot suit le même
état (« Regarde 2/48 joueurs en ville », absent, inactif en maintenance).

Les compteurs vocaux ne sont renommés qu'**une fois toutes les 5 minutes au
plus** : Discord n'autorise que 2 renommages de salon par 10 minutes.

## 8. Les journaux des scripts

Un script compatible se **déclare** à la ressource (titre, emoji, liste de
sujets). Le bot crée alors seul une catégorie « LOGS — … » réservée au staff,
un salon et un webhook par sujet. Le script n'a ensuite qu'à appeler
`exports['vesper-discord']:journal(...)`.

| Script | Catégorie | Salons |
|---|---|---|
| `vesper-lspd` | 🚔 LOGS — LSPD | 8 |
| `vesper-ems` | 🚑 LOGS — EMS | 10 |
| `vesper-billing` | 💳 LOGS — Facturation | 6 |
| `vesper-gangs` | 🔫 LOGS — GANGS | 11 |

- Un serveur ne reçoit que les journaux des scripts **qu'il fait tourner**.
- Un script arrêté garde ses salons. Pour un script désinstallé :
  `/journaux retirer:<script>`.
- Salon supprimé à la main : il est recréé avec son webhook au relevé suivant.

Le guide du développeur (déclaration, envoi, pièges) est dans
[`journaux.md`](journaux.md).

## 9. Cohabitation avec Toastie

Toastie gère déjà sur ce serveur : **bienvenue** et rôle Citoyen après le
règlement, journaux du Discord, tickets, automod, anti-raid, anti-nuke,
suivi des invitations. Le bot VESPER **ne fait rien de tout ça** :

- message de bienvenue désactivé (`BIENVENUE=0`) ;
- aucun journal Discord (messages, membres) : seulement ce qui se passe **en jeu** ;
- le statut FiveM et la whitelist de Toastie sont désactivés sur ce serveur.
  ⚠️ Activer `fivem_status` dans Toastie ferait doublon avec le panneau.

⚠️ L'anti-raid de Toastie expulsait tout compte de moins de 24 h, **bots
compris** : le bot VESPER était éjecté à la seconde de son invitation, sans
trace visible. Corrigé dans Toastie **4.37.6** (les bots sont ignorés par
l'anti-raid, puisque seul un admin peut en ajouter un).

## 10. Configuration

### `.env` du bot (`/opt/vesper-discord-bot/.env`, droits 600)

| Variable | Rôle | Valeur sur VESPER |
|---|---|---|
| `DISCORD_TOKEN` | jeton du bot | *secret* |
| `GUILD_ID` | le seul serveur Discord autorisé | `1563713516920250420` |
| `FIVEM_URL` | adresse du serveur FiveM vue du bot | `http://127.0.0.1:30120` |
| `VESPER_JETON` | même valeur que `vesper_discord_jeton` | *secret* |
| `ADRESSE_CONNEXION` | affichée pour `connect …` (F8) | `92.112.194.115:30120` |
| `CFX_JOIN` | code du bouton « Se connecter » | `m44lb6q` |
| `STAFF_ROLE_IDS` | rôles staff (ids, virgules) : salons privés, commandes | les 8 rôles staff |
| `ROLES_LECTURE` | rôles qui voient les salons publics (vide = tout le monde) | 🎟️ Citoyen |
| `INTERVALLE` | secondes entre deux relevés (10 au minimum) | `15` |
| `BIENVENUE` | `1` = message de bienvenue (exige l'intention « Server Members ») | `0` |

Après modification : `systemctl restart vesper-discord-bot`.

### `server.cfg`

```cfg
set vesper_discord_jeton "un-long-jeton-aléatoire"
ensure vesper-discord
```

⚠️ `set`, **jamais `sets`** : un `sets` est publié dans la liste publique des
serveurs.

### Permissions Discord du bot

Le bot est invité avec la permission **Administrateur**, la plus simple pour
créer salons, rôles et webhooks. Le minimum réel est : gérer les salons,
gérer les rôles, gérer les webhooks, envoyer des messages, intégrer des
liens, lire l'historique, mentionner les rôles. Son rôle doit rester
**au-dessus** de `🎮 En jeu` et `🔔 Notif serveur` pour pouvoir les donner.

## 11. Installation, mise à jour, exploitation

### Où sont les choses

| Quoi | Où |
|---|---|
| Code (dépôt privé) | `CedricPoint/vesper-discord-bot` : `bot/` et `vesper-discord/` |
| Bot sur le VPS | `/opt/vesper-discord-bot` (utilisateur `vesperbot`), service `vesper-discord-bot` |
| État du bot | `/opt/vesper-discord-bot/data/etat.json` (salons, rôles, webhooks, records) |
| Ressource | `/home/fxserver/vesper/server-data/resources/[standalone]/vesper-discord` |
| Sauvegardes | `/opt/vesper-discord-bot-sauvegardes/` (bot), `server-data/sauvegardes-code/vesper-discord-avant-*` (ressource) |

### Mettre à jour

1. **Sauvegarder** : `tar` de la ressource dans `sauvegardes-code/` et du bot
   dans `/opt/vesper-discord-bot-sauvegardes/`.
2. **Copier** les fichiers, `chown` (fxserver / vesperbot), vérifier :
   `luac5.4 -p *.lua`, `node --check src/index.js`.
3. **Ressource** : `refresh` **puis** `restart vesper-discord`.
   ⚠️ Un fichier ajouté au `fxmanifest.lua` sans `refresh` n'est pas chargé, et
   aucune erreur ne le signale. Les webhooks des journaux sont en KVP : ils
   survivent au redémarrage, et les scripts se redéclarent seuls.
4. **Bot** : `systemctl restart vesper-discord-bot`.
5. **Tester la mise en forme** sans rien envoyer sur Discord :
   `node tests/mise-en-forme.js fiche.json`. Le test valide chaque embed avec
   les limites de discord.js, à partir d'une vraie réponse de `/fiche`.

### Commandes utiles (VPS)

```bash
systemctl status vesper-discord-bot           # le bot tourne-t-il ?
journalctl -u vesper-discord-bot -n 50        # ses derniers messages
systemctl restart vesper-discord-bot          # le relancer (après un changement de .env)
python3 /root/vesper_console.py "restart vesper-discord"   # recharger la ressource
```

### Changer le jeton du bot

1. Portail développeur Discord → application VESPER RP → **Bot → Reset Token**.
2. Remplacer `DISCORD_TOKEN=` dans `/opt/vesper-discord-bot/.env`.
3. `systemctl restart vesper-discord-bot`.

## 12. Sécurité

- La ressource n'accepte que **127.0.0.1** et le **jeton** : impossible de
  l'interroger depuis Internet, même en connaissant l'adresse.
- Le jeton du pont est déclaré avec `set` (privé), jamais `sets`.
- Le `.env` est en droits 600 et appartient à `vesperbot`. Le service tourne
  sous cet utilisateur dédié, sans privilèges, et ne peut écrire que dans
  `data/`.
- Les requêtes SQL de la fiche sont paramétrées : aucune saisie n'est
  insérée telle quelle.
- `/id`, `/annonce-jeu`, `/update`, `/maintenance` et `/journaux` sont
  réservées au staff ; les consultations `/id` et les annonces sont tracées.
- Jamais dans le dépôt : `.env`, `data/etat.json` (il contient les webhooks).

## 13. Dépannage

| Symptôme | Cause probable et remède |
|---|---|
| Le bot rejoint le serveur puis disparaît aussitôt | L'anti-raid de Toastie (avant 4.37.6) ou un autre bot de sécurité l'expulse. Vérifier le journal d'audit Discord. |
| `📋・logs-joueurs` reste vide | Personne ne s'est connecté ni déconnecté depuis. Un départ causé par un arrêt du serveur n'apparaît qu'au redémarrage (message 🔄). |
| `/id` répond « Le serveur n'a pas répondu » | La ressource est arrêtée ou le serveur est hors ligne : `ensure vesper-discord`. |
| `/id` affiche de vieilles valeurs | Le personnage est hors ligne : c'est sa dernière sauvegarde. En jeu, argent et inventaire sont lus en direct. |
| Les commandes staff n'apparaissent pas | Il manque la permission « Gérer le serveur » : *Intégrations → VESPER RP*. |
| Les compteurs ne bougent plus | Limite Discord de 2 renommages par 10 minutes : ils rattrapent au plus tard 5 minutes après. |
| Le panneau indique « hors ligne » alors que le serveur tourne | La ressource ne répond plus à `/dynamic.json` non plus : vérifier `journalctl -u vesper`. |
| Un salon de journaux supprimé par erreur | Rien à faire : il est recréé au relevé suivant. Sinon `/journaux resynchroniser:True`. |
| Une modification de la ressource n'a aucun effet | Fichier ajouté au manifeste sans `refresh` : faire `refresh` puis `restart vesper-discord`. |

## 14. Référence : points d'accès de la ressource

Tous sous `http://127.0.0.1:30120/vesper-discord/`, avec l'en-tête
`X-Vesper-Jeton: <jeton>`. Sans le bon jeton ou hors de la machine, la
réponse est `403 {"erreur":"refuse"}`.

| Méthode et chemin | Réponse |
|---|---|
| `GET /etat?depuis=N` | `nom`, `max`, `en_ligne_depuis` (s), `ressources[]`, `joueurs[]` (id, nom, ping, discord, licence, métier, grade, en service, personnage, argent), `evenements[]` (numérotés après `N`), `dernier`, `modules[]` |
| `GET /recherche?q=…` | `{ resultats: [{ label, valeur: "license:…" }] }`, 25 au plus, joueurs connectés en premier |
| `GET /fiche?q=…` | la fiche complète, ou `{ candidats: [...] }` si la recherche est ambiguë, ou `404 { erreur }` |
| `POST /annonce` | corps `{ message, auteur }` → tchat en jeu ; `400` si le message est vide |
| `POST /webhooks` | corps `{ id, webhooks: { sujet: url } }` : les webhooks d'un script, envoyés par le bot |

Types d'événements dans `/etat` : `arrivee`, `personnage` (`nouveau`),
`metier` (`avant`, `apres`), `mort` (`tueur`, `cause`), `depart` (`raison`,
`joueur.duree`). Le type `redemarrage` est fabriqué par le bot lui-même.

## 15. Historique des versions

| Version | Nouveautés |
|---|---|
| **Bot 1.3.0 · ressource 1.2.0** | `/id` : fiche complète d'un joueur avec autocomplétion. Salon `📜・connexions-jeu` devenu `📋・logs-joueurs` : licence, personnage chargé ou créé, changement de métier, mort (tueur, cause), argent au départ, joueurs déconnectés par un redémarrage. Test de mise en forme hors ligne. |
| Bot 1.2.0 | `/journaux retirer` pour nettoyer les salons d'un script désinstallé. |
| Bot 1.1.0 · ressource 1.1.0 | Journaux des scripts : catégories, salons et webhooks créés par le bot. |
| Bot 1.0.0 · ressource 1.0.0 | Panneau de statut, compteurs, rôles, journal des connexions, `/update`, `/annonce-jeu`, `/maintenance`, verrouillage sur un seul serveur, alignement sur Toastie. |
