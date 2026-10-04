#!/usr/bin/env python3
"""
Minecraft Cross-Play Server Downloader
Automatically downloads the server JAR, Geyser-Spigot, Floodgate-Spigot, and ViaVersion plugins.
"""

import os
import sys
import json
import urllib.request
import urllib.error

SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
PLUGINS_DIR = os.path.join(SERVER_DIR, "plugins")

HEADERS = {
    "User-Agent": "Minecraft-Crossplay-Setup/1.0 (server@laptop)"
}

def download_file(url, dest_path, desc="Downloading"):
    print(f"[*] {desc}...")
    print(f"    URL: {url}")
    print(f"    Destination: {dest_path}")
    
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as response, open(dest_path, "wb") as out_file:
            total_size = response.getheader("Content-Length")
            total_size = int(total_size) if total_size else None
            downloaded = 0
            block_size = 65536
            
            while True:
                buffer = response.read(block_size)
                if not buffer:
                    break
                downloaded += len(buffer)
                out_file.write(buffer)
                if total_size:
                    percent = (downloaded / total_size) * 100
                    mb_downloaded = downloaded / (1024 * 1024)
                    mb_total = total_size / (1024 * 1024)
                    sys.stdout.write(f"\r    Progress: {percent:5.1f}% ({mb_downloaded:.1f}/{mb_total:.1f} MB)")
                    sys.stdout.flush()
                else:
                    mb_downloaded = downloaded / (1024 * 1024)
                    sys.stdout.write(f"\r    Downloaded: {mb_downloaded:.1f} MB")
                    sys.stdout.flush()
            print("\n    [+] Done!")
    except Exception as e:
        print(f"\n    [!] Failed to download from {url}: {e}")
        return False
    return True

def get_latest_server_url():
    print("[*] Checking Purpur / Paper API for latest build...")
    try:
        api_base = "https://api.purpurmc.org/v2/purpur"
        req = urllib.request.Request(api_base, headers=HEADERS)
        with urllib.request.urlopen(req) as resp:
            proj_data = json.loads(resp.read().decode())
        latest_version = proj_data["versions"][-1]
        download_url = f"{api_base}/{latest_version}/latest/download"
        return download_url, latest_version
    except Exception as e:
        print(f"[!] Purpur API check skipped: {e}")
    
    return "https://api.purpurmc.org/v2/purpur/1.21.4/latest/download", "1.21.4"

def main():
    print("=" * 60)
    print("  Minecraft Bedrock + Java Cross-Play Server Downloader")
    print("=" * 60)
    os.makedirs(PLUGINS_DIR, exist_ok=True)
    
    # 1. Download Server Core
    server_jar = os.path.join(SERVER_DIR, "server.jar")
    server_url, ver = get_latest_server_url()
    download_file(server_url, server_jar, f"Downloading Minecraft Server Core ({ver})")
        
    # 2. Download Geyser-Spigot
    geyser_jar = os.path.join(PLUGINS_DIR, "Geyser-Spigot.jar")
    geyser_url = "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
    download_file(geyser_url, geyser_jar, "Downloading Geyser-Spigot (Bedrock Support)")
    
    # 3. Download Floodgate-Spigot
    floodgate_jar = os.path.join(PLUGINS_DIR, "floodgate-spigot.jar")
    floodgate_url = "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
    download_file(floodgate_url, floodgate_jar, "Downloading Floodgate-Spigot (Account Linker)")

    # 4. Download ViaVersion
    viaversion_jar = os.path.join(PLUGINS_DIR, "ViaVersion.jar")
    viaversion_url = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.2.1/PAPER/ViaVersion-5.2.1.jar"
    download_file(viaversion_url, viaversion_jar, "Downloading ViaVersion (Multi-client version support)")

    print("\n" + "=" * 60)
    print("  All files downloaded successfully!")
    print("  You can now start the server by running:")
    print("    Windows:       start.bat")
    print("    macOS / Linux: ./start.sh")
    print("=" * 60)

if __name__ == "__main__":
    main()
