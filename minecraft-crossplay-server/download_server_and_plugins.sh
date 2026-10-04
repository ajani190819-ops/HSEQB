#!/usr/bin/env bash
# Minecraft Bedrock + Java Cross-Play Server 1-Click Installer (Linux / macOS)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "======================================================================"
echo "  Minecraft Bedrock + Java Cross-Play Server 1-Click Installer"
echo "======================================================================"
echo ""

# 1. Check for Java
if ! command -v java &>/dev/null; then
    echo "[!] WARNING: Java was not found in your PATH."
    echo "    Please install OpenJDK 21 (e.g., sudo apt install openjdk-21-jdk / brew install openjdk@21)"
    echo ""
else
    echo "[+] Java is installed."
fi

# 2. Ensure directories exist
mkdir -p plugins/Geyser-Spigot plugins/floodgate plugins/ViaVersion config

# 3. Download PaperMC
echo "[*] [1/4] Downloading PaperMC (server.jar)..."
PAPER_URL="https://api.papermc.io/v2/projects/paper/versions/1.21.4/builds/147/downloads/paper-1.21.4-147.jar"
curl -sL -A "Mozilla/5.0" "${PAPER_URL}" -o server.jar
echo "[+] PaperMC downloaded."

# 4. Download Geyser
echo "[*] [2/4] Downloading Geyser-Spigot (Bedrock protocol support)..."
GEYSER_URL="https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
curl -sL -A "Mozilla/5.0" "${GEYSER_URL}" -o plugins/Geyser-Spigot.jar
echo "[+] Geyser-Spigot downloaded."

# 5. Download Floodgate
echo "[*] [3/4] Downloading Floodgate-Spigot (Bedrock Xbox authentication)..."
FLOODGATE_URL="https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
curl -sL -A "Mozilla/5.0" "${FLOODGATE_URL}" -o plugins/floodgate-spigot.jar
echo "[+] Floodgate-Spigot downloaded."

# 6. Download ViaVersion
echo "[*] [4/4] Downloading ViaVersion (Multi-version support)..."
VIA_URL="https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.2.1/PAPER/ViaVersion-5.2.1.jar"
curl -sL -A "Mozilla/5.0" "${VIA_URL}" -o plugins/ViaVersion.jar || true
echo "[+] ViaVersion downloaded."

# 7. Auto-generate eula.txt if missing
if [ ! -f "eula.txt" ]; then
    echo "eula=true" > eula.txt
    echo "[+] Created eula.txt"
fi

# 8. Auto-generate start.sh if missing
if [ ! -f "start.sh" ]; then
cat << 'EOF' > start.sh
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
RAM="4G"
echo "Starting Minecraft Server with ${RAM} RAM..."
exec java -Xms${RAM} -Xmx${RAM} -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -jar server.jar --nogui
EOF
    chmod +x start.sh
    echo "[+] Created start.sh"
fi

echo ""
echo "======================================================================"
echo "  SETUP COMPLETE!"
echo ""
echo "  To start your Minecraft server:"
echo "    chmod +x start.sh && ./start.sh"
echo "======================================================================"
