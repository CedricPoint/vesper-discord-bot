// Construit les embeds de /id et du salon logs-joueurs à partir de vraies
// réponses de la ressource, et laisse discord.js les valider (taille des
// champs, nombre d'embeds) — sans rien envoyer sur Discord.
//
//   node tests/mise-en-forme.js fiche.json [fiche2.json…]
'use strict';

process.env.DISCORD_TOKEN = process.env.DISCORD_TOKEN || 'test';
const fs = require('fs');
const { embedsFiche, embedEvenement } = require('../src/index.js');

let erreurs = 0;
const ok = (cond, msg) => { console.log(`${cond ? '✓' : '✗'} ${msg}`); if (!cond) erreurs += 1; };

for (const fichier of process.argv.slice(2)) {
  const fiche = JSON.parse(fs.readFileSync(fichier, 'utf8'));
  const lots = embedsFiche(fiche);
  const n = lots.reduce((s, l) => s + l.length, 0);
  ok(n === 1 + (fiche.personnages || []).length, `${fichier} : ${n} embeds (compte + personnages), ${lots.length} message(s)`);
  for (const lot of lots) {
    const json = lot.map((e) => e.toJSON());
    const taille = JSON.stringify(json.map((e) => [e.title, e.description, e.footer, e.fields])).length;
    ok(lot.length <= 10 && taille < 6000, `  message de ${lot.length} embed(s), ~${taille} caractères`);
    for (const e of json) {
      for (const f of e.fields || []) ok(f.value.length <= 1024 && f.name.length <= 256, `    ${f.name} (${f.value.length})`);
    }
  }
}

const j = { id: 3, nom: 'test', discord: '1', licence: 'license:abc', personnage: 'Jean Test', metier_label: 'Police', grade: 'Cadet', liquide: 10, banque: 20, duree: 3700 };
for (const evt of [
  { type: 'arrivee', joueur: j }, { type: 'personnage', joueur: j, nouveau: true },
  { type: 'metier', joueur: j, avant: 'Sans emploi — Chômeur', apres: 'Police — Cadet' },
  { type: 'mort', joueur: j, tueur: { ...j, id: 4 }, cause: 'pistolet' },
  { type: 'depart', joueur: j, raison: 'Exiting' },
  { type: 'redemarrage', joueurs: [j, { ...j, id: 4 }] },
]) {
  const d = embedEvenement(evt).toJSON().description || '';
  ok(d.length > 0 && d.length <= 4096, `événement ${evt.type} : ${d.split('\n')[0]}`);
}

console.log(erreurs ? `\n${erreurs} échec(s)` : '\nTout est valide.');
process.exit(erreurs ? 1 : 0);
