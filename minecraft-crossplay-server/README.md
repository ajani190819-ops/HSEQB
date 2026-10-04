# 🎮 Minecraft Bedrock + Java Cross-Play Server Kit

A ready-to-run, fully configured Minecraft cross-play server package optimized for hosting on a laptop.

Allows players from **Minecraft Java Edition** (PC, Mac, Linux) and **Minecraft Bedrock Edition** (Windows 10/11, iOS, Android, Xbox, PlayStation, Nintendo Switch) to play together in the same world!

---

## ⚡ Quick Start (2-Minute Setup)

### 1. Requirements
* **Java 21 JDK** installed on your laptop: [Download Eclipse Temurin 21 (LTS)](https://adoptium.net/temurin/releases/?version=21)

### 2. Windows Users:
1. Double-click **`download_server_and_plugins.bat`** (downloads the latest PaperMC, Geyser, Floodgate, and ViaVersion).
2. Double-click **`start.bat`** to start your server.

### 3. macOS / Linux Users:
1. Open Terminal in this folder and make scripts executable:
   ```bash
   chmod +x *.sh *.py
   ```
2. Run the downloader:
   ```bash
   ./download_server_and_plugins.sh
   ```
3. Run the server launcher:
   ```bash
   ./start.sh
   ```

---

## 📁 Package Contents

| File / Folder | Description |
| :--- | :--- |
| **`GUIDE.md`** | **Complete step-by-step master guide** (networking, internet hosting, console setup, laptop tuning). |
| **`download_server_and_plugins.bat`** | Windows 1-click installer script. |
| **`download_server_and_plugins.sh`** | macOS / Linux installer script. |
| **`download_server_and_plugins.ps1`** | Native PowerShell downloader. |
| **`download_server_and_plugins.py`** | Cross-platform Python 3 downloader. |
| **`start.bat`** | Windows server launch script with Aikar's optimized G1GC flags. |
| **`start.sh`** | macOS / Linux launch script. |
| **`eula.txt`** | Pre-accepted Minecraft EULA. |
| **`server.properties`** | Pre-configured and optimized server properties. |
| **`bukkit.yml` & `spigot.yml`** | Tuned spawn limits and entity activation ranges for laptop CPU/battery efficiency. |
| **`config/`** | Paper engine global and world optimization configurations. |
| **`plugins/Geyser-Spigot/config.yml`** | Configured Bedrock protocol bridge (`port: 19132`, Floodgate auth). |
| **`plugins/floodgate/config.yml`** | Configured Xbox Live authentication and prefix handling. |

---

## 🌐 Network Ports

* **Java Edition Port**: `25565` (**TCP**)
* **Bedrock Edition Port**: `19132` (**UDP**)

For detailed instructions on port forwarding, zero-config Playit.gg tunneling, console joining, and laptop performance tips, open **`GUIDE.md`**.
