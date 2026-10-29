# Bot VESPER — documentation

> Bot **1.5.2** · ressource FiveM **`vesper-discord` 1.4.2** · licence MIT.
> Brancher un script sur les salons de journaux : [`journaux.md`](journaux.md).
> Ce qui change d'une version à l'autre : [`../CHANGELOG.md`](../CHANGELOG.md).

---

## Sommaire

1. [Ce que fait le bot](#1-ce-que-fait-le-bot)
2. [Comment ça marche](#2-comment-ça-marche)
3. [Installation](#3-installation)
4. [Réglages : `/config`](#4-réglages--config)
5. [Salons et rôles créés](#5-salons-et-rôles-créés)
6. [Commandes](#6-commandes)
7. [La fiche joueur : `/id`](#7-la-fiche-joueur--id)
8. [Le salon `📋・logs-joueurs`](#8-le-salon-logs-joueurs)
8 bis. [Retrouver un journal : `/logs`](#8-bis-retrouver-un-journal--logs)
9. [Le panneau de statut](#9-le-panneau-de-statut)
10. [Les journaux des scripts](#10-les-journaux-des-scripts)
11. [Mises à jour](#11-mises-à-jour)
12. [Cohabiter avec d'autres bots](#12-cohabiter-avec-dautres-bots)
13. [Sécurité](#13-sécurité)
14. [Dépannage](#14-dépannage)
15. [Référence : points d'accès de la ressource](#15-référence--points-daccès-de-la-ressource)

---

## 1. Ce que fait le bot

| Pour qui | Quoi |
|---|---|
| **Joueurs** | Panneau d'état du serveur en direct (en ligne, joueurs, services en ville, pic du jour, record), bouton « Se connecter », compteurs en salons vocaux, rôle « 🎮 En jeu » quand on est connecté, notifications de retour du serveur et des mises à jour. |
| **Staff** | Journal des joueurs (connexions, déconnexions, personnages, métiers, morts, redémarrages), **fiche complète d'un joueur avec `/id`**, annonces en jeu depuis Discord, mises à jour, maintenance, journaux de chaque script compatible. |
| **Administrateurs** | Réglages depuis Discord (`/config`), **mises à jour en un clic** annoncées dans `🆕・updates-bot`. |
| **Le serveur** | Le bot crée et entretient **seul** ses salons, ses rôles, ses webhooks et ses commandes. |

Un bot = **un** serveur Discord. Il adopte celui où on l'invite en premier ;
invité ailleurs ensuite, il en repart immédiatement.

## 2. Comment ça marche

```
 Machine du serveur FiveM                          Discord
┌────────────────────────────┐   HTTP local    ┌───────────────────────┐
│ ressource vesper-discord   │◄────────────────│ bot (service systemd) │──► salons, rôles,
│  • état, joueurs, métiers  │  toutes les 15 s│  vesper-discord-bot   │    commandes, panneau
│  • événements (connexions…)│  + à la demande │                       │
│  • fiche joueur (/id)      │ (jeton + 127.0.0.1)    ▲                │
│  • journaux des scripts ───┼──── webhooks Discord ──┼──────────────────► salons « LOGS — … »
└────────────────────────────┘                 └─────┼─────────────────┘
                                                     │ toutes les 6 h
                                          versions publiées sur GitHub
```

- **La ressource FiveM** (`resources/[standalone]/vesper-discord`) lit ce que
  seul le serveur connaît : vrais noms des joueurs, métiers ESX, comptes
  Discord liés, argent, inventaire, base de données. Elle l'expose en JSON sur
  `http://127.0.0.1:30120/vesper-discord/…`, **à la machine elle-même et avec
  un jeton**.
- **Le bot** (Node.js 18.17+, discord.js 14) interroge la ressource toutes les
  15 secondes et met Discord à jour.
- Pourquoi une ressource ? L'adresse publique `/players.json` de FiveM peut
  rendre chaque joueur sous le nom « Player », sans identifiant : impossible
  alors de nommer quelqu'un ou de compter la police.
- Si la ressource est arrêtée, le bot se rabat sur `/dynamic.json` : il garde
  le nombre de joueurs mais perd les noms, les services et la fiche.

## 3. Installation

### Prérequis

- **Linux avec systemd**, sur **la même machine** que le serveur FiveM.
- **Node.js 18.17 ou plus**, npm, tar, curl.
- Côté FiveM : **ESX** (es_extended) et **oxmysql**. qs-inventory, lb-phone
  et les scripts vesper-* enrichissent la fiche `/id` s'ils sont là ; sans
  eux, les rubriques concernées sont simplement absentes.

### En une commande

1. Créez l'application sur
   [discord.com/developers/applications](https://discord.com/developers/applications) :
   *New Application* → *Bot* → *Reset Token*, et copiez le jeton.
2. Sur la machine :
   ```bash
   curl -fsSL https://raw.githubusercontent.com/CedricPoint/vesper-discord-bot/main/install.sh | sudo bash
   ```
   Le script télécharge la dernière version **et vérifie son empreinte**,
   crée l'utilisateur `vesperbot`, installe le bot dans
   `/opt/vesper-discord-bot`, demande le jeton, génère le jeton du pont,
   copie la ressource si vous lui donnez votre dossier `resources`, installe
   et démarre le service.
3. Ajoutez au `server.cfg` les lignes affichées, puis redémarrez le serveur
   (ou `refresh` et `ensure vesper-discord`) :
   ```cfg
   set vesper_discord_jeton "…"
   add_ace resource.vesper-discord command.refresh allow
   add_ace resource.vesper-discord command.restart allow
   add_ace resource.vesper-discord command.stop allow
   add_ace resource.vesper-discord command.start allow
   ensure vesper-discord
   ```
   ⚠️ `set`, **jamais `sets`** : un `sets` est publié dans la liste des serveurs.
   Les quatre `add_ace` laissent la ressource se recharger seule lors d'une
   mise à jour : sans elles, FiveM refuse (« Access denied for command … »).
   `restart` relance lui-même `stop` puis `start`, d'où les quatre. Elles ne
   valent que pour cette ressource.
4. Ouvrez le **lien d'invitation** affiché (permission Administrateur). Le
   bot adopte ce serveur Discord et crée tout.
5. Réglez-le avec `/config` (§ 4).

Relancer `install.sh` sur une machine déjà équipée ne remplace que le code :
le `.env` et `data/` (réglages, salons) sont gardés.

### À la main

```bash
cd bot && npm ci --omit=dev
cp .env.example .env && chmod 600 .env   # remplir DISCORD_TOKEN, VESPER_JETON
node lanceur.js
```

En service : `bot/deploy/vesper-discord-bot.service` (utilisateur dédié,
`ExecStart=node lanceur.js`).

### Message de bienvenue (facultatif)

Il exige l'intention **Server Members** : portail Discord → *Bot* →
*Privileged Gateway Intents*. Puis `/config bienvenue actif:True`. Laissez-le
coupé si un autre bot accueille déjà vos membres.

## 4. Réglages : `/config`

Réservé aux administrateurs du serveur Discord. Les réglages sont rangés
dans `data/config.json` et l'emportent sur le `.env`.

| Commande | Effet |
|---|---|
| `/config voir` | Tous les réglages et les versions installées. |
| `/config serveur nom:… adresse:… cfx:…` | Nom affiché (vide : celui du serveur FiveM), adresse pour F8, code ou lien `cfx.re/join/…` du bouton « Se connecter ». `-` efface une valeur. |
| `/config role type:Staff action:Ajouter role:@…` | Rôles staff : ils voient les salons privés et peuvent utiliser les commandes staff. |
| `/config role type:Lecture … role:@…` | Rôles qui voient les salons publics. Aucun = tout le monde. Pratique pour un serveur qui n'ouvre ses salons qu'après le règlement. |
| `/config services liste:…` | Métiers comptés « en service » sur le panneau : `police=👮 Police, ambulance=🚑 Secours` (8 au plus), ou `défaut`. |
| `/config bienvenue actif:…` | Message de bienvenue aux nouveaux membres. |

Changer des rôles réapplique les permissions des salons du bot. Sinon, un
salon déjà créé n'est **jamais renommé, déplacé ni retouché** : rangez-le et
renommez-le comme vous voulez.

### Le `.env`

Ne contient que ce qui ne peut pas se régler depuis Discord :

| Variable | Rôle |
|---|---|
| `DISCORD_TOKEN` | jeton du bot (secret) |
| `GUILD_ID` | serveur Discord ; vide = adopté à la première invitation |
| `FIVEM_URL` | adresse du serveur FiveM vue du bot (`http://127.0.0.1:30120`) |
| `VESPER_JETON` | même valeur que `vesper_discord_jeton` dans `server.cfg` (secret) |
| `INTERVALLE` | secondes entre deux relevés (15 ; 10 au minimum) |
| `DEPOT_MAJ` | dépôt GitHub des mises à jour (facultatif) |

## 5. Salons et rôles créés

### Catégorie « 📡 *nom du serveur* — SERVEUR »

| Salon | Contenu |
|---|---|
| `📊・statut-serveur` | Panneau en direct + annonces de panne, retour, redémarrage, maintenance. Lecture seule. |
| `📢・mises-à-jour` | Mises à jour publiées par le staff avec `/update`. Lecture seule. |
| `🎮 En jeu : X/48` (vocal) | Compteur de joueurs (on ne peut pas y entrer). |
| `👥 Membres : N` (vocal) | Compteur de membres du Discord. |

### Catégorie « 🛡️ *nom du serveur* — STAFF » (privée)

| Salon | Contenu |
|---|---|
| `📋・logs-joueurs` | Tout ce que font les joueurs côté serveur (§ 8). |
| `🤖・journal-bot` | Démarrages du bot, pannes, ressources lancées ou arrêtées, annonces en jeu, consultations `/id`, réglages modifiés, mises à jour. |
| `🆕・updates-bot` | Nouvelles versions du bot, avec le bouton **Installer** (§ 11). |

### Catégories « LOGS — … » (privées, une par script compatible)

Voir § 10.

### Rôles

| Rôle | Rôle du rôle |
|---|---|
| `🔔 Notif serveur` | Chacun le prend ou le rend avec le bouton 🔔 du panneau. Mentionné au retour du serveur, en fin de maintenance, aux mises à jour. |
| `🎮 En jeu` | Donné automatiquement aux membres connectés en jeu (compte Discord relié à FiveM), retiré à leur départ. Placez-le au-dessus des autres rôles pour qu'il s'affiche à part. |

Le rôle du bot doit rester **au-dessus** de ces deux rôles.

## 6. Commandes

Les réponses marquées « privée » ne sont visibles que de la personne qui
lance la commande.

| Commande | Qui | Ce qu'elle fait |
|---|---|---|
| `/statut` | tous | Affiche le panneau d'état. |
| `/joueurs` | tous | Joueurs en ville (privée). Le staff voit en plus personnage, métier, ping et compte Discord. |
| `/connexion` | tous | Comment rejoindre le serveur. |
| `/id joueur:<…>` | staff | **Fiche complète d'un joueur** (privée), § 7. Bouton **📜 Logs de ce joueur**. |
| `/logs joueur` · `script` · `recherche` | staff | **Retrouver les journaux** d'un joueur, d'un script, ou par mot-clé (privée), § 8 bis. |
| `/update [notifier]` | staff | Formulaire de mise à jour publié dans `📢・mises-à-jour`. Une ligne = une puce. |
| `/annonce-jeu message:<…>` | staff | Écrit dans le tchat **en jeu** de tous les joueurs (400 caractères). Tracé. |
| `/maintenance activer [raison]` / `terminer` | staff | Passe le panneau en 🟠 maintenance, ou l'en sort. |
| `/journaux [resynchroniser] [retirer]` | staff | Journaux des scripts : état, revérification, nettoyage d'un script désinstallé. |
| `/config …` | administrateurs | Réglages, § 4. |
| `/maj verifier` · `/maj etat` | administrateurs | Cherche une nouvelle version ; versions installées et publiées. |
| `/installer` | administrateurs | Recrée les salons et rôles du bot qui manqueraient. |

> ⚠️ Discord ne montre les commandes staff qu'aux membres ayant « Gérer le
> serveur ». Pour d'autres rôles : *Paramètres du serveur → Intégrations →*
> votre bot. Le bot accepte de toute façon les rôles staff de `/config`.

## 7. La fiche joueur : `/id`

### Chercher

L'option `joueur` propose des résultats **pendant la frappe** : joueurs
connectés (🟢) d'abord, puis ceux de la base (⚫). On peut taper l'id en jeu,
un nom de personnage, un pseudo FiveM, la licence (`license:…` ou les 40
caractères), l'identifiant d'un personnage (`char0:…`), ou un compte Discord
(mention ou id, seulement si le joueur est en jeu).

### Contenu

**Carte « compte »** : pseudo, en jeu ou non (id, ping) ou dernière visite,
licence, Discord, temps de jeu, personnages et emplacements, première
connexion relevée, rang staff, **sanctions**.

**Une carte par personnage :**

| Rubrique | Détail | Source |
|---|---|---|
| 🪪 Identité | naissance, sexe, taille, groupe sanguin, téléphone, création | `users`, `phone_phones` |
| 💼 Métier | métier et grade, matricule, groupe ESX, gang | ESX, `vesper_lspd_personnel`, `vesper_gangs_*` |
| 💰 Argent | liquide, banque, argent sale, cartes (4 derniers chiffres), jetons de casino | ESX en direct / `users.accounts`, `bank_cards`, `casino_memberships` |
| ⚖️ Justice | casier (3 dernières entrées), amendes impayées, factures ouvertes, assurances | `vesper_lspd_*`, `vesper_billing_factures`, assurances |
| 🚗 Véhicules | plaque, modèle réel, au garage / sorti / en fourrière | `owned_vehicles` + catalogues |
| 🏠 Propriétés | maisons, locations, motels et dette de loyer | `player_houses`, `qs_motel_rentals` |
| 🎒 Inventaire | chaque objet et sa quantité | qs-inventory en direct / `users.inventory` |

En jeu, argent et inventaire sont lus **en direct** ; hors ligne, c'est la
**dernière sauvegarde**. Une table absente du serveur = rubrique absente.

### Confidentialité

Réponse **privée**, chaque consultation **tracée** dans `🤖・journal-bot`,
carte bancaire jamais en entier, aucune adresse IP. Attention en partage
d'écran : la fiche montre l'argent et l'inventaire.

## 8. Le salon `📋・logs-joueurs`

| | Événement | Affiché |
|---|---|---|
| ➡️ | Connexion | pseudo, id, Discord, licence |
| 🧍 | Personnage chargé ou **créé** | personnage, métier, liquide et banque |
| 💼 | Changement de métier | ancien → nouveau, avec le grade |
| 💀 | Mort | victime, **tueur** si c'est un joueur, cause |
| ⬅️ | Déconnexion | personnage, métier, session, argent au départ, raison, licence |
| 🔄 | Redémarrage ou panne | les joueurs qui étaient en ville |

- Les prises de service n'y sont pas : les scripts de métier les journalisent
  déjà dans leur propre catégorie.
- Un arrêt du serveur emporte la ressource : les départs sont alors regroupés
  par le bot dans un message 🔄 au redémarrage.
- La mort est signalée par le jeu du joueur (`esx:onPlayerDeath`) : fiable
  pour un journal, pas une preuve. Limitée à une toutes les 10 s par joueur.
- Décalage de 15 s au plus ; rien n'est perdu entre deux relevés.

## 8 bis. Retrouver un journal : `/logs`

Tout journal envoyé sur Discord par un script (et tout événement de
`📋・logs-joueurs`) est **aussi rangé en base** par la ressource, rattaché
aux joueurs qu'il cite et au message Discord d'origine. Le staff le retrouve
sans fouiller cent salons.

| Commande | Ce qu'elle montre |
|---|---|
| `/logs joueur joueur:… [script] [periode] [texte]` | Tout ce qui a été journalisé sur ce joueur, tous scripts confondus, et un résumé **« où apparaît ce joueur »** (nombre de journaux et dernier en date, script par script). |
| `/logs script script:… [sujet] [periode] [texte]` | Les derniers journaux d'un script, ou d'un seul de ses salons. |
| `/logs recherche texte:… [script] [periode]` | Un mot, une plaque, un montant, un nom, dans tous les journaux. |

- Résultats du plus récent au plus ancien, 8 par page (◀️ ▶️), chacun avec
  un lien **voir le message** vers le journal d'origine.
- **📄 Exporter en fichier** : les 500 journaux les plus récents de la
  recherche, en texte, pour un dossier de sanction ou un rapport.
- Sur la fiche `/id`, le bouton **📜 Logs de ce joueur** ouvre la même vue.
- Réponses privées ; chaque consultation et exportation est tracée dans
  `🤖・journal-bot`.

**Comment un journal est rattaché à un joueur.** Les scripts écrivent déjà
qui est concerné : identifiant du personnage (`char0:…`), licence
(`license:…`), ou id en jeu entre accents graves (`` `#12` ``, traduit en
licence si le joueur est connecté). La ressource en tire la licence : **aucun
script n'a besoin d'être modifié**. Un journal qui ne cite personne reste
trouvable par script, salon et texte.

**Conservation.** 30 jours par défaut, réglable dans `server.cfg` :
`set vesper_discord_historique_jours 60` (0 = sans limite). Les journaux
plus anciens sont effacés toutes les 6 heures. Tables
`vesper_discord_journaux` et `vesper_discord_journaux_joueurs`, créées
toutes seules au démarrage de la ressource.

## 9. Le panneau de statut

Un seul message, réécrit seulement quand quelque chose change, et reposé en
dernier après chaque annonce. 🟢 en ligne · 🟠 maintenance · 🔴 hors ligne
(3 relevés manqués, ≈ 45 s).

Il affiche joueurs et jauge, durée depuis le démarrage, pic du jour et
record, qui est **en service** (métiers de `/config services`), la liste des
joueurs en ville et la façon de se connecter. Boutons : 🎮 Se connecter,
👥 Joueurs, 🔔 Notifications. Les compteurs vocaux changent au plus une fois
toutes les 5 minutes (limite Discord : 2 renommages par 10 minutes).

## 10. Les journaux des scripts

Un script compatible se **déclare** à la ressource ; le bot crée une
catégorie « LOGS — … » réservée au staff, un salon et un webhook par sujet.
Un serveur ne reçoit que les journaux des scripts qu'il fait tourner ; un
script arrêté garde ses salons ; `/journaux retirer` nettoie ceux d'un script
désinstallé. Guide du développeur : [`journaux.md`](journaux.md).

## 11. Mises à jour

### Ce qui se passe

1. Toutes les **6 heures** (et avec `/maj verifier`), le bot consulte la
   dernière version publiée sur GitHub.
2. Si elle est plus récente, il l'annonce **une fois** dans `🆕・updates-bot` :
   notes de version, versions installées, boutons **Installer** et
   **Voir sur GitHub**.
3. Un **administrateur** clique sur **Installer**. Le message suit
   l'avancement :
   - téléchargement de l'archive et **vérification de son empreinte SHA-256** ;
   - **ressource FiveM** : si sa version change, le bot lui envoie les
     nouveaux fichiers ; elle **vérifie que chaque fichier Lua compile**
     avant d'écrire quoi que ce soit, garde l'ancienne version à côté
     (`*.avant-maj-<version>`), puis fait `refresh` et redémarre ;
   - dépendances réinstallées si elles ont changé (dans un dossier de travail :
     un échec ne touche à rien) ;
   - **sauvegarde du code actuel** dans `data/sauvegardes/<version>/`, puis
     remplacement ;
   - redémarrage du bot sur la nouvelle version.
4. Au démarrage suivant, le message passe à **✅ Version X installée**.

### Si la ressource n'a pas le droit de se recharger

Sans les quatre lignes `add_ace … command.refresh`, `restart`, `stop` et `start` (§ 3),
l'annonce le signale en ⚠️ avec les lignes à ajouter, et l'installation
s'arrête **avant d'écrire quoi que ce soit** : ni la ressource ni le bot ne
sont touchés.

### Si la nouvelle version plante

Le service ne lance pas le bot directement mais `lanceur.js`. Si la nouvelle
version s'arrête avant d'être prête, le lanceur **remet automatiquement la
version sauvegardée** et la relance ; le bot annonce alors
« ❌ La version X plantait au démarrage : retour automatique à Y ».

En cas d'échec avant le remplacement (téléchargement, empreinte, ressource
qui ne revient pas), rien n'est remplacé côté bot : le message l'indique et
le bouton redevient cliquable.

### Ce que la mise à jour ne touche jamais

`.env`, `data/` (réglages, salons, webhooks, sauvegardes) et `lanceur.js`
tant qu'il n'a pas changé.

### Première installation d'une ressource sans `/maj`

Les ressources antérieures à la 1.3.0 ne savent pas se mettre à jour
seules : copiez une fois `vesper-discord/` à la main, puis `refresh` et
`restart vesper-discord`. Ensuite, tout passe par le bouton.

## 12. Cohabiter avec d'autres bots

- Le bot ne gère **que ce qui se passe en jeu** : pas de journal des messages
  ou des membres Discord, pas de tickets, pas d'automod. Gardez votre bot de
  modération pour cela.
- Un autre bot accueille déjà vos membres ? Laissez `/config bienvenue` coupé.
- Un autre bot affiche déjà le statut FiveM ? Coupez l'un des deux.
- ⚠️ **Les anti-raid qui expulsent les comptes récents** peuvent éjecter le
  bot à la seconde où vous l'invitez (son compte vient d'être créé), sans
  trace visible. Ajoutez-le en exception ou désactivez la règle le temps de
  l'invitation.

## 13. Sécurité

- La ressource n'accepte que **127.0.0.1** et le **jeton** du pont.
- Le jeton du pont est déclaré avec `set` (privé), jamais `sets`.
- Le `.env` est en droits 600 ; le service tourne sous un utilisateur dédié,
  sans privilèges, limité à son propre dossier.
- Mises à jour : archive vérifiée par **SHA-256**, Lua vérifié avant
  écriture, sauvegarde avant remplacement, installation réservée aux
  **administrateurs**, tout est tracé dans `🤖・journal-bot`.
- Requêtes SQL paramétrées ; `/id`, `/annonce-jeu` et les réglages sont
  tracés.
- Jamais dans le dépôt : `.env`, `data/`.

## 14. Dépannage

| Symptôme | Cause probable et remède |
|---|---|
| Le bot rejoint puis disparaît aussitôt | Un anti-raid l'expulse (compte récent) : voir § 12. |
| Le bot ne crée rien après l'invitation | `journalctl -u vesper-discord-bot -f` : il indique s'il attend une invitation ou s'il est sur plusieurs serveurs (fixer `GUILD_ID`). |
| `📋・logs-joueurs` reste vide | Personne ne s'est connecté ni déconnecté depuis. |
| `/id` : « Le serveur n'a pas répondu » | Ressource arrêtée ou serveur hors ligne : `ensure vesper-discord`. |
| Le panneau est rouge alors que le serveur tourne | `FIVEM_URL` incorrecte, ou ressource absente et `/dynamic.json` injoignable. |
| Commandes staff invisibles | Permission « Gérer le serveur » manquante : *Intégrations*. |
| Compteurs figés | Limite Discord de 2 renommages par 10 minutes : rattrapé en 5 minutes au plus. |
| Une mise à jour échoue sur « la ressource n'est pas revenue » | Console du serveur FiveM ; les anciens fichiers sont dans `*.avant-maj-*`. |
| Une modification de la ressource à la main n'a aucun effet | Fichier ajouté au manifeste sans `refresh` : `refresh` puis `restart vesper-discord`. |

Changer le jeton du bot : portail Discord → *Bot* → *Reset Token*, remplacer
`DISCORD_TOKEN` dans le `.env`, `systemctl restart vesper-discord-bot`.

## 15. Référence : points d'accès de la ressource

Sous `http://127.0.0.1:30120/vesper-discord/`, en-tête `X-Vesper-Jeton`.
Sans le bon jeton ou hors de la machine : `403`.

| Méthode et chemin | Réponse |
|---|---|
| `GET /etat?depuis=N` | `nom`, `version`, `max`, `en_ligne_depuis`, `ressources[]`, `joueurs[]`, `evenements[]` (après `N`), `dernier`, `modules[]` |
| `GET /recherche?q=…` | `{ resultats: [{ label, valeur }] }`, 25 au plus |
| `GET /fiche?q=…` | la fiche, `{ candidats }` si ambigu, ou `404` |
| `GET /historique?licence=&ressource=&sujet=&texte=&depuis=&limite=&decalage=&complet=` | `{ total, lignes: [{ id, quand, ressource, sujet, titre, texte, salon, message }] }` (500 au plus) |
| `GET /historique/resume?licence=…` | `{ sujets: [{ ressource, sujet, n, premier, dernier }], conservation }` |
| `POST /annonce` | `{ message, auteur }` → tchat en jeu |
| `POST /webhooks` | `{ id, webhooks }` : webhooks d'un script, envoyés par le bot |
| `POST /maj` | `{ version, fichiers: { "nom.lua": contenu } }` : vérifie, sauvegarde, écrit, `refresh`, redémarre |

Événements de `/etat` : `arrivee`, `personnage`, `metier`, `mort`, `depart`
(`redemarrage` est fabriqué par le bot).

Tester la mise en forme sans rien envoyer : `node bot/tests/mise-en-forme.js fiche.json`.
