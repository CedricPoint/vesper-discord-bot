// Bot Discord de VESPER RP.
//
// Il crée et tient seul ses salons : panneau de statut en direct, compteurs
// de joueurs et de membres, mises à jour, journaux du staff. Il interroge
// la ressource FiveM `vesper-discord` (noms, métiers, connexions) et se
// rabat sur /dynamic.json si elle ne répond pas.
//
// LES JOURNAUX DES SCRIPTS : un script (vesper-lspd…) se déclare auprès de
// la ressource ; au relevé suivant, le bot crée sa catégorie réservée au
// staff, un salon par sujet et un webhook par salon, et renvoie les
// webhooks à la ressource, qui poste. Aucune configuration à la main.
//
// ⚠️ UN SEUL SERVEUR DISCORD : il quitte tout autre serveur où on l'invite.

'use strict';

const fs = require('fs');
const path = require('path');
const {
  ActionRowBuilder, ActivityType, ButtonBuilder, ButtonStyle, ChannelType,
  Client, EmbedBuilder, Events, GatewayIntentBits, ModalBuilder,
  PermissionFlagsBits, REST, Routes, SlashCommandBuilder, TextInputBuilder,
  TextInputStyle,
} = require('discord.js');

const VERSION = require('../package.json').version;

// ── Configuration ────────────────────────────────────────────────────────

// Lu à la main pour un lancement hors systemd (qui, lui, passe par
// EnvironmentFile). Les variables déjà posées gagnent.
(function lireEnv() {
  const fichier = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(fichier)) return;
  for (const ligne of fs.readFileSync(fichier, 'utf8').split(/\r?\n/)) {
    const m = ligne.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^"(.*)"$/, '$1');
  }
})();

const CFG = {
  token: process.env.DISCORD_TOKEN,
  guildId: process.env.GUILD_ID || '1563713516920250420',
  fivem: (process.env.FIVEM_URL || 'http://127.0.0.1:30120').replace(/\/$/, ''),
  jeton: process.env.VESPER_JETON || '',
  adresse: process.env.ADRESSE_CONNEXION || '92.112.194.115:30120',
  cfxJoin: (process.env.CFX_JOIN || '').trim(),
  staffRoles: (process.env.STAFF_ROLE_IDS || '').split(',').map((s) => s.trim()).filter(Boolean),
  rolesLecture: (process.env.ROLES_LECTURE || '').split(',').map((s) => s.trim()).filter(Boolean),
  // Désactivé quand un autre bot (Toastie) accueille déjà les arrivants.
  bienvenue: process.env.BIENVENUE === '1',
  intervalle: Math.max(10, Number(process.env.INTERVALLE) || 15) * 1000,
};

if (!CFG.token) {
  console.error('DISCORD_TOKEN manquant (.env)');
  process.exit(1);
}

const COULEUR = { marque: 0x7c6cf5, ok: 0x22c55e, ko: 0xef4444, maintenance: 0xf59e0b, info: 0x4da6ff };

// Métiers mis en avant sur le panneau, dans cet ordre.
const SERVICES = [
  { metier: 'police', emoji: '👮', nom: 'Police' },
  { metier: 'ambulance', emoji: '🚑', nom: 'Secours' },
  { metier: 'mechanic', emoji: '🔧', nom: 'Mécanos' },
  { metier: 'taxi', emoji: '🚕', nom: 'Taxis' },
  { metier: 'realestate', emoji: '🏠', nom: 'Immobilier' },
];

// Trois relevés manqués (≈ 45 s) avant de déclarer le serveur hors ligne :
// un relevé perdu pendant un pic de charge ne doit pas alerter tout le monde.
const ECHECS_AVANT_HORS_LIGNE = 3;
// Discord n'autorise que 2 renommages de salon par 10 minutes.
const DELAI_RENOMMAGE = 5 * 60 * 1000 + 15 * 1000;

// ── État persistant ──────────────────────────────────────────────────────

const FICHIER_ETAT = path.join(__dirname, '..', 'data', 'etat.json');

function chargerEtat() {
  try {
    return JSON.parse(fs.readFileSync(FICHIER_ETAT, 'utf8'));
  } catch {
    return {};
  }
}

const etat = Object.assign({
  salons: {},        // clé → id de salon
  roles: {},         // clé → id de rôle
  panneau: null,     // id du message de statut
  dernierEvt: null,  // dernier événement FiveM traité
  ressources: null,  // ressources lancées au dernier relevé
  picJour: { jour: null, valeur: 0 },
  record: { valeur: 0, date: null },
  enJeu: [],         // ids Discord à qui on a donné le rôle « En jeu »
  maintenance: null, // { raison, depuis } ou null
  // Journaux des scripts : id de ressource → { titre, signature, roles,
  // categorie, salons: { sujet → { salon, webhook } } }.
  modules: {},
}, chargerEtat());

function sauver() {
  fs.mkdirSync(path.dirname(FICHIER_ETAT), { recursive: true });
  const tmp = FICHIER_ETAT + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(etat, null, 2));
  fs.renameSync(tmp, FICHIER_ETAT);
}

// ── Petits outils ────────────────────────────────────────────────────────

function duree(secondes) {
  const s = Math.max(0, Math.floor(secondes));
  const j = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (j) return `${j} j ${h} h`;
  if (h) return `${h} h ${String(m).padStart(2, '0')}`;
  if (m) return `${m} min`;
  return `${s} s`;
}

function argent(n) {
  return n == null ? '?' : `${Math.round(Number(n)).toLocaleString('fr-FR')} $`;
}

// oxmysql rend les dates en millisecondes, nos tables en secondes, et
// certaines colonnes en texte : tout devient un horodatage Discord.
function quand(v, style = 'f') {
  if (v == null || v === '') return null;
  let s = typeof v === 'number' ? v : (/^\d+$/.test(String(v)) ? Number(v) : Date.parse(String(v)) / 1000);
  if (!Number.isFinite(s)) return String(v);
  if (s > 1e11) s /= 1000;
  return ts(s, style);
}

const liste = (x) => (Array.isArray(x) ? x : Object.values(x || {}));

function barre(n, max, cases = 8) {
  const plein = max ? Math.round((n / max) * cases) : 0;
  return '▰'.repeat(Math.min(cases, plein)) + '▱'.repeat(Math.max(0, cases - plein));
}

function echapper(texte, max = 64) {
  return String(texte ?? '').slice(0, max).replace(/([*_`~|>\\])/g, '\\$1');
}

function jourParis(date = new Date()) {
  return date.toLocaleDateString('fr-CA', { timeZone: 'Europe/Paris' });
}

const ts = (secondes, style = 'R') => `<t:${Math.floor(secondes)}:${style}>`;
const maintenant = () => Math.floor(Date.now() / 1000);

// ── Relevé du serveur FiveM ──────────────────────────────────────────────

async function recuperer(chemin, options = {}) {
  const res = await fetch(CFG.fivem + chemin, {
    ...options,
    headers: { 'X-Vesper-Jeton': CFG.jeton, 'Content-Type': 'application/json', ...(options.headers || {}) },
    signal: AbortSignal.timeout(6000),
  });
  if (!res.ok) {
    const err = new Error(`HTTP ${res.status} sur ${chemin}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

// Rend { enLigne, complet, joueurs, max, enLigneDepuis, ressources, evenements, dernier }.
async function releve() {
  try {
    const depuis = etat.dernierEvt ?? 0;
    const d = await recuperer(`/vesper-discord/etat?depuis=${depuis}`);
    return {
      enLigne: true, complet: true, max: d.max, joueurs: d.joueurs || [],
      enLigneDepuis: d.en_ligne_depuis, ressources: d.ressources || [],
      evenements: d.evenements || [], dernier: d.dernier ?? 0,
      modules: Array.isArray(d.modules) ? d.modules : null,
    };
  } catch (err) {
    // La ressource peut être arrêtée alors que le serveur tourne : on garde
    // au moins le nombre de joueurs.
    const dyn = await recuperer('/dynamic.json');
    return {
      enLigne: true, complet: false, max: Number(dyn.sv_maxclients) || 48,
      joueurs: Array.from({ length: Number(dyn.clients) || 0 }, (_, i) => ({ id: i, nom: 'Joueur' })),
      enLigneDepuis: null, ressources: null, evenements: [], dernier: null, raison: err.message,
    };
  }
}

// ── Discord ──────────────────────────────────────────────────────────────

let client = null;
let guilde = null;
let dernier = null;          // dernier relevé réussi
let statut = 'inconnu';      // 'en_ligne' | 'hors_ligne' | 'inconnu'
let echecs = 0;
let hashPanneau = null;
const renommages = new Map(); // id salon → horodatage du dernier renommage

function estStaff(interaction) {
  if (interaction.memberPermissions?.has(PermissionFlagsBits.ManageGuild)) return true;
  const roles = interaction.member?.roles?.cache;
  return Boolean(roles && CFG.staffRoles.some((id) => roles.has(id)));
}

function salon(cle) {
  const id = etat.salons[cle];
  return id ? guilde?.channels.cache.get(id) || null : null;
}

async function journal(texte) {
  console.log('[journal]', texte.replace(/\n/g, ' | '));
  const s = salon('journal');
  if (s) await s.send({ content: texte.slice(0, 1900), allowedMentions: { parse: [] } }).catch(() => {});
}

// ── Installation : salons, rôles ─────────────────────────────────────────

const LECTURE_SEULE = [
  PermissionFlagsBits.SendMessages, PermissionFlagsBits.SendMessagesInThreads,
  PermissionFlagsBits.CreatePublicThreads, PermissionFlagsBits.CreatePrivateThreads,
  PermissionFlagsBits.AddReactions,
];

async function assurerRole(cle, options) {
  const existant = etat.roles[cle] && (await guilde.roles.fetch(etat.roles[cle]).catch(() => null));
  if (existant) return existant;
  const role = guilde.roles.cache.find((r) => r.name === options.name)
    || (await guilde.roles.create({ ...options, reason: 'Bot VESPER : installation' }));
  etat.roles[cle] = role.id;
  return role;
}

// Un salon déjà connu n'est jamais renommé ni déplacé : si le staff le
// range ailleurs ou change son nom, c'est voulu. Ses permissions ne sont
// réécrites que si la configuration des rôles (.env) a changé depuis la
// dernière installation — pas à chaque démarrage.
async function assurerSalon(cle, options, reappliquer, ancienNom) {
  const existant = etat.salons[cle] && (await guilde.channels.fetch(etat.salons[cle]).catch(() => null));
  if (existant) {
    // Un salon que le bot a lui-même renommé d'une version à l'autre : on
    // ne touche qu'au nom d'origine, jamais à un nom choisi par le staff.
    if (ancienNom && existant.name === ancienNom) {
      await existant.edit({ name: options.name, topic: options.topic, reason: 'Bot VESPER : salon renommé' })
        .catch((e) => console.error('renommage', cle, e.message));
    }
    if (reappliquer && options.permissionOverwrites) {
      await existant.permissionOverwrites.set(options.permissionOverwrites, 'Bot VESPER : rôles reconfigurés')
        .catch((e) => console.error('permissions', cle, e.message));
    }
    return existant;
  }
  const cree = await guilde.channels.create({ ...options, reason: 'Bot VESPER : installation' });
  etat.salons[cle] = cree.id;
  return cree;
}

// Réservé au staff : caché à @everyone, lisible par STAFF_ROLE_IDS, et le
// bot y gère ses webhooks.
function permissionsStaff() {
  return [
    { id: guilde.roles.everyone.id, deny: [PermissionFlagsBits.ViewChannel] },
    { id: client.user.id, allow: [PermissionFlagsBits.ViewChannel, PermissionFlagsBits.SendMessages, PermissionFlagsBits.EmbedLinks,
      PermissionFlagsBits.ReadMessageHistory, PermissionFlagsBits.ManageWebhooks, PermissionFlagsBits.ManageChannels] },
    ...CFG.staffRoles.map((id) => ({
      id, allow: [PermissionFlagsBits.ViewChannel, PermissionFlagsBits.ReadMessageHistory],
      deny: [PermissionFlagsBits.SendMessages],
    })),
  ];
}

async function installer() {
  const tous = guilde.roles.everyone.id;
  const moi = client.user.id;
  const signature = JSON.stringify({ lecture: CFG.rolesLecture, staff: CFG.staffRoles });
  const reappliquer = etat.signatureRoles !== signature;

  const staffAutorise = CFG.staffRoles.map((id) => ({
    id, allow: [PermissionFlagsBits.ViewChannel, PermissionFlagsBits.ReadMessageHistory],
  }));
  // Sans ROLES_LECTURE, les salons publics sont ouverts à tous. Avec, ils
  // suivent le serveur : cachés à @everyone tant que le règlement n'est pas
  // accepté, visibles des rôles listés et du staff.
  const lecteurs = [...new Set([...CFG.rolesLecture, ...CFG.staffRoles])];
  const filtre = lecteurs.length > 0;

  await assurerRole('notif', {
    name: '🔔 Notif serveur', color: COULEUR.info, mentionable: false,
  });
  await assurerRole('enJeu', {
    name: '🎮 En jeu', color: COULEUR.ok, hoist: true, mentionable: false,
  });

  const publique = await assurerSalon('categorie', {
    name: '📡 VESPER RP — SERVEUR', type: ChannelType.GuildCategory, position: 0,
  });

  const vue = [PermissionFlagsBits.ViewChannel];
  const ouverts = filtre
    ? [{ id: tous, deny: vue }, ...lecteurs.map((id) => ({ id, allow: vue, deny: [PermissionFlagsBits.Connect] }))]
    : [{ id: tous, allow: vue, deny: [PermissionFlagsBits.Connect] }];
  const compteur = [
    ...ouverts,
    { id: moi, allow: [PermissionFlagsBits.ViewChannel, PermissionFlagsBits.ManageChannels, PermissionFlagsBits.Connect] },
  ];
  await assurerSalon('compteurJoueurs', {
    name: '🎮 En jeu : …', type: ChannelType.GuildVoice, parent: publique.id, permissionOverwrites: compteur,
  }, reappliquer);
  await assurerSalon('compteurMembres', {
    name: '👥 Membres : …', type: ChannelType.GuildVoice, parent: publique.id, permissionOverwrites: compteur,
  }, reappliquer);

  const lire = [PermissionFlagsBits.ViewChannel, PermissionFlagsBits.ReadMessageHistory];
  const lectureSeule = [
    ...(filtre
      ? [{ id: tous, deny: [...vue, ...LECTURE_SEULE] }, ...lecteurs.map((id) => ({ id, allow: lire, deny: LECTURE_SEULE }))]
      : [{ id: tous, allow: lire, deny: LECTURE_SEULE }]),
    { id: moi, allow: [PermissionFlagsBits.ViewChannel, PermissionFlagsBits.SendMessages, PermissionFlagsBits.EmbedLinks,
      PermissionFlagsBits.AttachFiles, PermissionFlagsBits.ManageMessages, PermissionFlagsBits.ReadMessageHistory,
      PermissionFlagsBits.MentionEveryone] },
  ];
  await assurerSalon('statut', {
    name: '📊・statut-serveur', type: ChannelType.GuildText, parent: publique.id,
    topic: 'État du serveur VESPER RP en direct — mis à jour automatiquement.', permissionOverwrites: lectureSeule,
  }, reappliquer);
  await assurerSalon('majs', {
    name: '📢・mises-à-jour', type: ChannelType.GuildText, parent: publique.id,
    topic: 'Nouveautés et correctifs du serveur VESPER RP.', permissionOverwrites: lectureSeule,
  }, reappliquer);
  if (CFG.bienvenue) {
    await assurerSalon('bienvenue', {
      name: '👋・bienvenue', type: ChannelType.GuildText, parent: publique.id,
      topic: 'Les nouveaux arrivants sur le Discord de VESPER RP.', permissionOverwrites: lectureSeule,
    }, reappliquer);
  }

  const prive = [
    { id: tous, deny: [PermissionFlagsBits.ViewChannel] },
    { id: moi, allow: [PermissionFlagsBits.ViewChannel, PermissionFlagsBits.SendMessages, PermissionFlagsBits.EmbedLinks,
      PermissionFlagsBits.ReadMessageHistory] },
    ...staffAutorise,
  ];
  const staff = await assurerSalon('categorieStaff', {
    name: '🛡️ VESPER — STAFF', type: ChannelType.GuildCategory, permissionOverwrites: prive,
  }, reappliquer);
  await assurerSalon('connexions', {
    name: '📋・logs-joueurs', type: ChannelType.GuildText, parent: staff.id,
    topic: 'Connexions, déconnexions, personnages chargés, changements de métier, morts, redémarrages. Fiche d’un joueur : /id.',
    permissionOverwrites: prive,
  }, reappliquer, '📜・connexions-jeu');
  await assurerSalon('journal', {
    name: '🤖・journal-bot', type: ChannelType.GuildText, parent: staff.id,
    topic: 'Démarrages du bot, redémarrages du serveur, ressources lancées ou arrêtées.', permissionOverwrites: prive,
  }, reappliquer);

  etat.signatureRoles = signature;
  sauver();
}

// ── Journaux des scripts ─────────────────────────────────────────────────

// Après un échec (permission manquante, salon refusé…), on ne réessaie pas
// à chaque relevé : le journal du bot serait inondé.
const PAUSE_APRES_ECHEC = 5 * 60 * 1000;
const echecsModules = new Map(); // id → horodatage du dernier échec
let modulesPresents = [];        // dernière liste reçue de la ressource

async function webhookDuSalon(salonDiscord, connu, nom) {
  const existants = await salonDiscord.fetchWebhooks();
  let wh = (connu && existants.get(connu)) || existants.find((w) => w.owner?.id === client.user.id && w.name === nom);
  // Sans jeton, l'URL est inutilisable : on en refait un.
  if (wh && !wh.token) {
    await wh.delete('Bot VESPER : webhook sans jeton').catch(() => {});
    wh = null;
  }
  if (!wh) {
    wh = await salonDiscord.createWebhook({
      name: nom, avatar: client.user.displayAvatarURL({ extension: 'png', size: 256 }),
      reason: 'Bot VESPER : journaux',
    });
  }
  return wh;
}

async function installerModule(m) {
  const connu = etat.modules[m.id];
  const signatureRoles = JSON.stringify(CFG.staffRoles);
  const reappliquer = Boolean(connu) && connu.roles !== signatureRoles;
  const nouveau = !connu;
  const prive = permissionsStaff();

  const categorie = await assurerSalon(`mod:${m.id}:categorie`, {
    name: `${m.emoji} LOGS — ${m.titre}`, type: ChannelType.GuildCategory, permissionOverwrites: prive,
  }, reappliquer);

  const salons = {};
  const webhooks = {};
  for (const s of m.salons) {
    const salonDiscord = await assurerSalon(`mod:${m.id}:${s.cle}`, {
      name: `${s.emoji}・${m.prefixe}-${s.nom}`, type: ChannelType.GuildText, parent: categorie.id,
      topic: `${m.titre} — ${s.description || s.cle}`.slice(0, 1000), permissionOverwrites: prive,
    }, reappliquer);
    const wh = await webhookDuSalon(salonDiscord, connu?.salons?.[s.cle]?.webhook, `${m.titre} — journaux`);
    salons[s.cle] = { salon: salonDiscord.id, webhook: wh.id };
    webhooks[s.cle] = wh.url;
  }

  // La ressource les garde (KVP) et poste elle-même.
  await recuperer('/vesper-discord/webhooks', { method: 'POST', body: JSON.stringify({ id: m.id, webhooks }) });

  etat.modules[m.id] = {
    titre: m.titre, signature: m.signature, roles: signatureRoles, categorie: categorie.id, salons,
  };
  sauver();
  echecsModules.delete(m.id);

  if (nouveau) {
    await journal(`🧩 **${echapper(m.titre)}** détecté (\`${m.id}\`) : ${m.salons.length} salons de journaux `
      + `créés dans <#${categorie.id}>, réservés au staff.`);
  } else if (connu.signature !== m.signature) {
    await journal(`🧩 Journaux de **${echapper(m.titre)}** mis à jour (${m.salons.length} salons).`);
  }
}

async function synchroniserModules(modules) {
  if (!Array.isArray(modules)) return;
  modulesPresents = modules;
  const signatureRoles = JSON.stringify(CFG.staffRoles);
  for (const m of modules) {
    const connu = etat.modules[m.id];
    const aFaire = !connu || connu.signature !== m.signature || connu.roles !== signatureRoles
      || (Array.isArray(m.manquants) && m.manquants.length > 0);
    if (!aFaire) continue;
    if (Date.now() - (echecsModules.get(m.id) || 0) < PAUSE_APRES_ECHEC) continue;
    try {
      await installerModule(m);
    } catch (err) {
      echecsModules.set(m.id, Date.now());
      console.error('journaux', m.id, err);
      await journal(`⚠️ Journaux de **${echapper(m.titre)}** : ${err.message}. Nouvel essai dans 5 min `
        + '(le bot a-t-il « Gérer les salons » et « Gérer les webhooks » ?).');
    }
  }
}

// Un script désinstallé laisse sa catégorie : on ne la supprime jamais
// tout seul (un arrêt pour maintenance ne doit pas effacer l'historique),
// mais le staff peut la retirer avec `/journaux retirer`.
async function retirerModule(id) {
  const m = etat.modules[id];
  const cles = Object.keys(etat.salons).filter((c) => c.startsWith(`mod:${id}:`));
  // Les salons d'abord, la catégorie en dernier : Discord refuse sinon
  // de la vider proprement.
  cles.sort((a, b) => (a.endsWith(':categorie') ? 1 : 0) - (b.endsWith(':categorie') ? 1 : 0));
  let supprimes = 0;
  for (const c of cles) {
    const ch = await guilde.channels.fetch(etat.salons[c]).catch(() => null);
    if (ch) {
      await ch.delete(`Bot VESPER : journaux de ${m?.titre || id} retirés`);
      supprimes += 1;
    }
    delete etat.salons[c];
  }
  delete etat.modules[id];
  echecsModules.delete(id);
  sauver();
  return { titre: m?.titre || id, supprimes };
}

// ── Panneau de statut ────────────────────────────────────────────────────

function compterServices(joueurs) {
  return SERVICES.map((s) => {
    const membres = joueurs.filter((j) => j.metier === s.metier);
    // `en_service` n'existe que si ESX le gère pour ce métier ; sinon on
    // compte tous ceux qui ont le métier.
    const geresService = membres.some((j) => typeof j.en_service === 'boolean');
    const n = geresService ? membres.filter((j) => j.en_service).length : membres.length;
    return `${s.emoji} ${s.nom} **${n}**`;
  });
}

function lienConnexion() {
  return CFG.cfxJoin ? `https://cfx.re/join/${CFG.cfxJoin}` : null;
}

function embedStatut() {
  const e = new EmbedBuilder()
    .setAuthor({ name: 'VESPER RP — Roleplay français', iconURL: client.user.displayAvatarURL() })
    .setThumbnail(client.user.displayAvatarURL({ size: 256 }))
    .setFooter({ text: `Bot VESPER v${VERSION} · relevé toutes les ${CFG.intervalle / 1000} s` })
    .setTimestamp(new Date());

  const connexion = `\`\`\`connect ${CFG.adresse}\`\`\``;

  if (statut !== 'en_ligne' || !dernier) {
    return e.setColor(COULEUR.ko)
      .setTitle('🔴 Serveur hors ligne')
      .setDescription(statut === 'inconnu'
        ? 'Premier relevé en cours…'
        : 'Le serveur ne répond plus. Il revient généralement en quelques minutes.\n'
          + 'Activez **🔔 Notifications** pour être prévenu de son retour.')
      .addFields({ name: 'Adresse (F8)', value: connexion });
  }

  const d = dernier;
  const n = d.joueurs.length;
  const maint = etat.maintenance;

  e.setColor(maint ? COULEUR.maintenance : COULEUR.ok)
    .setTitle(maint ? '🟠 Serveur en maintenance' : '🟢 Serveur en ligne')
    .setDescription(maint
      ? `**${echapper(maint.raison, 200) || 'Maintenance en cours'}**\nDepuis ${ts(maint.depuis)}.`
      : 'Bienvenue à Los Santos. Appuyez sur **F8** dans FiveM et collez l’adresse ci-dessous.');

  e.addFields(
    { name: '👥 Joueurs', value: `**${n} / ${d.max}**\n${barre(n, d.max)}`, inline: true },
    { name: '⏱️ En ligne depuis', value: d.enLigneDepuis != null ? duree(d.enLigneDepuis) : '—', inline: true },
    { name: '📈 Pic du jour · record', value: `**${etat.picJour.valeur}** · ${etat.record.valeur}`, inline: true },
  );

  if (d.complet) {
    e.addFields({ name: '🏙️ En service', value: compterServices(d.joueurs).join('  ·  ') });
    if (n) {
      const noms = d.joueurs
        .slice().sort((a, b) => a.id - b.id)
        .map((j) => `\`${String(j.id).padStart(2, ' ')}\` ${echapper(j.nom)}`);
      let liste = '';
      for (const ligne of noms) {
        if ((liste + ligne).length > 980) { liste += `\n… et ${noms.length - liste.split('\n').length} autres`; break; }
        liste += (liste ? '\n' : '') + ligne;
      }
      e.addFields({ name: '🎮 En ville', value: liste });
    }
  }

  e.addFields({ name: '🔌 Se connecter (F8)', value: connexion });
  return e;
}

function boutonsStatut() {
  const rangee = new ActionRowBuilder();
  const lien = lienConnexion();
  if (lien) {
    rangee.addComponents(new ButtonBuilder().setStyle(ButtonStyle.Link).setLabel('Se connecter').setEmoji('🎮').setURL(lien));
  }
  rangee.addComponents(
    new ButtonBuilder().setCustomId('vesper:joueurs').setStyle(ButtonStyle.Secondary).setLabel('Joueurs').setEmoji('👥'),
    new ButtonBuilder().setCustomId('vesper:notif').setStyle(ButtonStyle.Primary).setLabel('Notifications').setEmoji('🔔'),
  );
  return [rangee];
}

async function majPanneau({ forcerEnBas = false } = {}) {
  const s = salon('statut');
  if (!s) return;
  const embed = embedStatut();
  const contenu = { embeds: [embed], components: boutonsStatut() };

  // On ne réécrit le message que si quelque chose a changé (l'heure du
  // pied de page exceptée), pour ne pas marteler l'API.
  const signature = JSON.stringify({ ...embed.toJSON(), timestamp: null });
  if (!forcerEnBas && signature === hashPanneau && etat.panneau) return;

  let message = etat.panneau && (await s.messages.fetch(etat.panneau).catch(() => null));
  if (message && forcerEnBas) {
    await message.delete().catch(() => {});
    message = null;
  }
  if (message) {
    await message.edit(contenu);
  } else {
    message = await s.send(contenu);
    etat.panneau = message.id;
    sauver();
  }
  hashPanneau = signature;
}

// Un événement (panne, retour, redémarrage) part dans le salon de statut,
// puis le panneau est reposé en dessous pour rester le dernier message.
async function annoncerStatut(texte, { ping = false, couleur = COULEUR.info } = {}) {
  const s = salon('statut');
  if (!s) return;
  const role = etat.roles.notif;
  await s.send({
    content: ping && role ? `<@&${role}>` : undefined,
    embeds: [new EmbedBuilder().setColor(couleur).setDescription(texte).setTimestamp(new Date())],
    allowedMentions: { roles: ping && role ? [role] : [] },
  }).catch((e) => console.error('annonce statut', e.message));
  await majPanneau({ forcerEnBas: true });
}

// ── Compteurs, présence, rôle « En jeu » ─────────────────────────────────

async function renommer(cle, nom) {
  const s = salon(cle);
  if (!s || s.name === nom) return;
  const avant = renommages.get(s.id) || 0;
  if (Date.now() - avant < DELAI_RENOMMAGE) return; // réessayé au prochain relevé
  renommages.set(s.id, Date.now());
  await s.setName(nom, 'Bot VESPER : compteur').catch((e) => console.error('renommage', e.message));
}

async function majCompteurs() {
  const n = statut === 'en_ligne' && dernier ? dernier.joueurs.length : null;
  await renommer('compteurJoueurs', n == null ? '🔴 Serveur hors ligne' : `🎮 En jeu : ${n}/${dernier.max}`);

  // Le nombre de membres ne change pas vite : un appel toutes les 5 min.
  if (Date.now() - dernierComptageMembres < DELAI_RENOMMAGE) return;
  dernierComptageMembres = Date.now();
  const g = await client.guilds.fetch({ guild: CFG.guildId, withCounts: true, force: true }).catch(() => null);
  const membres = g?.approximateMemberCount ?? guilde.memberCount;
  if (membres) await renommer('compteurMembres', `👥 Membres : ${membres}`);
}

let dernierComptageMembres = 0;

function majPresence() {
  if (!client?.user) return;
  if (statut !== 'en_ligne' || !dernier) {
    client.user.setPresence({ status: 'dnd', activities: [{ name: 'Serveur hors ligne', type: ActivityType.Watching }] });
    return;
  }
  const n = dernier.joueurs.length;
  client.user.setPresence({
    status: etat.maintenance ? 'idle' : 'online',
    activities: [{
      type: ActivityType.Watching,
      name: etat.maintenance ? 'la maintenance' : `${n}/${dernier.max} joueurs en ville`,
    }],
  });
}

async function majRoleEnJeu() {
  const roleId = etat.roles.enJeu;
  // Sans la ressource on ne connaît pas les comptes Discord des joueurs :
  // on ne retire alors le rôle à personne.
  if (!roleId || (statut === 'en_ligne' && !dernier?.complet)) return;
  const voulus = new Set(statut === 'en_ligne'
    ? dernier.joueurs.map((j) => j.discord).filter(Boolean)
    : []);
  const actuels = new Set(etat.enJeu);
  let change = false;

  for (const id of voulus) {
    if (actuels.has(id)) continue;
    const m = await guilde.members.fetch(id).catch(() => null);
    if (m) await m.roles.add(roleId, 'En jeu sur VESPER').catch(() => {});
    actuels.add(id); // même absent du Discord : on ne le recherche pas à chaque relevé
    change = true;
  }
  for (const id of [...actuels]) {
    if (voulus.has(id)) continue;
    const m = await guilde.members.fetch(id).catch(() => null);
    if (m) await m.roles.remove(roleId, 'A quitté VESPER').catch(() => {});
    actuels.delete(id);
    change = true;
  }
  if (change) {
    etat.enJeu = [...actuels];
    sauver();
  }
}

// ── Journaux : connexions et ressources ──────────────────────────────────

function qui(j) {
  return `**${echapper(j.nom || '?')}** \`#${j.id ?? '?'}\`${j.discord ? ` · <@${j.discord}>` : ''}`;
}

function metierDe(j) {
  return j.metier_label ? `${echapper(j.metier_label)}${j.grade ? ` (${echapper(j.grade)})` : ''}` : null;
}

// Un événement de la ressource → un embed du salon 📋 logs-joueurs.
function embedEvenement(evt) {
  const j = evt.joueur || {};
  const e = new EmbedBuilder().setTimestamp(new Date((evt.t || maintenant()) * 1000));
  const lignes = (l) => l.filter(Boolean).join('\n');
  const licence = j.licence ? `Licence : \`${j.licence}\`` : null;

  if (evt.type === 'arrivee') {
    return e.setColor(COULEUR.ok).setDescription(lignes([`➡️ ${qui(j)} se connecte`, licence]));
  }
  if (evt.type === 'personnage') {
    return e.setColor(COULEUR.info).setDescription(lignes([
      `🧍 ${qui(j)} ${evt.nouveau ? '**crée un nouveau personnage**' : 'charge son personnage'}`,
      j.personnage && `Personnage : **${echapper(j.personnage)}**`,
      metierDe(j) && `Métier : ${metierDe(j)}`,
      (j.liquide != null || j.banque != null) && `Argent : 💵 ${argent(j.liquide)} · 🏦 ${argent(j.banque)}`,
    ]));
  }
  if (evt.type === 'metier') {
    return e.setColor(COULEUR.marque).setDescription(lignes([
      `💼 ${qui(j)} change de métier${j.personnage ? ` — ${echapper(j.personnage)}` : ''}`,
      `${evt.avant ? echapper(evt.avant, 80) : '?'} → **${echapper(evt.apres, 80)}**`,
    ]));
  }
  if (evt.type === 'mort') {
    return e.setColor(0x6b7280).setDescription(lignes([
      `💀 ${qui(j)}${j.personnage ? ` (${echapper(j.personnage)})` : ''} est mort`,
      evt.tueur && `Tué par : ${qui(evt.tueur)}${evt.tueur.personnage ? ` (${echapper(evt.tueur.personnage)})` : ''}`,
      evt.cause && `Cause : ${echapper(evt.cause)}`,
    ]));
  }
  if (evt.type === 'redemarrage') {
    return e.setColor(COULEUR.maintenance).setDescription(lignes([
      `🔄 **${evt.joueurs.length} joueur(s) déconnecté(s) par ${evt.panne ? 'la panne' : 'le redémarrage'} du serveur**`,
      ...evt.joueurs.slice(0, 40).map((x) => `• ${qui(x)}${x.personnage ? ` — ${echapper(x.personnage)}` : ''}`),
    ]).slice(0, 4000));
  }
  return e.setColor(COULEUR.ko).setDescription(lignes([
    `⬅️ ${qui(j)} se déconnecte`,
    j.personnage && `Personnage : ${echapper(j.personnage)}`,
    metierDe(j) && `Métier : ${metierDe(j)}`,
    j.duree != null && `Session : ${duree(j.duree)}`,
    (j.liquide != null || j.banque != null) && `Argent : 💵 ${argent(j.liquide)} · 🏦 ${argent(j.banque)}`,
    evt.raison && `Raison : ${String(evt.raison).slice(0, 200)}`,
    licence,
  ]));
}

async function publierEvenements(evenements) {
  const s = salon('connexions');
  if (!s || !evenements.length) return;
  for (let i = 0; i < evenements.length; i += 10) {
    const lot = evenements.slice(i, i + 10).map(embedEvenement);
    await s.send({ embeds: lot, allowedMentions: { parse: [] } }).catch((e) => console.error('logs-joueurs', e.message));
  }
}

async function comparerRessources(liste) {
  if (!liste) return;
  const avant = etat.ressources;
  etat.ressources = liste;
  if (!avant) return;
  const ajoutees = liste.filter((r) => !avant.includes(r));
  const retirees = avant.filter((r) => !liste.includes(r));
  if (!ajoutees.length && !retirees.length) return;
  const lignes = [
    ...ajoutees.map((r) => `➕ \`${r}\``),
    ...retirees.map((r) => `➖ \`${r}\``),
  ];
  await journal(`🧩 **Ressources modifiées** (${liste.length} lancées)\n${lignes.join('\n')}`);
}

// ── Boucle principale ────────────────────────────────────────────────────

let enCours = false;

async function cycle() {
  if (enCours || !guilde) return;
  enCours = true;
  try {
    let r = null;
    try {
      r = await releve();
    } catch {
      r = null;
    }

    if (r) {
      echecs = 0;
      const etaitHorsLigne = statut === 'hors_ligne';
      const redemarre = statut === 'en_ligne' && dernier?.enLigneDepuis != null
        && r.enLigneDepuis != null && r.enLigneDepuis + 60 < dernier.enLigneDepuis;
      statut = 'en_ligne';

      // Pic du jour et record.
      const n = r.joueurs.length;
      const jour = jourParis();
      if (etat.picJour.jour !== jour) etat.picJour = { jour, valeur: 0 };
      if (n > etat.picJour.valeur) etat.picJour.valeur = n;
      if (n > etat.record.valeur) etat.record = { valeur: n, date: maintenant() };

      // Événements : le compteur de la ressource repart de zéro à chaque
      // redémarrage ; au tout premier lancement du bot, on ne rejoue pas
      // l'historique.
      if (r.dernier != null) {
        if (etat.dernierEvt != null && r.dernier >= etat.dernierEvt) await publierEvenements(r.evenements);
        etat.dernierEvt = r.dernier;
      }
      await comparerRessources(r.ressources);

      // Les départs provoqués par un arrêt du serveur ne nous parviennent
      // jamais (la ressource s'éteint avec lui) : on les reconstitue à
      // partir des derniers joueurs vus.
      if ((redemarre || etaitHorsLigne) && etat.derniersJoueurs?.length) {
        await publierEvenements([{ type: 'redemarrage', panne: etaitHorsLigne, joueurs: etat.derniersJoueurs, t: maintenant() }]);
      }
      if (r.complet) etat.derniersJoueurs = r.joueurs.map(({ id, nom, discord, personnage }) => ({ id, nom, discord, personnage }));

      dernier = r;
      sauver();
      await synchroniserModules(r.modules);

      if (etaitHorsLigne) {
        await annoncerStatut('🟢 **Le serveur est de nouveau en ligne.** Bon jeu à tous !', { ping: true, couleur: COULEUR.ok });
        await journal('🟢 Serveur de nouveau joignable.');
      } else if (redemarre) {
        await annoncerStatut('🔄 **Le serveur vient de redémarrer.** Vous pouvez vous reconnecter.', { couleur: COULEUR.info });
        await journal('🔄 Redémarrage du serveur détecté.');
      }
    } else {
      echecs += 1;
      if (echecs >= ECHECS_AVANT_HORS_LIGNE && statut !== 'hors_ligne') {
        const etaitInconnu = statut === 'inconnu';
        statut = 'hors_ligne';
        dernier = null;
        if (!etaitInconnu) {
          await annoncerStatut('🔴 **Le serveur est hors ligne.** Nous revenons au plus vite.', { couleur: COULEUR.ko });
          await journal('🔴 Serveur injoignable depuis 3 relevés.');
        }
      }
    }

    await majPanneau();
    majPresence();
    await majRoleEnJeu();
    await majCompteurs();
  } catch (err) {
    console.error('cycle', err);
  } finally {
    enCours = false;
  }
}

// ── Commandes ────────────────────────────────────────────────────────────

const STAFF = PermissionFlagsBits.ManageGuild;

const COMMANDES = [
  new SlashCommandBuilder().setName('statut').setDescription('Affiche l’état du serveur VESPER RP'),
  new SlashCommandBuilder().setName('joueurs').setDescription('Liste les joueurs connectés'),
  new SlashCommandBuilder().setName('connexion').setDescription('Comment rejoindre le serveur'),
  new SlashCommandBuilder().setName('update').setDescription('Publier une mise à jour dans #mises-à-jour')
    .setDefaultMemberPermissions(STAFF)
    .addBooleanOption((o) => o.setName('notifier').setDescription('Mentionner le rôle 🔔 Notif serveur (oui par défaut)')),
  new SlashCommandBuilder().setName('annonce-jeu').setDescription('Envoyer un message dans le tchat en jeu')
    .setDefaultMemberPermissions(STAFF)
    .addStringOption((o) => o.setName('message').setDescription('Texte de l’annonce').setRequired(true).setMaxLength(400)),
  new SlashCommandBuilder().setName('maintenance').setDescription('Mettre le serveur en maintenance ou l’en sortir')
    .setDefaultMemberPermissions(STAFF)
    .addSubcommand((s) => s.setName('activer').setDescription('Annoncer une maintenance')
      .addStringOption((o) => o.setName('raison').setDescription('Ce qui est fait').setMaxLength(200)))
    .addSubcommand((s) => s.setName('terminer').setDescription('Fin de la maintenance')),
  new SlashCommandBuilder().setName('installer').setDescription('Recrée les salons et rôles du bot s’il en manque')
    .setDefaultMemberPermissions(PermissionFlagsBits.Administrator),
  new SlashCommandBuilder().setName('id').setDescription('Fiche d’un joueur : personnages, argent, inventaire, véhicules, propriétés…')
    .setDefaultMemberPermissions(STAFF)
    .addStringOption((o) => o.setName('joueur')
      .setDescription('Licence, id en jeu, nom du personnage, pseudo FiveM ou compte Discord')
      .setRequired(true).setAutocomplete(true).setMaxLength(100)),
  new SlashCommandBuilder().setName('journaux').setDescription('Scripts reliés au bot et leurs salons de journaux')
    .setDefaultMemberPermissions(STAFF)
    .addBooleanOption((o) => o.setName('resynchroniser')
      .setDescription('Vérifier et recréer salons et webhooks manquants au prochain relevé'))
    .addStringOption((o) => o.setName('retirer')
      .setDescription('Supprimer la catégorie et les salons d’un script arrêté ou désinstallé')
      .setAutocomplete(true)),
].map((c) => c.setDMPermission(false).toJSON());

async function enregistrerCommandes() {
  const rest = new REST({ version: '10' }).setToken(CFG.token);
  await rest.put(Routes.applicationGuildCommands(client.user.id, CFG.guildId), { body: COMMANDES });
}

function embedJoueurs(details) {
  const e = new EmbedBuilder().setColor(COULEUR.marque);
  if (statut !== 'en_ligne' || !dernier) return e.setTitle('🔴 Serveur hors ligne');
  const joueurs = dernier.joueurs.slice().sort((a, b) => a.id - b.id);
  e.setTitle(`👥 ${joueurs.length} / ${dernier.max} joueurs en ville`);
  if (!joueurs.length) return e.setDescription('Personne pour l’instant — soyez le premier !');
  if (!dernier.complet) return e.setDescription('Liste détaillée indisponible pour le moment.');
  const lignes = joueurs.map((j) => {
    let l = `\`#${j.id}\` **${echapper(j.nom)}**`;
    if (details) {
      if (j.personnage) l += ` — ${echapper(j.personnage)}`;
      if (j.metier_label) l += ` · ${echapper(j.metier_label)}`;
      l += ` · ${j.ping} ms`;
      if (j.discord) l += ` · <@${j.discord}>`;
    }
    return l;
  });
  return e.setDescription(lignes.join('\n').slice(0, 4000));
}

// ── Fiche joueur (/id) ───────────────────────────────────────────────────

// Une valeur de champ tient en 1024 caractères : on coupe proprement en
// annonçant ce qui manque, au lieu de laisser Discord refuser l'embed.
function champ(lignes, vide = '—') {
  const l = lignes.filter(Boolean);
  if (!l.length) return vide;
  let sortie = '';
  for (let i = 0; i < l.length; i += 1) {
    const suite = (sortie ? '\n' : '') + l[i];
    if ((sortie + suite).length > 990) return `${sortie}\n… et ${l.length - i} de plus`;
    sortie += suite;
  }
  return sortie;
}

function tailleEmbed(e) {
  const d = e.toJSON();
  return (d.title || '').length + (d.description || '').length + (d.footer?.text || '').length
    + (d.author?.name || '').length + (d.fields || []).reduce((n, f) => n + f.name.length + f.value.length, 0);
}

function embedCompte(f) {
  const e = new EmbedBuilder().setColor(f.en_ligne ? COULEUR.ok : 0x6b7280)
    .setTitle(`🪪 ${echapper(f.pseudo || 'Joueur')}`)
    .setDescription(f.en_ligne
      ? `🟢 **En jeu** — id \`#${f.en_ligne.id}\` · ${f.en_ligne.ping} ms`
      : `⚫ Hors ligne${f.derniere_vue ? ` — vu ${quand(f.derniere_vue, 'R')}` : ''}`)
    .addFields(
      { name: 'Licence', value: `\`${f.licence}\`` },
      { name: 'Discord', value: f.discord ? `<@${f.discord}>` : 'inconnu (seulement quand il est en jeu)', inline: true },
      { name: 'Temps de jeu', value: f.temps_de_jeu != null ? duree(f.temps_de_jeu) : '—', inline: true },
      { name: 'Personnages', value: `${liste(f.personnages).length}${f.emplacements ? ` / ${f.emplacements} emplacements` : ''}`, inline: true },
    );
  if (f.premiere_vue) e.addFields({ name: 'Première connexion relevée', value: quand(f.premiere_vue), inline: true });
  if (f.staff) e.addFields({ name: 'Staff', value: echapper(f.staff), inline: true });
  const sanctions = liste(f.sanctions);
  e.addFields({
    name: `⛔ Sanctions (${sanctions.length})`,
    value: champ(sanctions.map((s) => `${s.levee ? '~~' : ''}${echapper(s.raison || 'sans motif', 120)} — par ${echapper(s.par || '?')}`
      + ` ${quand(s.le, 'd') || ''}${s.jusqu_a ? ` → ${quand(s.jusqu_a, 'd')}` : ' (définitif)'}${s.levee ? '~~ levée' : ''}`), 'Aucune'),
  });
  return e;
}

const SEXES = { m: 'Homme', f: 'Femme' };

function embedPersonnage(p, enLigne) {
  const nom = `${p.prenom || '?'} ${p.nom || ''}`.trim();
  const e = new EmbedBuilder().setColor(p.en_jeu ? COULEUR.ok : COULEUR.marque)
    .setTitle(`👤 ${echapper(nom)}${p.en_jeu ? ' · 🟢 en jeu' : ''}`)
    .setFooter({ text: `${p.identifiant}${p.en_jeu ? ' · argent et inventaire en direct' : ' · d’après la dernière sauvegarde'}` });

  e.addFields(
    { name: '🪪 Identité', inline: true, value: champ([
      p.naissance && `Né(e) le ${echapper(p.naissance)}`,
      p.sexe && (SEXES[p.sexe] || echapper(p.sexe)),
      p.taille && `${p.taille} cm`,
      p.groupe_sanguin && `Groupe ${echapper(p.groupe_sanguin)}`,
      p.telephone && `📞 ${echapper(p.telephone)}`,
      p.cree_le && `Créé ${quand(p.cree_le, 'd')}`,
    ]) },
    { name: '💼 Métier', inline: true, value: champ([
      `${echapper(p.metier || '?')}${p.grade ? ` — ${echapper(p.grade)}` : ''}`,
      p.matricule && `Matricule ${echapper(p.matricule)}`,
      p.groupe && p.groupe !== 'user' && `Groupe ESX : ${echapper(p.groupe)}`,
      p.gang && `🏴 ${echapper(p.gang.nom)} (${echapper(p.gang.grade)})`,
    ]) },
    { name: '💰 Argent', inline: true, value: champ([
      `💵 ${argent(p.argent?.liquide)}`,
      `🏦 ${argent(p.argent?.banque)}`,
      p.argent?.sale ? `🕶️ ${argent(p.argent.sale)} (sale)` : null,
      ...liste(p.cartes).map((c) => `💳 ${echapper(c.type || 'carte')} ••${c.fin}${c.active ? '' : ' (bloquée)'}`),
      p.casino && `🎰 ${p.casino.jetons} jetons${p.casino.vip ? ' · VIP' : ''}`,
    ]) },
  );

  const justice = [
    p.casier && `Casier : **${p.casier.total}** entrée(s)`,
    ...liste(p.casier?.derniers).map((c) => `• ${echapper(c.infractions || '?', 120)} — ${argent(c.amende)}${c.prison ? `, ${c.prison} min` : ''} ${quand(c.quand, 'd') || ''}`),
    p.amendes_impayees?.nombre && `Amendes impayées : **${p.amendes_impayees.nombre}** (${argent(p.amendes_impayees.total)})`,
    p.factures_ouvertes?.nombre && `Factures ouvertes : **${p.factures_ouvertes.nombre}** (${argent(p.factures_ouvertes.reste)} restants)`,
    ...liste(p.assurances).map((a) => `🩺 ${echapper(a.nom)}${a.jusqu_a ? ` jusqu’au ${quand(a.jusqu_a, 'd')}` : ''}`),
  ];
  e.addFields({ name: '⚖️ Justice, factures, assurances', value: champ(justice, 'Rien à signaler') });

  const vehicules = liste(p.vehicules);
  e.addFields({
    name: `🚗 Véhicules (${vehicules.length})`,
    value: champ(vehicules.map((v) => `\`${echapper(v.plaque)}\` ${echapper(v.modele, 50)} — ${v.etat}${v.garage && v.etat !== 'sorti' ? ` (${echapper(v.garage, 40)})` : ''}`), 'Aucun'),
  });
  const proprietes = liste(p.proprietes);
  e.addFields({
    name: `🏠 Propriétés (${proprietes.length})`,
    value: champ(proprietes.map((h) => `${echapper(h.nom, 80)} — ${h.type}${h.dette ? ` (dette ${argent(h.dette)})` : ''}`), 'Aucune'),
  });

  const inventaire = liste(p.inventaire);
  e.addFields({
    name: `🎒 Inventaire (${inventaire.length} objet${inventaire.length > 1 ? 's' : ''} différents)`,
    value: champ(inventaire.map((o) => `${Number(o.quantite).toLocaleString('fr-FR')}× ${echapper(o.label || o.objet, 60)}`), 'Vide'),
  });
  return e;
}

// Rend des lots d'embeds, un par message : 10 embeds et 6000 caractères au
// plus par message.
function embedsFiche(f) {
  const embeds = [embedCompte(f), ...liste(f.personnages).map((p) => embedPersonnage(p, f.en_ligne))];
  const lots = [];
  let lot = [];
  let taille = 0;
  for (const e of embeds) {
    const t = tailleEmbed(e);
    if (lot.length && (lot.length >= 10 || taille + t > 5800)) {
      lots.push(lot);
      lot = [];
      taille = 0;
    }
    lot.push(e);
    taille += t;
  }
  if (lot.length) lots.push(lot);
  return lots;
}

function embedConnexion() {
  const lien = lienConnexion();
  return new EmbedBuilder().setColor(COULEUR.marque).setTitle('🎮 Rejoindre VESPER RP')
    .setDescription([
      '1. Lancez **FiveM**.',
      `2. Appuyez sur **F8** et tapez : \`connect ${CFG.adresse}\``,
      lien ? `3. Ou cliquez simplement : ${lien}` : '3. Ou cherchez **VESPER RP** dans la liste des serveurs.',
    ].join('\n'));
}

async function surInteraction(interaction) {
  if (interaction.guildId !== CFG.guildId) return;

  // Seuls les scripts absents sont proposés : on ne retire pas les
  // journaux d'un script qui tourne (il les recréerait au relevé suivant).
  if (interaction.isAutocomplete() && interaction.commandName === 'id') {
    if (!estStaff(interaction)) return interaction.respond([]).catch(() => {});
    const tape = interaction.options.getFocused();
    try {
      const r = await recuperer(`/vesper-discord/recherche?q=${encodeURIComponent(tape)}`);
      return interaction.respond(liste(r.resultats).map((x) => ({ name: x.label, value: x.valeur }))).catch(() => {});
    } catch {
      return interaction.respond([]).catch(() => {});
    }
  }

  if (interaction.isAutocomplete()) {
    if (interaction.commandName !== 'journaux' || !estStaff(interaction)) return interaction.respond([]);
    const tape = interaction.options.getFocused().toLowerCase();
    const presents = new Set(modulesPresents.map((m) => m.id));
    const choix = Object.entries(etat.modules)
      .filter(([id]) => !presents.has(id))
      .map(([id, m]) => ({ name: `${m.titre || id} (${id})`.slice(0, 100), value: id }))
      .filter((c) => c.name.toLowerCase().includes(tape))
      .slice(0, 25);
    return interaction.respond(choix).catch(() => {});
  }

  if (interaction.isButton()) {
    if (interaction.customId === 'vesper:joueurs') {
      return interaction.reply({ embeds: [embedJoueurs(estStaff(interaction))], ephemeral: true });
    }
    if (interaction.customId === 'vesper:notif') {
      const role = etat.roles.notif;
      const membre = interaction.member;
      if (!role || !membre) return interaction.reply({ content: 'Rôle indisponible.', ephemeral: true });
      if (membre.roles.cache.has(role)) {
        await membre.roles.remove(role, 'Notifications désactivées');
        return interaction.reply({ content: '🔕 Vous ne serez plus notifié.', ephemeral: true });
      }
      await membre.roles.add(role, 'Notifications activées');
      return interaction.reply({ content: '🔔 Vous serez prévenu des retours du serveur et des mises à jour.', ephemeral: true });
    }
    return;
  }

  if (interaction.isModalSubmit() && interaction.customId.startsWith('vesper:update:')) {
    if (!estStaff(interaction)) return interaction.reply({ content: 'Réservé au staff.', ephemeral: true });
    const notifier = interaction.customId.endsWith(':1');
    const titre = interaction.fields.getTextInputValue('titre').trim();
    const version = interaction.fields.getTextInputValue('version').trim();
    const contenu = interaction.fields.getTextInputValue('contenu').trim();
    const image = interaction.fields.getTextInputValue('image').trim();

    // Chaque ligne devient une puce, sauf si l'auteur a déjà mis les siennes.
    const corps = contenu.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)
      .map((l) => (/^([-•*>#]|\d+[.)]|[^\w\s])/u.test(l) ? l : `• ${l}`)).join('\n');

    const e = new EmbedBuilder().setColor(COULEUR.marque)
      .setAuthor({ name: 'VESPER RP — Mise à jour', iconURL: client.user.displayAvatarURL() })
      .setTitle(version ? `${titre} · ${version}` : titre)
      .setDescription(corps.slice(0, 4000))
      .setFooter({ text: `Publié par ${interaction.member?.displayName || interaction.user.username}` })
      .setTimestamp(new Date());
    if (/^https?:\/\/\S+$/i.test(image)) e.setImage(image);

    const s = salon('majs');
    if (!s) return interaction.reply({ content: 'Salon #mises-à-jour introuvable — lancez /installer.', ephemeral: true });
    const role = etat.roles.notif;
    const msg = await s.send({
      content: notifier && role ? `<@&${role}>` : undefined,
      embeds: [e],
      allowedMentions: { roles: notifier && role ? [role] : [] },
    });
    if (s.type === ChannelType.GuildAnnouncement) await msg.crosspost().catch(() => {});
    return interaction.reply({ content: `✅ Publié : ${msg.url}`, ephemeral: true });
  }

  if (!interaction.isChatInputCommand()) return;
  const cmd = interaction.commandName;

  if (cmd === 'statut') {
    return interaction.reply({ embeds: [embedStatut()], components: boutonsStatut() });
  }
  if (cmd === 'joueurs') {
    return interaction.reply({ embeds: [embedJoueurs(estStaff(interaction))], ephemeral: true });
  }
  if (cmd === 'connexion') {
    return interaction.reply({ embeds: [embedConnexion()] });
  }

  if (!estStaff(interaction)) return interaction.reply({ content: 'Réservé au staff.', ephemeral: true });

  if (cmd === 'update') {
    const notifier = interaction.options.getBoolean('notifier') ?? true;
    const champ = (id, label, style, requis, max, aide) => new ActionRowBuilder().addComponents(
      new TextInputBuilder().setCustomId(id).setLabel(label).setStyle(style).setRequired(requis)
        .setMaxLength(max).setPlaceholder(aide),
    );
    const modal = new ModalBuilder().setCustomId(`vesper:update:${notifier ? 1 : 0}`).setTitle('Nouvelle mise à jour')
      .addComponents(
        champ('titre', 'Titre', TextInputStyle.Short, true, 100, 'Ex. : Arrivée du métier de pompier'),
        champ('version', 'Version (facultatif)', TextInputStyle.Short, false, 30, 'Ex. : v1.4'),
        champ('contenu', 'Changements (une ligne = une puce)', TextInputStyle.Paragraph, true, 3500,
          'Nouveau garage à Sandy Shores\nCorrection des factures du mécano'),
        champ('image', 'Image (lien, facultatif)', TextInputStyle.Short, false, 500, 'https://…'),
      );
    return interaction.showModal(modal);
  }

  if (cmd === 'id') {
    const recherche = interaction.options.getString('joueur', true);
    await interaction.deferReply({ ephemeral: true });
    let fiche;
    try {
      fiche = await recuperer(`/vesper-discord/fiche?q=${encodeURIComponent(recherche)}`);
    } catch (err) {
      const msg = err.status === 404 ? 'Aucun joueur trouvé.' : `Le serveur n’a pas répondu (${err.message}).`;
      return interaction.editReply(`❌ ${msg}`);
    }
    if (fiche.candidats) {
      const c = liste(fiche.candidats);
      return interaction.editReply(c.length
        ? `Plusieurs joueurs correspondent, précisez :\n${c.map((x) => `• ${x.label} — \`${x.valeur}\``).join('\n')}`.slice(0, 1900)
        : '❌ Aucun joueur trouvé.');
    }
    const [premier, ...suite] = embedsFiche(fiche);
    await interaction.editReply({ embeds: premier, allowedMentions: { parse: [] } });
    for (const lot of suite) {
      await interaction.followUp({ embeds: lot, ephemeral: true, allowedMentions: { parse: [] } });
    }
    // Qui a consulté quoi : la fiche montre l'argent et l'inventaire.
    await journal(`🔎 <@${interaction.user.id}> a consulté la fiche de **${echapper(fiche.pseudo || fiche.licence)}** (\`${fiche.licence}\`).`);
    return;
  }

  if (cmd === 'annonce-jeu') {
    const message = interaction.options.getString('message', true);
    try {
      await recuperer('/vesper-discord/annonce', {
        method: 'POST',
        body: JSON.stringify({ message, auteur: interaction.user.username }),
      });
      await journal(`📢 Annonce en jeu par <@${interaction.user.id}> : ${message}`);
      return interaction.reply({ content: '✅ Annonce envoyée dans le tchat en jeu.', ephemeral: true });
    } catch (err) {
      return interaction.reply({ content: `❌ Le serveur n’a pas reçu l’annonce (${err.message}).`, ephemeral: true });
    }
  }

  if (cmd === 'maintenance') {
    if (interaction.options.getSubcommand() === 'activer') {
      const raison = interaction.options.getString('raison') || 'Maintenance en cours';
      etat.maintenance = { raison, depuis: maintenant() };
      sauver();
      await interaction.reply({ content: '🟠 Maintenance annoncée.', ephemeral: true });
      await annoncerStatut(`🟠 **Maintenance :** ${echapper(raison, 200)}`, { couleur: COULEUR.maintenance });
    } else {
      etat.maintenance = null;
      sauver();
      await interaction.reply({ content: '🟢 Maintenance terminée.', ephemeral: true });
      await annoncerStatut('🟢 **Maintenance terminée.** Le serveur est ouvert.', { ping: true, couleur: COULEUR.ok });
    }
    majPresence();
    return;
  }

  if (cmd === 'journaux') {
    const aRetirer = interaction.options.getString('retirer');
    if (aRetirer) {
      if (!etat.modules[aRetirer]) {
        return interaction.reply({ content: `Aucun journal connu pour \`${echapper(aRetirer, 60)}\`.`, ephemeral: true });
      }
      if (modulesPresents.some((m) => m.id === aRetirer)) {
        return interaction.reply({
          content: `\`${aRetirer}\` tourne encore : arrêtez la ressource d’abord, sinon ses salons reviennent au relevé suivant.`,
          ephemeral: true,
        });
      }
      await interaction.deferReply({ ephemeral: true });
      try {
        const r = await retirerModule(aRetirer);
        await journal(`🗑️ Journaux de **${echapper(r.titre)}** (\`${aRetirer}\`) retirés par <@${interaction.user.id}> `
          + `(${r.supprimes} salon(s) supprimé(s)).`);
        return interaction.editReply(`✅ Journaux de **${echapper(r.titre)}** retirés : ${r.supprimes} salon(s) supprimé(s). `
          + 'S’il redémarre un jour, le script les recréera tout seul.');
      } catch (err) {
        return interaction.editReply(`❌ Retrait incomplet (${err.message}). Relancez la commande pour finir.`);
      }
    }
    if (interaction.options.getBoolean('resynchroniser')) {
      for (const id of Object.keys(etat.modules)) etat.modules[id].signature = null;
      echecsModules.clear();
      sauver();
    }
    const presents = new Set(modulesPresents.map((m) => m.id));
    const ids = [...new Set([...Object.keys(etat.modules), ...presents])].sort();
    const e = new EmbedBuilder().setColor(COULEUR.marque).setTitle('🧩 Journaux des scripts');
    if (!ids.length) {
      e.setDescription('Aucun script ne s’est encore déclaré. Un script compatible (ex. `vesper-lspd`) '
        + 'apparaît ici tout seul, quelques secondes après son démarrage.');
    }
    for (const id of ids.slice(0, 25)) {
      const m = etat.modules[id];
      const enCours = modulesPresents.find((x) => x.id === id);
      const manquants = enCours?.manquants?.length || 0;
      const etatTexte = !presents.has(id) ? '⚪ script arrêté (salons conservés · `/journaux retirer` pour les supprimer)'
        : !m ? '⏳ installation au prochain relevé'
          : manquants ? `🟠 ${manquants} webhook(s) à refaire` : '🟢 relié';
      const salons = m ? Object.values(m.salons).map((s) => `<#${s.salon}>`).join(' ') : '—';
      e.addFields({ name: `${m?.titre || enCours?.titre || id} · \`${id}\``, value: `${etatTexte}\n${salons}`.slice(0, 1024) });
    }
    if (interaction.options.getBoolean('resynchroniser')) e.setFooter({ text: 'Vérification complète au prochain relevé.' });
    return interaction.reply({ embeds: [e], ephemeral: true });
  }

  if (cmd === 'installer') {
    await interaction.deferReply({ ephemeral: true });
    await installer();
    hashPanneau = null;
    await majPanneau();
    return interaction.editReply('✅ Salons et rôles vérifiés.');
  }
}

// ── Bienvenue ────────────────────────────────────────────────────────────

async function surArrivee(membre) {
  if (membre.guild.id !== CFG.guildId) return;
  const s = salon('bienvenue');
  if (!s) return;
  const e = new EmbedBuilder().setColor(COULEUR.marque)
    .setAuthor({ name: membre.user.username, iconURL: membre.user.displayAvatarURL() })
    .setDescription(`Bienvenue <@${membre.id}> sur **VESPER RP** ! 🌆\n`
      + `Tu es notre **${membre.guild.memberCount}ᵉ** membre.\n\n`
      + `🎮 Pour jouer : **F8** → \`connect ${CFG.adresse}\`\n`
      + (salon('statut') ? `📊 État du serveur : <#${etat.salons.statut}>` : ''))
    .setThumbnail(membre.user.displayAvatarURL({ size: 256 }))
    .setTimestamp(new Date());
  await s.send({ embeds: [e], allowedMentions: { users: [membre.id] } }).catch(() => {});
}

// ── Démarrage ────────────────────────────────────────────────────────────

let minuterie = null;

async function surPret() {
  console.log(`Connecté en tant que ${client.user.tag} — VESPER bot v${VERSION}`);

  // Un seul serveur Discord autorisé.
  for (const g of client.guilds.cache.values()) {
    if (g.id !== CFG.guildId) {
      console.warn(`Serveur non autorisé quitté : ${g.name} (${g.id})`);
      await g.leave().catch(() => {});
    }
  }

  guilde = await client.guilds.fetch(CFG.guildId).catch(() => null);
  if (!guilde) {
    console.warn(`Pas encore invité sur ${CFG.guildId} — en attente.`);
    return;
  }
  await guilde.channels.fetch();
  await guilde.roles.fetch();

  await installer();
  await enregistrerCommandes().catch((e) => console.error('commandes', e.message));
  await journal(`🤖 Bot VESPER v${VERSION} démarré.`);

  clearInterval(minuterie);
  await cycle();
  minuterie = setInterval(cycle, CFG.intervalle);
}

function demarrer(avecMembres) {
  const intents = [GatewayIntentBits.Guilds];
  if (avecMembres) intents.push(GatewayIntentBits.GuildMembers);
  client = new Client({ intents });

  client.once(Events.ClientReady, () => surPret().catch((e) => console.error('démarrage', e)));
  client.on(Events.GuildCreate, (g) => {
    if (g.id !== CFG.guildId) {
      console.warn(`Invité sur un serveur non autorisé, départ : ${g.name} (${g.id})`);
      g.leave().catch(() => {});
    } else {
      // Toujours réinstaller : après une expulsion, `guilde` pointe encore
      // vers l'ancienne arrivée et le retour serait ignoré.
      surPret().catch((e) => console.error('arrivée', e));
    }
  });
  client.on(Events.GuildDelete, (g) => {
    if (g.id !== CFG.guildId) return;
    console.warn(`Retiré du serveur ${g.id} (expulsion ou suppression).`);
    clearInterval(minuterie);
    guilde = null;
  });
  client.on(Events.InteractionCreate, (i) => surInteraction(i).catch((e) => {
    console.error('interaction', e);
    if (i.isRepliable() && !i.replied && !i.deferred) i.reply({ content: 'Erreur interne.', ephemeral: true }).catch(() => {});
  }));
  if (avecMembres) client.on(Events.GuildMemberAdd, surArrivee);

  return client.login(CFG.token).catch((err) => {
    // L'intention « membres » est privilégiée : tant qu'elle n'est pas
    // cochée dans le portail développeur, Discord refuse la connexion. On
    // tourne alors sans le message de bienvenue plutôt que pas du tout.
    if (avecMembres && /disallowed intents|privileged intent/i.test(String(err.message))) {
      console.warn('Intention « Server Members » non activée : bienvenue désactivée.');
      client.destroy();
      return demarrer(false);
    }
    throw err;
  });
}

// Importé (tests de mise en forme) : on expose les constructeurs d'embeds
// sans se connecter à Discord.
if (require.main === module) {
  process.on('unhandledRejection', (e) => console.error('promesse rejetée', e));
  process.on('SIGTERM', () => { client?.destroy(); process.exit(0); });

  demarrer(CFG.bienvenue).catch((e) => {
    console.error('connexion impossible', e.message);
    process.exit(1);
  });
} else {
  module.exports = { embedsFiche, embedEvenement };
}
