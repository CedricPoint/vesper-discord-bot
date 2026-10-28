# Changements

Chaque section ci-dessous devient la note de la version publiée, affichée
par le bot dans son salon 🆕・updates-bot.

## [1.4.0]

**Mises à jour en un clic et installation pour n'importe quel serveur.**

- 🆕 Nouveau salon **🆕・updates-bot** (staff) : le bot y annonce chaque nouvelle version, avec un bouton **Installer** réservé aux administrateurs.
- ⬇️ L'installation télécharge la version, vérifie son empreinte, met à jour la ressource FiveM puis le bot, et redémarre. **Sauvegarde automatique** avant, et **retour arrière automatique** si la nouvelle version plante au démarrage.
- ⚙️ `/config` : nom affiché, adresse F8, bouton « Se connecter », rôles staff, rôles qui voient les salons publics, métiers « en service », bienvenue — sans toucher au serveur.
- `/maj verifier` et `/maj etat` : versions installées et dernière version publiée.
- Plus rien de propre à un serveur dans le code : le nom vient du serveur FiveM, et le bot adopte le serveur Discord où on l'invite.
- `install.sh` : installation complète en une commande sur Linux.
- Ressource FiveM 1.3.0 : se met à jour elle-même à la demande du bot (fichiers vérifiés avant écriture, anciennes versions gardées).

## [1.3.0]

- `/id` : fiche complète d'un joueur avec recherche pendant la frappe (argent, inventaire, véhicules, propriétés, casier, factures, assurances).
- Salon **📋・logs-joueurs** : personnage chargé ou créé, changement de métier, mort (tueur, cause), argent au départ, joueurs déconnectés par un redémarrage.

## [1.2.0]

- `/journaux retirer` : supprime les salons de journaux d'un script désinstallé.

## [1.1.0]

- Journaux des scripts : un script se déclare, le bot crée sa catégorie, ses salons et ses webhooks.

## [1.0.0]

- Panneau de statut en direct, compteurs, rôles 🎮 En jeu et 🔔 Notif serveur, journal des connexions, `/update`, `/annonce-jeu`, `/maintenance`.
