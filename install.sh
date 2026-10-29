#!/usr/bin/env bash
# Installe (ou réinstalle) le bot Discord VESPER sur une machine Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/CedricPoint/vesper-discord-bot/main/install.sh | sudo bash
#
# ou, depuis une archive de version décompressée :  sudo bash install.sh
#
# Le bot doit tourner sur la MÊME machine que le serveur FiveM : la ressource
# n'accepte que les demandes venues de 127.0.0.1.
#
# Déjà installé ? Le script garde le .env et data/ (réglages, salons) et ne
# remplace que le code. Ensuite, les mises à jour se font depuis Discord.

set -euo pipefail

DEPOT="CedricPoint/vesper-discord-bot"
DOSSIER="/opt/vesper-discord-bot"
UTILISATEUR="vesperbot"
SERVICE="vesper-discord-bot"

dire() { printf '\n\033[1;35m▸ %s\033[0m\n' "$*"; }
echec() { printf '\n\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }
# Les questions se lisent sur le terminal, même lancé par « curl | bash ».
demander() { local q="$1" def="${2:-}" r; read -r -p "$q${def:+ [$def]} : " r </dev/tty || true; echo "${r:-$def}"; }

[ "$(id -u)" -eq 0 ] || echec "À lancer en root (sudo)."
command -v systemctl >/dev/null || echec "systemd est nécessaire."
command -v node >/dev/null || echec "Node.js 18.17 ou plus est nécessaire (https://nodejs.org)."
command -v npm >/dev/null || echec "npm est nécessaire."
command -v tar >/dev/null || echec "tar est nécessaire."
node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>18||(a===18&&b>=17)?0:1)' \
  || echec "Node.js $(node -v) est trop ancien : 18.17 au minimum."

# ── 1. Les fichiers : à côté du script, sinon la dernière version publiée ──
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /nonexistent)"
TRAVAIL=""
if [ ! -f "$SOURCE/bot/src/index.js" ]; then
  dire "Téléchargement de la dernière version publiée"
  command -v curl >/dev/null || echec "curl est nécessaire."
  TRAVAIL="$(mktemp -d)"
  trap 'rm -rf "$TRAVAIL"' EXIT
  INFO="$(curl -fsSL "https://api.github.com/repos/$DEPOT/releases/latest")"
  VERSION="$(printf '%s' "$INFO" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).tag_name.replace(/^v/,"")))')"
  BASE="https://github.com/$DEPOT/releases/download/v$VERSION/vesper-discord-bot-$VERSION.tgz"
  curl -fsSL -o "$TRAVAIL/a.tgz" "$BASE"
  curl -fsSL -o "$TRAVAIL/a.sha256" "$BASE.sha256"
  [ "$(sha256sum "$TRAVAIL/a.tgz" | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$TRAVAIL/a.sha256")" ] \
    || echec "Empreinte SHA-256 incorrecte : téléchargement abîmé."
  tar -xzf "$TRAVAIL/a.tgz" -C "$TRAVAIL"
  SOURCE="$TRAVAIL"
  echo "Version $VERSION vérifiée."
fi

# ── 2. Utilisateur dédié et code ──────────────────────────────────────────
dire "Installation dans $DOSSIER"
id "$UTILISATEUR" >/dev/null 2>&1 || useradd --system --home-dir "$DOSSIER" --shell /usr/sbin/nologin "$UTILISATEUR"
mkdir -p "$DOSSIER/data"
for f in src package.json package-lock.json lanceur.js avatar.png deploy .env.example; do
  [ -e "$SOURCE/bot/$f" ] || continue
  rm -rf "${DOSSIER:?}/$f"
  cp -r "$SOURCE/bot/$f" "$DOSSIER/$f"
done
chown -R "$UTILISATEUR:$UTILISATEUR" "$DOSSIER"
( cd "$DOSSIER" && sudo -u "$UTILISATEUR" -H env HOME="$DOSSIER" npm ci --omit=dev --no-audit --no-fund >/dev/null )

# ── 3. Réglages (seulement à la première installation) ────────────────────
JETON_PONT=""
if [ ! -f "$DOSSIER/.env" ]; then
  dire "Réglages"
  echo "Jeton du bot : portail https://discord.com/developers/applications → votre application → Bot → Reset Token."
  read -r -s -p "Jeton du bot Discord : " TOKEN </dev/tty || true; echo
  [ -n "${TOKEN:-}" ] || echec "Le jeton du bot est obligatoire."
  FIVEM_URL="$(demander "Adresse HTTP du serveur FiveM vue de cette machine" "http://127.0.0.1:30120")"
  JETON_PONT="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  umask 077
  cat > "$DOSSIER/.env" <<EOF
DISCORD_TOKEN=$TOKEN
# Vide : le bot adopte le serveur Discord où vous l'invitez.
GUILD_ID=
FIVEM_URL=$FIVEM_URL
VESPER_JETON=$JETON_PONT
INTERVALLE=15
EOF
  umask 022
  chown "$UTILISATEUR:$UTILISATEUR" "$DOSSIER/.env"
  chmod 600 "$DOSSIER/.env"
else
  echo "Réglages existants conservés ($DOSSIER/.env)."
  JETON_PONT="$(grep -E '^VESPER_JETON=' "$DOSSIER/.env" | cut -d= -f2-)"
  TOKEN="$(grep -E '^DISCORD_TOKEN=' "$DOSSIER/.env" | cut -d= -f2-)"
fi

# ── 4. La ressource FiveM (facultatif) ────────────────────────────────────
RESSOURCES="$(demander "Dossier « resources » de votre serveur FiveM (vide : je la copierai moi-même)" "")"
if [ -n "$RESSOURCES" ]; then
  [ -d "$RESSOURCES" ] || echec "Dossier introuvable : $RESSOURCES"
  CIBLE="$RESSOURCES/[standalone]/vesper-discord"
  mkdir -p "$CIBLE"
  cp "$SOURCE"/vesper-discord/*.lua "$CIBLE/"
  chown -R "$(stat -c '%U:%G' "$RESSOURCES")" "$CIBLE"
  echo "Ressource copiée dans $CIBLE"
fi

# ── 5. Service ────────────────────────────────────────────────────────────
dire "Service $SERVICE"
cp "$DOSSIER/deploy/$SERVICE.service" "/etc/systemd/system/$SERVICE.service"
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null
systemctl restart "$SERVICE"

# L'identifiant de l'application est la première partie du jeton (base64).
ID_APP="$(printf '%s' "${TOKEN%%.*}" | tr '_-' '/+' | { b="$(cat)"; while [ $(( ${#b} % 4 )) -ne 0 ]; do b="$b="; done; printf '%s' "$b"; } | base64 -d 2>/dev/null || true)"

dire "C'est installé. Il reste trois choses à faire :"
cat <<EOF

 1. Dans le server.cfg de FiveM :

      set vesper_discord_jeton "$JETON_PONT"
      add_ace resource.vesper-discord command.refresh allow
      add_ace resource.vesper-discord command.restart allow
      ensure vesper-discord

    ⚠️ « set », jamais « sets » (un sets est public). Les deux add_ace laissent la
    ressource se recharger seule lors des mises à jour. Puis redémarrez le serveur.

 2. Inviter le bot sur votre serveur Discord :

      https://discord.com/oauth2/authorize?client_id=${ID_APP:-VOTRE_ID_APPLICATION}&permissions=8&scope=bot%20applications.commands

    Il crée seul ses salons et ses rôles, puis se règle avec /config.

 3. (Facultatif) Message de bienvenue : cochez « Server Members Intent »
    dans le portail Discord (Bot → Privileged Gateway Intents), puis /config bienvenue.

 Journal du bot :  journalctl -u $SERVICE -f
EOF
