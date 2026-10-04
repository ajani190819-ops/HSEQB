#!/usr/bin/env bash
# ==============================================================================
# Minecraft Bedrock + Java Cross-Play Server Launcher (Linux / macOS)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Memory allocation (adjust as needed for your laptop)
RAM="4G"

# Check server.jar
if [ ! -f "server.jar" ]; then
    echo "[!] server.jar not found."
    read -p "Would you like to run the downloader script now? (y/n) " choice
    case "$choice" in
        y|Y ) ./download_server_and_plugins.sh;;
        * ) echo "Please download server.jar and place it here."; exit 1;;
    esac
fi

# Check Java
if ! command -v java &>/dev/null; then
    echo "[!] ERROR: Java is not installed or not in PATH."
    echo "Please install Java 21 JDK (e.g. Eclipse Temurin 21)."
    exit 1
fi

echo "======================================================================"
echo "  Starting Minecraft Bedrock + Java Server with ${RAM} RAM..."
echo "  Java Port:    25565 (TCP)"
echo "  Bedrock Port: 19132 (UDP)"
echo "======================================================================"

exec java -Xms${RAM} -Xmx${RAM} \
  -XX:+UseG1GC \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+DisableExplicitGC \
  -XX:+AlwaysPreTouch \
  -XX:G1NewSizePercent=30 \
  -XX:G1MaxNewSizePercent=40 \
  -XX:G1ReservePercent=20 \
  -XX:G1HeapWastePercent=5 \
  -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=15 \
  -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 \
  -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem \
  -XX:MaxTenuringThreshold=1 \
  -Dusing.aikars.flags=https://mcflags.emc.gs \
  -Daikars.new.flags=true \
  -jar server.jar --nogui
