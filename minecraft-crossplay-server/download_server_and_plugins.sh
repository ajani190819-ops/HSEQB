#!/usr/bin/env bash
# Minecraft Bedrock + Java Cross-Play Server Downloader (Linux/macOS)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${SCRIPT_DIR}/plugins"
mkdir -p "${PLUGINS_DIR}"

echo "======================================================================"
echo "  Minecraft Bedrock + Java Cross-Play Downloader (Bash)"
echo "======================================================================"

# Try Python downloader first if installed
if command -v python3 >/dev/null 2>&1; then
    echo "[*] Python 3 found. Running Python downloader..."
    python3 "${SCRIPT_DIR}/download_server_and_plugins.py"
    exit 0
elif command -v python >/dev/null 2>&1; then
    echo "[*] Python found. Running Python downloader..."
    python "${SCRIPT_DIR}/download_server_and_plugins.py"
    exit 0
fi

# Fallback to curl
echo "[*] Using curl for downloads..."

# 1. PaperMC
echo "[*] Fetching PaperMC..."
PAPER_FALLBACK="https://api.papermc.io/v2/projects/paper/versions/1.21.4/builds/147/downloads/paper-1.21.4-147.jar"
curl -sL -A "Mozilla/5.0" "${PAPER_FALLBACK}" -o "${SCRIPT_DIR}/server.jar"
echo "[+] PaperMC downloaded as server.jar"

# 2. Geyser-Spigot
echo "[*] Fetching Geyser-Spigot..."
GEYSER_URL="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
curl -sL -A "Mozilla/5.0" "${GEYSER_URL}" -o "${PLUGINS_DIR}/Geyser-Spigot.jar"
echo "[+] Geyser-Spigot downloaded"

# 3. Floodgate-Spigot
echo "[*] Fetching Floodgate-Spigot..."
FLOODGATE_URL="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
curl -sL -A "Mozilla/5.0" "${FLOODGATE_URL}" -o "${PLUGINS_DIR}/floodgate-spigot.jar"
echo "[+] Floodgate-Spigot downloaded"

# 4. ViaVersion
echo "[*] Fetching ViaVersion..."
VIAVERSION_URL="https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.2.1/PAPER/ViaVersion-5.2.1.jar"
curl -sL -A "Mozilla/5.0" "${VIAVERSION_URL}" -o "${PLUGINS_DIR}/ViaVersion.jar" || true
echo "[+] ViaVersion downloaded"

echo "======================================================================"
echo "  All downloads complete! Make start.sh executable and run it:"
echo "    chmod +x start.sh && ./start.sh"
echo "======================================================================"
