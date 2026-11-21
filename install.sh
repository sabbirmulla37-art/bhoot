#!/usr/bin/env bash
# SiftNodes VPS Bot - installer
# Debian/Ubuntu + Python venv + Discord voice dependencies + FFmpeg + Docker
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$0")")"

if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

printf '\n=== SiftNodes VPS Bot Setup ===\n'

if ! command -v apt-get >/dev/null 2>&1; then
    echo "This installer supports Debian/Ubuntu apt systems only." >&2
    exit 1
fi

echo "[1/6] Updating packages..."
$SUDO apt-get update

echo "[2/6] Installing system dependencies..."
$SUDO apt-get install -y \
    python3 \
    python3-venv \
    python3-pip \
    ca-certificates \
    curl \
    ffmpeg \
    libffi-dev \
    libnacl-dev \
    build-essential

echo "[3/6] Creating/updating Python virtual environment..."
if [[ ! -x "$PWD/venv/bin/python" ]]; then
    rm -rf "$PWD/venv"
    python3 -m venv "$PWD/venv"
fi

PY="$PWD/venv/bin/python"
PIP="$PWD/venv/bin/pip"

"$PY" -m pip install --upgrade pip setuptools wheel

echo "[3.1/6] Installing Discord + voice dependencies..."
"$PIP" install --upgrade \
    'discord.py>=2.3,<3' \
    'discord.py[voice]>=2.3,<3' \
    'aiohttp>=3.9,<4' \
    'PyNaCl>=1.5.0' \
    'davey' \
    'audioop-lts' \
    'python-dotenv>=1.0.0'

echo "[3.2/6] Checking voice support..."
"$PY" -c "import discord, nacl, davey; print('VOICE SUPPORT: OK')"

read -r -p "Install Docker Engine? [Y/n]: " DOCKER
DOCKER="${DOCKER:-Y}"

if [[ "$DOCKER" =~ ^[Yy]$ ]]; then
    echo "[4/6] Installing Docker..."
    $SUDO apt-get install -y docker.io
    if command -v systemctl >/dev/null 2>&1; then
        $SUDO systemctl enable --now docker || true
    fi
else
    echo "[4/6] Docker installation skipped."
fi

ENV_FILE="$PWD/sift.env"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

setkv() {
    local key="$1"
    local value="$2"
    local tmp
    tmp="$(mktemp)"
    grep -v "^${key}=" "$ENV_FILE" > "$tmp" || true
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    cat "$tmp" > "$ENV_FILE"
    rm -f "$tmp"
    chmod 600 "$ENV_FILE"
}

echo "[5/6] Configuring bot..."

read -r -p "Website URL (e.g. https://terminal.example.com): " URL
URL="${URL%/}"

if [[ ! "$URL" =~ ^https?://[^[:space:]]+$ ]]; then
    echo "Invalid URL. Use http:// or https://." >&2
    exit 1
fi

read -r -p "Owner Discord User ID: " OWNER_ID

if [[ ! "$OWNER_ID" =~ ^[0-9]{15,22}$ ]]; then
    echo "Invalid Discord User ID." >&2
    exit 1
fi

read -r -s -p "Discord bot token: " TOKEN
echo

if [[ -z "$TOKEN" || "$TOKEN" == *$'\n'* ]]; then
    echo "Bot token cannot be empty." >&2
    exit 1
fi

read -r -s -p "Groq AI API key: " GROQ_KEY
echo

if [[ -z "$GROQ_KEY" || "$GROQ_KEY" == *$'\n'* ]]; then
    echo "Groq AI API key cannot be empty." >&2
    exit 1
fi

read -r -s -p "Tailscale auth key (optional, press Enter to skip): " TS_KEY
echo

setkv SIFT_WEB_URL "$URL"
setkv SIFT_OWNER_ID "$OWNER_ID"
setkv DISCORD_TOKEN "$TOKEN"
setkv GROQ_API_KEY "$GROQ_KEY"

if [[ -n "$TS_KEY" ]]; then
    setkv TAILSCALE_AUTH_KEY "$TS_KEY"
else
    setkv TAILSCALE_AUTH_KEY ""
fi

unset TOKEN GROQ_KEY TS_KEY

chmod 600 "$ENV_FILE"

echo "[5.1/6] Checking FFmpeg..."
if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -version | head -n 1
else
    echo "WARNING: FFmpeg was not found." >&2
fi

echo "[5.2/6] Checking Discord voice modules..."
"$PY" - <<'PY'
import discord
import nacl
import davey

print("discord.py :", discord.__version__)
print("PyNaCl     : OK")
print("davey      : OK")
print("Voice      : READY")
PY

if [[ ! -f "$PWD/bot.py" ]]; then
    echo "bot.py not found beside installer." >&2
    exit 1
fi

echo "[6/6] Restarting SiftNodes bot..."

if command -v pgrep >/dev/null 2>&1; then
    while read -r pid; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done < <(pgrep -f "$PWD/bot.py" || true)
fi

sleep 2

nohup "$PY" "$PWD/bot.py" >> "$PWD/sift.log" 2>&1 < /dev/null &

PID=$!

echo
echo "=========================================="
echo " SiftNodes installation completed!"
echo "=========================================="
echo "Bot PID : $PID"
echo "Python  : $PY"
echo "Log     : $PWD/sift.log"
echo "Config  : $ENV_FILE"
echo "AI API   : CONFIGURED"
if grep -q "^TAILSCALE_AUTH_KEY=.\+" "$ENV_FILE"; then echo "Tailscale: AUTH KEY CONFIGURED"; else echo "Tailscale: MANUAL AUTH MODE"; fi
echo
echo "Voice dependencies: INSTALLED"
echo "FFmpeg: INSTALLED"
echo "PyNaCl: INSTALLED"
echo "davey: INSTALLED"
echo
echo "View logs:"
echo "tail -f $PWD/sift.log"
echo
echo "IMPORTANT:"
echo "Discord server/channel permissions still need View Channel,"
echo "Connect and Speak for the bot in the voice channel."
echo "=========================================="
