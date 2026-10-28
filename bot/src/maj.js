// Mises à jour du bot et de la ressource FiveM, depuis les versions
// publiées sur GitHub (dépôt public, une archive .tgz + son empreinte
// SHA-256 par version, fabriquées par .github/workflows/version.yml).
//
// Le bot ANNONCE une nouvelle version ; un administrateur l'installe d'un
// clic. L'installation :
//   1. télécharge l'archive et vérifie son empreinte ;
//   2. envoie les fichiers de la ressource à `vesper-discord` (POST /maj),
//      qui les compile, les écrit et se recharge — le bot n'a pas le droit
//      d'écrire dans le dossier des ressources ;
//   3. remplace son propre code (sauvegarde d'abord), réinstalle les
//      dépendances si elles ont changé, puis quitte avec le code 75 ;
//   4. `lanceur.js` le relance aussitôt — et remet l'ancienne version si la
//      nouvelle plante au démarrage.
//
// ⚠️ Ce fichier ne touche JAMAIS à `lanceur.js`, `.env` ni `data/` : ce
// sont eux qui permettent de revenir en arrière.

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFile } = require('child_process');

const RACINE = path.join(__dirname, '..');
const DATA = path.join(RACINE, 'data');
const DEPOT = process.env.DEPOT_MAJ || 'CedricPoint/vesper-discord-bot';
const CODE_REDEMARRAGE = 75;

// Ce qui appartient au code du bot et peut être remplacé.
const A_REMPLACER = ['src', 'package.json', 'package-lock.json', 'avatar.png', 'deploy', '.env.example'];

const FICHIER_EN_COURS = path.join(DATA, 'maj-en-cours.json');
const FICHIER_ECHEC = path.join(DATA, 'maj-echec.json');

function comparer(a, b) {
  const pa = String(a).replace(/^v/, '').split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b).replace(/^v/, '').split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < 3; i += 1) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0) ? 1 : -1;
  }
  return 0;
}

function executer(commande, args, cwd) {
  return new Promise((resoudre, rejeter) => {
    execFile(commande, args, { cwd, timeout: 10 * 60 * 1000, maxBuffer: 16 * 1024 * 1024 }, (err, sortie, erreurs) => {
      if (err) {
        err.message = `${commande} ${args.join(' ')} : ${(erreurs || err.message).toString().trim().slice(-400)}`;
        return rejeter(err);
      }
      resoudre(sortie);
    });
  });
}

async function telecharger(url, accept) {
  const res = await fetch(url, {
    headers: { 'User-Agent': 'vesper-discord-bot', Accept: accept || 'application/octet-stream' },
    redirect: 'follow',
    signal: AbortSignal.timeout(60000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} sur ${url}`);
  return res;
}

/** La dernière version publiée, ou null s'il n'y en a aucune. */
async function derniereVersion() {
  const res = await fetch(`https://api.github.com/repos/${DEPOT}/releases/latest`, {
    headers: { 'User-Agent': 'vesper-discord-bot', Accept: 'application/vnd.github+json' },
    signal: AbortSignal.timeout(15000),
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`GitHub a répondu ${res.status}`);
  const r = await res.json();
  const version = String(r.tag_name || '').replace(/^v/, '');
  const archive = (r.assets || []).find((a) => a.name === `vesper-discord-bot-${version}.tgz`);
  const empreinte = (r.assets || []).find((a) => a.name === `vesper-discord-bot-${version}.tgz.sha256`);
  return {
    version,
    titre: r.name || `Version ${version}`,
    notes: r.body || '',
    lien: r.html_url,
    publiee: r.published_at,
    archive: archive?.browser_download_url || null,
    empreinte: empreinte?.browser_download_url || null,
  };
}

function copierDossier(source, cible) {
  fs.cpSync(source, cible, { recursive: true, force: true });
}

function lireSiExiste(fichier) {
  try { return fs.readFileSync(fichier, 'utf8'); } catch { return null; }
}

/**
 * Installe `publication` (rendue par derniereVersion). `etape(texte)` reçoit
 * l'avancement ; `envoyerRessource(version, fichiers)` pousse la ressource
 * FiveM et attend qu'elle revienne. Ne rend la main qu'en cas d'échec : en
 * cas de succès, le processus se termine pour être relancé.
 */
async function installer(publication, versionActuelle, { etape, envoyerRessource, versionRessource, contexte }) {
  if (!publication?.archive || !publication?.empreinte) throw new Error('archive ou empreinte absente de la publication');

  const travail = path.join(DATA, 'maj', publication.version);
  fs.rmSync(travail, { recursive: true, force: true });
  fs.mkdirSync(travail, { recursive: true });

  await etape(`Téléchargement de la version ${publication.version}…`);
  const archive = Buffer.from(await (await telecharger(publication.archive)).arrayBuffer());
  const attendue = (await (await telecharger(publication.empreinte)).text()).trim().split(/\s+/)[0].toLowerCase();
  const obtenue = crypto.createHash('sha256').update(archive).digest('hex');
  if (attendue !== obtenue) throw new Error(`empreinte SHA-256 différente (attendue ${attendue.slice(0, 12)}…, obtenue ${obtenue.slice(0, 12)}…)`);

  const fichierArchive = path.join(travail, 'archive.tgz');
  fs.writeFileSync(fichierArchive, archive);
  // `tar` existe sur Linux et sur Windows 10 et plus : pas de dépendance.
  await executer('tar', ['-xzf', 'archive.tgz'], travail);
  const nouveauBot = path.join(travail, 'bot');
  const nouvelleRessource = path.join(travail, 'vesper-discord');
  if (!fs.existsSync(path.join(nouveauBot, 'src', 'index.js'))) throw new Error('archive incomplète (bot/src/index.js absent)');

  // 1. La ressource FiveM, si sa version a changé.
  const manifeste = lireSiExiste(path.join(nouvelleRessource, 'fxmanifest.lua')) || '';
  const versionRes = (manifeste.match(/^version\s+['"]([^'"]+)['"]/m) || [])[1];
  if (versionRes && versionRessource && comparer(versionRes, versionRessource) > 0) {
    await etape(`Mise à jour de la ressource FiveM ${versionRessource} → ${versionRes}…`);
    const fichiers = {};
    for (const nom of fs.readdirSync(nouvelleRessource)) {
      if (/\.lua$/.test(nom)) fichiers[nom] = fs.readFileSync(path.join(nouvelleRessource, nom), 'utf8');
    }
    await envoyerRessource(versionRes, fichiers);
  } else if (versionRes && !versionRessource) {
    await etape('⚠️ Ressource FiveM injoignable : elle sera à mettre à jour à la main.');
  }

  // 2. Les dépendances, dans le dossier de travail : si `npm ci` échoue,
  // rien n'a encore été touché.
  const lockAvant = lireSiExiste(path.join(RACINE, 'package-lock.json'));
  const lockApres = lireSiExiste(path.join(nouveauBot, 'package-lock.json'));
  const dependancesChangent = lockApres && lockApres !== lockAvant;
  if (dependancesChangent) {
    await etape('Installation des nouvelles dépendances…');
    await executer(process.platform === 'win32' ? 'npm.cmd' : 'npm', ['ci', '--omit=dev', '--no-audit', '--no-fund'], nouveauBot);
  }

  // 3. Sauvegarde du code actuel, puis remplacement.
  await etape('Sauvegarde de la version actuelle et remplacement du code…');
  const sauvegarde = path.join(DATA, 'sauvegardes', versionActuelle);
  fs.rmSync(sauvegarde, { recursive: true, force: true });
  fs.mkdirSync(sauvegarde, { recursive: true });
  for (const nom of A_REMPLACER) {
    const actuel = path.join(RACINE, nom);
    if (fs.existsSync(actuel)) copierDossier(actuel, path.join(sauvegarde, nom));
  }
  if (dependancesChangent && fs.existsSync(path.join(RACINE, 'node_modules'))) {
    fs.renameSync(path.join(RACINE, 'node_modules'), path.join(sauvegarde, 'node_modules'));
  }

  for (const nom of A_REMPLACER) {
    const nouveau = path.join(nouveauBot, nom);
    if (!fs.existsSync(nouveau)) continue;
    fs.rmSync(path.join(RACINE, nom), { recursive: true, force: true });
    copierDossier(nouveau, path.join(RACINE, nom));
  }
  if (dependancesChangent) fs.renameSync(path.join(nouveauBot, 'node_modules'), path.join(RACINE, 'node_modules'));
  // Le lanceur lui-même : remplacé seulement s'il a changé, il ne sert qu'au
  // prochain démarrage du service.
  const lanceur = lireSiExiste(path.join(nouveauBot, 'lanceur.js'));
  if (lanceur && lanceur !== lireSiExiste(path.join(RACINE, 'lanceur.js'))) {
    fs.writeFileSync(path.join(RACINE, 'lanceur.js'), lanceur);
  }

  fs.writeFileSync(FICHIER_EN_COURS, JSON.stringify({
    de: versionActuelle, vers: publication.version, quand: Date.now(), ...contexte,
  }, null, 2));
  fs.rmSync(travail, { recursive: true, force: true });

  await etape(`Redémarrage du bot en version ${publication.version}…`);
  setTimeout(() => process.exit(CODE_REDEMARRAGE), 1500);
}

/** Ce que le démarrage précédent a laissé : une MAJ réussie ou annulée. */
function bilanAuDemarrage(versionActuelle) {
  const echec = lireSiExiste(FICHIER_ECHEC);
  if (echec) {
    fs.rmSync(FICHIER_ECHEC, { force: true });
    try { return { type: 'echec', ...JSON.parse(echec) }; } catch { return { type: 'echec' }; }
  }
  const enCours = lireSiExiste(FICHIER_EN_COURS);
  if (enCours) {
    let info = {};
    try { info = JSON.parse(enCours); } catch { /* fichier abîmé : on le jette */ }
    // Tant que ce fichier existe, un plantage fait revenir le lanceur à
    // l'ancienne version. Une fois le bot prêt, la mise à jour est acquise.
    if (info.vers === versionActuelle) {
      fs.rmSync(FICHIER_EN_COURS, { force: true });
      return { type: 'reussite', ...info };
    }
  }
  return null;
}

module.exports = {
  CODE_REDEMARRAGE, DEPOT, comparer, derniereVersion, installer, bilanAuDemarrage,
};
