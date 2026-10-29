# Changements

Chaque section ci-dessous devient la note de la version publiée, affichée
par le bot dans son salon 🆕・updates-bot.

## [1.7.0]

**Historique des objets d'un joueur : `/inventaire historique`.**

- 🎒 Chaque objet **gagné ou perdu** par les personnages d'une licence, du plus récent au plus ancien : quantité, ce qui reste ensuite, le personnage, et la **raison**. Par exemple : utilisé, donné à…, reçu de…, déposé dans le coffre de véhicule AB123CD, achat, fabrication, fouille, admin, ou « par le script X ».
- Filtres : un objet, une période, un mot de la raison. Pages de 15, et **📄 Exporter en fichier** jusqu'à 1000 mouvements, pour un dossier ou un remboursement.
- Il faut **vesper-inventory 1.6.0 ou plus**, qui range ces mouvements. La ressource FiveM passe en 1.6.0.

## [1.6.1]

- `/inventaire objet` et la recherche de `/inventaire coffre` trouvent de nouveau les noms qui contiennent un `_` (« water_bottle », « gang_ballas ») : ce caractère était retiré au lieu d'être protégé dans la requête.

## [1.6.0]

**Coffres et objets : `/inventaire`.**

- 🗄️ **`/inventaire coffre`** : le contenu d'un coffre, d'un coffre de véhicule ou d'une boîte à gants, avec le propriétaire du véhicule. La recherche propose les plaques et les noms de coffres.
- 📦 **`/inventaire objet`** : qui détient un objet, et combien. Les joueurs connectés sont lus en direct, puis viennent les personnages hors ligne, les coffres et les véhicules. C'est l'outil pour repérer une duplication.
- 📜 Bouton **Historique de ce coffre** (ou **Logs de cet objet**) : la recherche `/logs` sur la plaque, le coffre ou l'objet.
- La ressource FiveM passe en 1.5.0 (nouveau fichier `inventaire.lua`) et se met à jour avec le bot.

## [1.5.2]

- La ressource annonce la version du code **réellement chargé** : un `refresh` relit le manifeste sans recharger le code, et l'installation pouvait se croire terminée alors que l'ancien code tournait encore.
- Il faut **quatre** droits pour qu'elle se recharge seule, et non deux : `restart` relance lui-même `stop` puis `start`. Ajoutez dans `server.cfg` :
  `add_ace resource.vesper-discord command.stop allow` et `add_ace resource.vesper-discord command.start allow`. L'annonce d'une mise à jour les indique s'ils manquent.

## [1.5.1]

**Mises à jour plus sûres pour la ressource FiveM.**

- La ressource vérifie qu'elle a le droit de se recharger **avant** d'écrire ses nouveaux fichiers. Sans les deux lignes `add_ace resource.vesper-discord command.refresh allow` et `… command.restart allow` dans `server.cfg`, l'installation s'arrête proprement au lieu de laisser une ressource à moitié mise à jour.
- L'annonce d'une nouvelle version dans 🆕・updates-bot indique ces lignes s'il en manque.
- Les refus de la ressource s'affichent avec leur vraie raison au lieu de « HTTP 400 ».
- `install.sh` et la documentation donnent les deux lignes dès l'installation.

## [1.5.0]

**Les journaux deviennent consultables : `/logs`.**

- 📜 **`/logs joueur`** : tout ce que les scripts ont journalisé sur un joueur, du plus récent au plus ancien, avec un résumé « où apparaît ce joueur » (script par script). Filtres : script, période, texte.
- 🔎 **`/logs recherche`** : un mot, une plaque, un montant, dans tous les journaux de tous les scripts.
- 🗂️ **`/logs script`** : les derniers journaux d'un script, ou d'un seul de ses salons.
- Chaque résultat a un lien **voir le message** vers le journal d'origine dans son salon, et un bouton **Exporter en fichier** (500 journaux au plus).
- Bouton **📜 Logs de ce joueur** directement sur la fiche `/id`.
- Toutes les consultations et exportations sont tracées dans 🤖・journal-bot.
- Ressource FiveM 1.4.0 : chaque journal envoyé est aussi rangé en base (table `vesper_discord_journaux`), rattaché aux joueurs qu'il cite — **aucun script n'a besoin d'être modifié**. Conservation : 30 jours (`set vesper_discord_historique_jours`).

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
