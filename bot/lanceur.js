// Lanceur du bot : c'est lui que le service démarre (node lanceur.js).
//
// Il lance `src/index.js` et le relance :
//   - aussitôt, quand le bot sort avec le code 75 (il vient d'installer une
//     mise à jour et veut tourner sur son nouveau code) ;
//   - après 10 s, s'il plante.
//
// ⚠️ RETOUR ARRIÈRE. Si le bot plante alors qu'une mise à jour est en cours
// (`data/maj-en-cours.json` existe encore : il n'a pas atteint l'état
// « prêt »), le lanceur remet la version sauvegardée dans
// `data/sauvegardes/<ancienne version>/` et le note dans
// `data/maj-echec.json`, que le bot annonce au démarrage suivant.
//
// Volontairement minuscule et sans dépendance : c'est le seul code qui doit
// fonctionner quoi qu'il arrive au reste.

'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const RACINE = __dirname;
const DATA = path.join(RACINE, 'data');
const EN_COURS = path.join(DATA, 'maj-en-cours.json');
const ECHEC = path.join(DATA, 'maj-echec.json');
const CODE_REDEMARRAGE = 75;

let enfant = null;
let arret = false;

function revenirEnArriere(raison) {
  let info = {};
  try { info = JSON.parse(fs.readFileSync(EN_COURS, 'utf8')); } catch { return false; }
  const sauvegarde = path.join(DATA, 'sauvegardes', String(info.de || ''));
  if (!info.de || !fs.existsSync(path.join(sauvegarde, 'src', 'index.js'))) return false;

  for (const nom of fs.readdirSync(sauvegarde)) {
    const cible = path.join(RACINE, nom);
    fs.rmSync(cible, { recursive: true, force: true });
    if (nom === 'node_modules') fs.renameSync(path.join(sauvegarde, nom), cible);
    else fs.cpSync(path.join(sauvegarde, nom), cible, { recursive: true, force: true });
  }
  fs.writeFileSync(ECHEC, JSON.stringify({ ...info, raison, quand: Date.now() }, null, 2));
  fs.rmSync(EN_COURS, { force: true });
  console.error(`[lanceur] la version ${info.vers} plante au démarrage : retour à ${info.de}.`);
  return true;
}

function lancer() {
  enfant = spawn(process.execPath, [path.join(RACINE, 'src', 'index.js')], { cwd: RACINE, stdio: 'inherit' });
  enfant.on('exit', (code, signal) => {
    enfant = null;
    if (arret) return process.exit(0);
    if (code === CODE_REDEMARRAGE) return lancer();
    if (fs.existsSync(EN_COURS) && revenirEnArriere(`sortie ${signal || code}`)) return lancer();
    console.error(`[lanceur] le bot s'est arrêté (${signal || code}), relance dans 10 s.`);
    setTimeout(lancer, 10000);
  });
}

for (const s of ['SIGTERM', 'SIGINT']) {
  process.on(s, () => {
    arret = true;
    if (enfant) enfant.kill(s);
    else process.exit(0);
  });
}

lancer();
