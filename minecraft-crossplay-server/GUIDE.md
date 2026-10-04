# Master Guide: Setting Up a Minecraft Bedrock + Java Server on Your Laptop

This guide provides complete, step-by-step instructions for running a high-performance **Minecraft Bedrock & Java Cross-Play Server** directly on your laptop using **PaperMC**, **GeyserMC**, and **Floodgate**.

---

## Table of Contents
1. [How Cross-Play Works](#1-how-cross-play-works)
2. [Prerequisites & Java 21 Installation](#2-prerequisites--java-21-installation)
3. [Quick 1-Click Setup & Startup](#3-quick-1-click-setup--startup)
4. [Manual Setup (Alternative)](#4-manual-setup-alternative)
5. [Connecting to Your Server](#5-connecting-to-your-server)
   - [A. On the Same Local Network (LAN / Wi-Fi)](#a-on-the-same-local-network-lan--wi-fi)
   - [B. Playing Over the Internet (Friends at their own houses)](#b-playing-over-the-internet-friends-at-their-own-houses)
     - [Option 1: Playit.gg (Recommended — Zero Port Forwarding / CGNAT Safe)](#option-1-playitgg-recommended--zero-port-forwarding--cgnat-safe)
     - [Option 2: Router Port Forwarding](#option-2-router-port-forwarding)
6. [Bedrock Console Players (Xbox, PlayStation, Nintendo Switch)](#6-bedrock-console-players-xbox-playstation-nintendo-switch)
7. [Laptop Performance & Power Optimization](#7-laptop-performance--power-optimization)
8. [Essential Server Admin Commands](#8-essential-server-admin-commands)
9. [Troubleshooting & FAQ](#9-troubleshooting--faq)

---

## 1. How Cross-Play Works

```
┌────────────────────────────────────────────────────────┐
│                      Your Laptop                       │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │             PaperMC Java Server Core             │  │
│  │                (Port: 25565 TCP)                 │  │
│  └────────▲─────────────────────────▲───────────────┘  │
│           │                         │                  │
│           │ Direct Connection       │ Internal Bridge  │
│           │                         │                  │
│     ┌─────┴────────┐      ┌─────────┴─────────────┐    │
│     │ Java Players │      │  Geyser + Floodgate   │    │
│     │ (PC/Mac/Lnx) │      │   (Port: 19132 UDP)   │    │
│     └──────────────┘      └─────────▲─────────────┘    │
└─────────────────────────────────────┼──────────────────┘
                                      │
                         ┌────────────┴────────────┐
                         │     Bedrock Players     │
                         │ (Win10/11, iOS, Android,│
                         │  Xbox, PS4/PS5, Switch) │
                         └─────────────────────────┘
```

* **PaperMC**: An optimized Java Minecraft server software offering high TPS (ticks-per-second) and plugin support.
* **Geyser**: A proxy plugin that translates Bedrock network packets into Java packets in real-time.
* **Floodgate**: Authenticates Bedrock players via their Microsoft/Xbox accounts so they do not need to purchase a separate Java Edition account.
* **ViaVersion**: Allows players running different Minecraft client versions to connect without version mismatches.

---

## 2. Prerequisites & Java 21 Installation

Modern Minecraft versions (1.20.5 through 1.21+) require **Java 21 (JDK 21)**.

### Windows:
1. Download **Eclipse Temurin 21 (LTS)** installer:
   👉 [Adoptium Temurin 21 JDK Installer (.msi)](https://adoptium.net/temurin/releases/?version=21)
2. Run the `.msi` installer.
3. **IMPORTANT**: In the installer custom setup screen, make sure **"Add to PATH"** and **"Set JAVA_HOME variable"** are set to **"Will be installed on local hard drive"**.
4. Finish installation and restart any open Command Prompt / PowerShell windows.

### macOS:
1. Download Temurin 21 `.pkg` (x64 for Intel Macs, aarch64 for Apple Silicon M1/M2/M3/M4):
   👉 [Adoptium macOS Downloads](https://adoptium.net/temurin/releases/?version=21&os=mac)
2. Or via Homebrew:
   ```bash
   brew install openjdk@21
   ```

### Linux (Ubuntu / Debian / Mint):
```bash
sudo apt update
sudo apt install -y openjdk-21-jdk
```

### Verify Java Installation:
Open your terminal / Command Prompt and run:
```bash
java -version
```
*Expected output: `openjdk version "21.x.x"`*

---

## 3. Quick 1-Click Setup & Startup

All server configuration files in this folder are already optimized and pre-configured.

### On Windows:
1. Double-click **`download_server_and_plugins.bat`**.
   * This automatically fetches the latest `server.jar` (PaperMC), `Geyser-Spigot.jar`, `floodgate-spigot.jar`, and `ViaVersion.jar`.
2. Once downloads complete, double-click **`start.bat`**.
3. Your server will start! The console will display:
   ```
   [Geyser-Spigot] Started Geyser on 0.0.0.0:19132
   [Server thread/INFO]: Done (12.4s)! For help, type "help"
   ```

### On macOS / Linux:
1. Open Terminal in the `minecraft-crossplay-server` directory.
2. Grant execution permissions:
   ```bash
   chmod +x download_server_and_plugins.sh start.sh download_server_and_plugins.py
   ```
3. Run the automated downloader:
   ```bash
   ./download_server_and_plugins.sh
   ```
4. Start the server:
   ```bash
   ./start.sh
   ```

---

## 4. Manual Setup (Alternative)

If you prefer to download files manually without the script:

1. **PaperMC Core**:
   * Visit [PaperMC Downloads](https://papermc.io/downloads/paper).
   * Download the latest build and save it in this folder as `server.jar`.
2. **Geyser Plugin**:
   * Visit [GeyserMC Download](https://geysermc.org/download#geyser).
   * Download **Geyser-Spigot** and place it in the `plugins/` folder.
3. **Floodgate Plugin**:
   * Visit [GeyserMC Floodgate](https://geysermc.org/download#floodgate).
   * Download **Floodgate-Spigot** and place it in the `plugins/` folder.
4. **ViaVersion Plugin**:
   * Visit [ViaVersion Hangar](https://hangar.papermc.io/ViaVersion/ViaVersion).
   * Download the `.jar` and place it in the `plugins/` folder.
5. Launch using `start.bat` (Windows) or `./start.sh` (Mac/Linux).

---

## 5. Connecting to Your Server

### Finding Your Laptop's Local IP Address

* **Windows**: Open Command Prompt, run `ipconfig`, look for **IPv4 Address** under Wi-Fi or Ethernet (e.g., `192.168.1.50`).
* **macOS**: Go to *System Settings > Wi-Fi > Details* or run `ipconfig getifaddr en0` in Terminal.
* **Linux**: Run `hostname -I` in Terminal.

---

### A. On the Same Local Network (LAN / Wi-Fi)

For anyone connected to your home Wi-Fi:

#### 1. Java Edition:
* Open Minecraft Java -> **Multiplayer** -> **Add Server**.
* **If playing on the same laptop hosting the server**:
  * Server Address: `localhost` (or `127.0.0.1`)
* **If playing on another PC in the house**:
  * Server Address: `<Laptop_Local_IP>` (e.g., `192.168.1.50:25565`)

#### 2. Bedrock Edition (Windows, iPhone, iPad, Android):
* Open Minecraft Bedrock -> **Play** -> **Servers** tab -> scroll down to **Add Server**.
* **Server Name**: `My Crossplay Server`
* **Server Address**: `<Laptop_Local_IP>` (e.g., `192.168.1.50`)
* **Port**: `19132` (Default Bedrock Port)
* Click **Save** and then **Join Server**.

---

### B. Playing Over the Internet (Friends at their own houses)

#### Option 1: Playit.gg (Recommended — Zero Port Forwarding / CGNAT Safe)

If you don't have access to your router settings or your ISP blocks incoming ports (CGNAT), **Playit.gg** is the best solution.

1. Download the **Playit.gg Minecraft Plugin**:
   👉 [Playit.gg Paper Plugin](https://playit.gg/download/minecraft-plugin)
2. Place `playit-minecraft-plugin-x.x.x.jar` into your `plugins/` folder.
3. Restart your server.
4. Watch the server console. You will see a claim URL:
   ```
   [playit] Claim your agent: https://playit.gg/claim/xxxx-xxxx
   ```
5. Click the link to link your server to a free Playit.gg account.
6. In your Playit dashboard, create two tunnels:
   * **Tunnel 1 (Java)**: Type `Minecraft Java` -> Local port `25565`
   * **Tunnel 2 (Bedrock)**: Type `Minecraft Bedrock` -> Local port `19132`
7. Playit will give you public domains:
   * Java friends connect to: `something.joinmc.link`
   * Bedrock friends connect to: Address `something.bedrock.joinmc.link` / Port: assigned port number.

---

#### Option 2: Router Port Forwarding

If you have administrative access to your home Wi-Fi router:

1. Open your browser and go to your router's gateway (typically `192.168.1.1` or `192.168.0.1`).
2. Log in and locate the **Port Forwarding** / **Virtual Servers** section.
3. Add two forwarding rules targeting your laptop's **Local IP** (e.g., `192.168.1.50`):

| Rule Name | Protocol | External Port | Internal Port | Internal IP |
| :--- | :--- | :--- | :--- | :--- |
| **MC-Java** | **TCP** | `25565` | `25565` | `<Your_Laptop_IP>` |
| **MC-Bedrock** | **UDP** | `19132` | `19132` | `<Your_Laptop_IP>` |

4. Check your Public IP Address at [whatismyipaddress.com](https://whatismyipaddress.com).
5. Give your friends:
   * **Java Players**: `<Your_Public_IP>:25565`
   * **Bedrock Players**: Server IP: `<Your_Public_IP>`, Port: `19132`

---

## 6. Bedrock Console Players (Xbox, PlayStation, Nintendo Switch)

Consoles do not allow custom server IP input out-of-the-box. Console players can join using either of these two methods:

### Method 1: BedrockTogether Mobile App (Easiest)
1. Have the console player download **BedrockTogether** (Free on iOS App Store & Google Play Store).
2. Connect the phone to the **same Wi-Fi** as the console.
3. In the app:
   * Enter your server's Public or Local IP Address and Port (`19132`).
   * Press **Run**.
4. On the Xbox / PlayStation / Nintendo Switch:
   * Launch Minecraft.
   * Go to **Play** -> **Friends** tab.
   * Look under **LAN Games** — tap the BedrockTogether server to join!

### Method 2: Custom DNS Method (No phone required)
1. On the console, go to **Network Settings** -> **Advanced Settings** -> **DNS Settings** -> **Manual**.
2. Set **Primary DNS** to: `104.238.130.180` (MCServerList Bedrock DNS proxy).
3. Set **Secondary DNS** to: `8.8.8.8` or `1.1.1.1`.
4. Open Minecraft Bedrock on the console.
5. In the **Servers** tab, click to join ANY featured server (e.g., The Hive, Cubecraft).
6. Instead of loading that server, a custom menu will pop up allowing the player to enter your Server IP and Port!

---

## 7. Laptop Performance & Power Optimization

Running a server on a laptop requires keeping the CPU cool and preventing system sleep.

### 1. Power & Sleep Settings (Crucial)
* **Windows**:
  * Open **Settings > System > Power & battery**.
  * Set "When plugged in, turn off my screen after" to desired, but set **"Put my device to sleep after"** to **Never**.
  * Open **Control Panel > Power Options > Choose what closing the lid does** -> Set **When plugged in: Do nothing**.
* **macOS**:
  * Go to **System Settings > Energy Saver / Battery**.
  * Enable **"Prevent automatic sleeping on power adapter when the display is off"**.

### 2. Plug In Power Adapter
Always keep your laptop connected to the wall charger while hosting. On battery power, laptops throttle CPU clocks by 50% or more, causing TPS drops.

### 3. Thermal Management
* Elevate the back of the laptop with a book, stand, or cooling pad to maximize airflow intake.
* Clean any dust from laptop exhaust vents.

### 4. RAM Budgeting
In `start.bat` / `start.sh`, adjust the `RAM=4G` line based on your laptop's total RAM:

| Laptop Total RAM | Server Allocation (`set RAM=`) | Recommended Max Players |
| :--- | :--- | :--- |
| **8 GB RAM** | `3G` or `4G` | 4 – 8 players |
| **16 GB RAM** | `6G` or `8G` | 10 – 20 players |
| **32 GB RAM** | `10G` or `12G` | 20+ players |

---

## 8. Essential Server Admin Commands

Type these directly into your server console window (without `/`) or in-game with OP permissions (with `/`):

| Command | Description |
| :--- | :--- |
| `op <username>` | Grants full admin / operator rights to a player. *(Note: For Bedrock players, use `.PlayerName` if username-prefix is `.`)* |
| `deop <username>` | Revokes operator status. |
| `gamemode creative <player>` | Sets game mode to Creative. |
| `whitelist on` | Enables server whitelist. |
| `whitelist add <player>` | Adds a player to the whitelist. |
| `kick <player> [reason]` | Kicks a player off the server. |
| `ban <player> [reason]` | Bans a player from the server. |
| `save-all` | Forces the server to save the world to disk. |
| `stop` | Safely saves and closes the server. |

---

## 9. Troubleshooting & FAQ

### Q1: Bedrock players see "Unable to connect to world"
1. Verify UDP port `19132` is open on your Windows Firewall.
2. In Windows Defender Firewall:
   * Click **Advanced settings** -> **Inbound Rules** -> **New Rule**.
   * Select **Port** -> **UDP** -> Specific local ports: `19132` -> **Allow the connection** -> Name it `Minecraft Bedrock UDP`.
3. Verify Geyser loaded properly in console (`[Geyser-Spigot] Started Geyser on 0.0.0.0:19132`).

### Q2: Bedrock players are asked to log into a Java account
* This happens if Floodgate is missing.
* Ensure `plugins/floodgate-spigot.jar` exists and that `auth-type: floodgate` is set in `plugins/Geyser-Spigot/config.yml`.

### Q3: Server crashes with `java.lang.OutOfMemoryError`
* Reduce RAM allocation in `start.bat` / `start.sh` (e.g. from `6G` to `4G` or `3G`).
* Close heavy background apps on your laptop (Chrome tabs, video editors, other games).

### Q4: "Failed to bind to port" (Address already in use)
* Another Minecraft server or application is already running on port 25565 or 19132.
* Open Task Manager / Activity Monitor, terminate any remaining `java` or `javaw.exe` processes, and run `start.bat` again.

### Q5: Bedrock custom skins / capes don't appear
* Floodgate synchronizes Bedrock skins automatically. If a skin fails to show, ensure `send-floodgate-data: true` is enabled in `plugins/floodgate/config.yml`.

---

🎉 **You're all set! Enjoy playing together across PC, Mobile, and Consoles!**
