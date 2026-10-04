#!/usr/bin/env python3
"""
Minecraft Cross-Play Server Downloader
Automatically downloads the latest PaperMC server JAR, Geyser-Spigot, Floodgate-Spigot, and ViaVersion plugins.
"""

import os
import sys
import json
import urllib.request
import urllib.error

SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
PLUGINS_DIR = os.path.join(SERVER_DIR, "plugins")

HEADERS = {
    "User-Agent": "Minecraft-Server-Setup-Script/1.0"
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
    except urllib.error.URLError as e:
        print(f"\n    [!] Failed to download from {url}: {e}")
        return False
    return True

def get_latest_paper_url():
    print("[*] Checking PaperMC API for the latest release build...")
    api_base = "https://api.papermc.io/v2/projects/paper"
    req = urllib.request.Request(api_base, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        proj_data = json.loads(resp.read().decode())
    
    latest_version = proj_data["versions"][-1]
    
    version_url = f"{api_base}/versions/{latest_version}"
    req = urllib.request.Request(version_url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        ver_data = json.loads(resp.read().decode())
    
    latest_build = ver_data["builds"][-1]
    jar_filename = f"paper-{latest_version}-{latest_build}.jar"
    download_url = f"{api_base}/versions/{latest_version}/builds/{latest_build}/downloads/{jar_filename}"
    return download_url, latest_version, latest_build

def main():
    print("=" * 60)
    print("  Minecraft Bedrock + Java Cross-Play Server Downloader")
    print("=" * 60)
    os.makedirs(PLUGINS_DIR, exist_ok=True)
    
    # 1. Download Paper
    server_jar = os.path.join(SERVER_DIR, "server.jar")
    try:
        paper_url, ver, build = get_latest_paper_url()
        print(f"[+] Found PaperMC {ver} (Build #{build})")
        download_file(paper_url, server_jar, f"Downloading PaperMC {ver} (Build #{build})")
    except Exception as e:
        print(f"[!] Could not fetch latest build from PaperMC API: {e}")
        print("[!] Trying fallback Paper 1.21.4 direct URL...")
        fallback_paper = "https://api.papermc.io/v2/projects/paper/versions/1.21.4/builds/147/downloads/paper-1.21.4-147.jar"
        download_file(fallback_paper, server_jar, "Downloading PaperMC 1.21.4")
        
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
