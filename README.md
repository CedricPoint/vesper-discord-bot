# Bot VESPER — bot Discord pour serveur FiveM

Un bot Discord qui relie votre serveur **FiveM (ESX)** à votre Discord, et
qui **s'installe, se règle et se met à jour tout seul**.

📘 **Documentation complète : [`docs/DOCUMENTATION.md`](docs/DOCUMENTATION.md)**
· Changements : [`CHANGELOG.md`](CHANGELOG.md) · Licence MIT, gratuit.

## Ce qu'il fait

- **Statut en direct** : panneau dans `📊・statut-serveur` (joueurs, qui est en
  service, pic du jour, record, bouton « Se connecter »), compteurs en salons
  vocaux, annonces de panne, de retour et de redémarrage, rôle « 🎮 En jeu ».
- **Staff** : salon `📋・logs-joueurs` (connexions, départs, personnages,
  métiers, morts, redémarrages) et **fiche complète d'un joueur avec `/id`**
  (argent, inventaire, véhicules, propriétés, casier…).
- **Commandes** : `/statut`, `/joueurs`, `/connexion`, `/id`, `/update`,
  `/annonce-jeu`, `/maintenance`, `/journaux`, `/config`, `/maj`, `/installer`.
- **Journaux des scripts** : un script compatible se déclare, le bot crée sa
  catégorie « LOGS — … », ses salons et ses webhooks
  ([`docs/journaux.md`](docs/journaux.md)).
- **Mises à jour en un clic** : chaque nouvelle version est annoncée dans
  `🆕・updates-bot` avec un bouton **Installer** pour les administrateurs.
  Sauvegarde avant, retour arrière automatique si elle plante.

## Installer (Linux, 5 minutes)

**Il faut** : une machine Linux avec systemd, **Node.js 18.17+**, sur la
**même machine** que le serveur FiveM, avec ESX et oxmysql côté serveur.

1. **Créer l'application Discord** sur
   [discord.com/developers/applications](https://discord.com/developers/applications) :
   *New Application* → onglet *Bot* → *Reset Token* (copiez-le).
2. **Lancer l'installation** :
   ```bash
   curl -fsSL https://raw.githubusercontent.com/CedricPoint/vesper-discord-bot/main/install.sh | sudo bash
   ```
   Le script demande le jeton, installe le bot en service, copie la ressource
   FiveM si vous lui donnez votre dossier `resources`, et affiche la suite.
3. **Dans `server.cfg`**, ajouter les deux lignes affichées :
   ```cfg
   set vesper_discord_jeton "…"
   ensure vesper-discord
   ```
4. **Inviter le bot** avec le lien affiché. Il adopte ce serveur Discord,
   crée ses salons et ses rôles.
5. **Régler** depuis Discord avec `/config` : nom affiché, adresse F8,
   rôles staff, rôles qui voient les salons publics, métiers « en service ».

## Mettre à jour

Rien à faire : le bot vérifie toutes les 6 heures et annonce la nouvelle
version dans `🆕・updates-bot`. Un administrateur clique sur **Installer**.
`/maj verifier` force la vérification.

## Ce qui ne sera jamais dans ce dépôt

Le `.env` (jeton du bot, jeton du pont), `data/` (réglages, salons,
webhooks). Le pont FiveM n'accepte que **127.0.0.1** et son jeton.

## Publier une version (mainteneur)

1. Section `## [X.Y.Z]` dans `CHANGELOG.md`, version dans
   `bot/package.json` (et `vesper-discord/fxmanifest.lua` si la ressource
   change).
2. `git tag vX.Y.Z && git push --tags` : l'action GitHub fabrique l'archive,
   son empreinte SHA-256 et la version. Les bots installés l'annoncent au
   relevé suivant.
