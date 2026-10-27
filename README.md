# Bot Discord VESPER

Deux pièces qui travaillent ensemble :

| Dossier | Quoi | Où ça tourne |
|---|---|---|
| `bot/` | le bot Discord (Node.js 18+, discord.js 14) | un service à part (systemd) |
| `vesper-discord/` | la ressource FiveM, pont entre le serveur et le bot | `resources/[standalone]/vesper-discord` |

## Ce qu'il fait

- **Statut en direct** : panneau dans `📊・statut-serveur` (joueurs, services
  en ligne, pic du jour, record), compteurs en salons vocaux, présence du bot,
  annonces de panne, de retour et de redémarrage, rôle « 🎮 En jeu ».
- **Staff** : connexions et départs des joueurs, ressources lancées ou
  arrêtées, journal du bot.
- **Commandes** : `/statut`, `/joueurs`, `/connexion`, `/update` (mise à jour
  dans `📢・mises-à-jour`), `/annonce-jeu`, `/maintenance`, `/installer`,
  `/journaux`.
- **Journaux des scripts** : un script compatible (ex. `vesper-lspd`) se
  déclare à la ressource ; le bot crée **tout seul** sa catégorie
  « LOGS — … » réservée au staff, un salon par sujet et leurs webhooks.
  Voir [`docs/journaux.md`](docs/journaux.md).

## Installation

### La ressource FiveM

1. Copier `vesper-discord/` dans `resources/[standalone]/`.
2. Dans `server.cfg` :
   ```cfg
   set vesper_discord_jeton "un-long-jeton-aleatoire"
   ensure vesper-discord
   ```
   ⚠️ `set`, jamais `sets` : un `sets` est publié dans la liste des serveurs.
3. Le point d'entrée HTTP (`/vesper-discord/…`) n'accepte que **127.0.0.1**
   et ce jeton : le bot doit tourner sur la même machine.

### Le bot

```bash
cd bot
npm ci --omit=dev
cp .env.example .env && chmod 600 .env   # puis remplir
node src/index.js
```

En service : `bot/deploy/vesper-discord-bot.service` (utilisateur dédié
`vesperbot`, `/opt/vesper-discord-bot`, écriture limitée à `data/`).

Permissions Discord du bot : gérer les salons, gérer les rôles, **gérer les
webhooks**, envoyer des messages, intégrer des liens, lire l'historique.

## Mettre à jour (VESPER)

1. Sauvegarde : `tar` de la ressource dans `sauvegardes-code/` et du bot
   dans `/opt/vesper-discord-bot-sauvegardes/`.
2. Copier les fichiers, `chown`, `luac5.4 -p` / `node --check`.
3. Ressource : `refresh` puis `restart vesper-discord` (les webhooks sont en
   KVP, ils survivent). Bot : `systemctl restart vesper-discord-bot`.

## Secrets

Le `.env`, `data/etat.json` (il contient les identifiants des webhooks) et
les webhooks eux-mêmes ne sont **jamais** dans ce dépôt.
