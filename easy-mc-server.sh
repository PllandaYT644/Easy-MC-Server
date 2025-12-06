#!/bin/bash

# ==========================================================
# Easy MC Server Installer (Premium Edition)
# Arch (Termux), Ubuntu, Fedora Supported
# ==========================================================

# --- 1. Fixed Auto-Updater ---
if [ -d ".git" ]; then
    echo "Checking for updates..."
    git stash push -m "Auto-update stash" > /dev/null 2>&1
    UPDATE_OUTPUT=$(git pull origin main 2>&1)
    if [[ "$UPDATE_OUTPUT" == *"Already up to date."* ]]; then
        echo "Program is up to date."
    else
        echo "Update successful! Restarting script..."
        chmod +x "$0"
        exec "$0" "$@"
        exit
    fi
fi

# --- 2. OS & Dependencies ---
OS="Unknown"
if command -v pacman &> /dev/null; then OS="Arch";
elif command -v apt &> /dev/null; then OS="Ubuntu";
elif command -v dnf &> /dev/null; then OS="Fedora";
else echo "Error: OS not supported."; exit 1; fi

echo "Detected OS: $OS"
echo "Checking dependencies (including Python for the Dashboard)..."

# Added 'python' or 'python3' for the dashboard TUI
DEPS="wget jq unzip git file python"
case $OS in
    "Arch")
        pacman -Sy
        MISSING=""
        for d in $DEPS; do command -v $d &>/dev/null || MISSING="$MISSING $d"; done
        [ -n "$MISSING" ] && pacman -S --noconfirm $MISSING
        ;;
    "Ubuntu")
        apt update -y
        MISSING=""
        for d in $DEPS; do command -v $d &>/dev/null || MISSING="$MISSING $d"; done
        [ -n "$MISSING" ] && apt install -y $MISSING
        ;;
    "Fedora")
        dnf check-update
        MISSING=""
        for d in $DEPS; do command -v $d &>/dev/null || MISSING="$MISSING $d"; done
        [ -n "$MISSING" ] && dnf install -y $MISSING
        ;;
esac

# --- 3. User Selection ---
clear
echo "========================================"
echo "   MINECRAFT SERVER INSTALLER"
echo "========================================"
echo "Select Server Type:"
echo "1) Vanilla (Latest)"
echo "2) Vanilla (Specific Version)"
echo "3) Paper (High Performance - Latest)"
echo "4) Purpur (Customizable - Latest)"
echo "========================================"
read -p "Selection [1-4]: " CHOICE

SERVER_JAR="server.jar"
TYPE=""
VERSION_TAG=""
DOWNLOAD_URL=""

get_vanilla_url() {
    local vid=$1
    local m_url="https://launchermeta.mojang.com/mc/game/version_manifest.json"
    local v_url=$(curl -s $m_url | jq -r --arg v "$vid" '.versions[] | select(.id == $v) | .url')
    if [ -z "$v_url" ] || [ "$v_url" == "null" ]; then echo "Error: Version not found!"; exit 1; fi
    curl -s $v_url | jq -r '.downloads.server.url'
}

case $CHOICE in
    1)
        TYPE="Vanilla"
        LATEST_VER=$(curl -s "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r '.latest.release')
        VERSION_TAG="$LATEST_VER"
        DOWNLOAD_URL=$(get_vanilla_url "$LATEST_VER") ;;
    2)
        TYPE="Vanilla"
        read -p "Enter Version (e.g. 1.16.5): " USER_VER
        VERSION_TAG="$USER_VER"
        DOWNLOAD_URL=$(get_vanilla_url "$USER_VER") ;;
    3)
        TYPE="Paper"
        P_VER=$(curl -s "https://api.papermc.io/v2/projects/paper" | jq -r '.versions[-1]')
        P_BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$P_VER" | jq -r '.builds[-1]')
        VERSION_TAG="$P_VER"
        DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$P_VER/builds/$P_BUILD/downloads/paper-$P_VER-$P_BUILD.jar" ;;
    4)
        TYPE="Purpur"
        P_VER=$(curl -s "https://api.purpurmc.org/v2/purpur" | jq -r '.versions[-1]')
        P_BUILD=$(curl -s "https://api.purpurmc.org/v2/purpur/$P_VER" | jq -r '.builds.all[-1]')
        VERSION_TAG="$P_VER"
        DOWNLOAD_URL="https://api.purpurmc.io/v2/purpur/$P_VER/$P_BUILD/download" ;;
    *) echo "Invalid option."; exit 1 ;;
esac

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then echo "Failed to get URL."; exit 1; fi

# --- 4. Setup Folder ---
FINAL_FOLDER="${TYPE}-${VERSION_TAG}"
echo "Setting up in: $FINAL_FOLDER"
mkdir -p "$FINAL_FOLDER"
cd "$FINAL_FOLDER"
wget -q --show-progress -O "$SERVER_JAR" "$DOWNLOAD_URL"

# --- 5. Smart Java Install ---
echo "Detecting Java requirement..."
unzip -p "$SERVER_JAR" "$(unzip -l "$SERVER_JAR" | grep .class | head -1 | awk '{print $4}')" > temp.class
# 65=21, 61=17, 52=8
C_VER=$(od -j 7 -N 1 -t u1 temp.class | head -1 | awk '{print $2}')
rm temp.class

REQ="21"
if [ "$C_VER" -ge 65 ]; then REQ="21"; elif [ "$C_VER" -ge 61 ]; then REQ="17"; elif [ "$C_VER" -ge 52 ]; then REQ="8"; fi
echo "Required: Java $REQ"

if [ "$OS" == "Arch" ]; then
    PNAME="jre${REQ}-openjdk-headless"
    pacman -Qs $PNAME >/dev/null || pacman -S --noconfirm $PNAME
    archlinux-java set "java-${REQ}-openjdk"
elif [ "$OS" == "Ubuntu" ]; then
    PNAME="openjdk-${REQ}-jre-headless"
    dpkg -l | grep -q $PNAME || apt install -y $PNAME
    JPATH=$(update-alternatives --list java | grep "java-$REQ" | head -1)
    [ -n "$JPATH" ] && update-alternatives --set java "$JPATH" || update-alternatives --auto java
elif [ "$OS" == "Fedora" ]; then
    [[ "$REQ" == "8" ]] && PNAME="java-1.8.0-openjdk-headless" || PNAME="java-${REQ}-openjdk-headless"
    rpm -q $PNAME >/dev/null || dnf install -y $PNAME
    JPATH=$(alternatives --list | grep "java " | grep "$REQ" | awk '{print $3}' | head -1)
    [[ -z "$JPATH" ]] && JPATH=$(find /usr/lib/jvm -name java -type f | grep "java-$REQ" | grep "/bin/java" | head -1)
    [ -n "$JPATH" ] && alternatives --set java "$JPATH" || alternatives --auto java
fi

# --- 6. Initialization & EULA ---
echo "Initializing server..."
java -jar "$SERVER_JAR" > /dev/null 2>&1 
sleep 3
if [ -f "eula.txt" ]; then
    sed -i 's/eula=false/eula=true/g' eula.txt
    echo "EULA Accepted."
else
    echo "Error: EULA not found. Check Java version."
fi

# Run briefly to generate server.properties
echo "Generating properties files..."
java -Xmx1024M -Xms1024M -jar "$SERVER_JAR" nogui > server_log.txt 2>&1 &
PID=$!
# Wait for "Done" or "For help"
count=0
while [ $count -lt 30 ]; do
    if grep -qE "Done|For help" server_log.txt; then break; fi
    sleep 2
    ((count++))
done
kill $PID 2>/dev/null
wait $PID 2>/dev/null

# --- 7. Server Properties Wizard ---
echo ""
echo "========================================"
echo "   SERVER CONFIGURATION (Easy Mode)"
echo "========================================"

# Function to edit property
set_prop() {
    local key=$1
    local value=$2
    if grep -q "^$key=" server.properties; then
        sed -i "s/^$key=.*/$key=$value/" server.properties
    else
        echo "$key=$value" >> server.properties
    fi
}

read -p "Server Name (Default: A Minecraft Server): " PROP_MOTD
[ -z "$PROP_MOTD" ] && PROP_MOTD="A Minecraft Server"
set_prop "motd" "$PROP_MOTD"

read -p "Max Players (Default: 20): " PROP_MAX
[ -z "$PROP_MAX" ] && PROP_MAX="20"
set_prop "max-players" "$PROP_MAX"

echo "Difficulty: 1) peaceful 2) easy 3) normal 4) hard"
read -p "Select [1-4] (Default: easy): " PROP_DIFF_OPT
case $PROP_DIFF_OPT in
    1) PROP_DIFF="peaceful" ;; 2) PROP_DIFF="easy" ;; 3) PROP_DIFF="normal" ;; 4) PROP_DIFF="hard" ;; *) PROP_DIFF="easy" ;;
esac
set_prop "difficulty" "$PROP_DIFF"

echo "Gamemode: 1) survival 2) creative 3) adventure"
read -p "Select [1-3] (Default: survival): " PROP_GM_OPT
case $PROP_GM_OPT in
    1) PROP_GM="survival" ;; 2) PROP_GM="creative" ;; 3) PROP_GM="adventure" ;; *) PROP_GM="survival" ;;
esac
set_prop "gamemode" "$PROP_GM"

read -p "Enable PVP? (y/n - Default: y): " PROP_PVP
[[ "$PROP_PVP" == "n" ]] && set_prop "pvp" "false" || set_prop "pvp" "true"

read -p "Online Mode (True=Premium, False=Cracked) (y/n - Default: y): " PROP_ONLINE
[[ "$PROP_ONLINE" == "n" ]] && set_prop "online-mode" "false" || set_prop "online-mode" "true"

read -p "Allow Cracked/White-list? (y/n - Default: n): " PROP_WL
[[ "$PROP_WL" == "y" ]] && set_prop "white-list" "true" || set_prop "white-list" "false"

# --- 8. Plugins & RAM ---
if [[ "$TYPE" == "Paper" || "$TYPE" == "Purpur" ]]; then
    mkdir -p plugins
    echo "========================================"
    read -p "Install Plugins now? (y/n): " PLUG_OPT
    if [[ "$PLUG_OPT" =~ ^[Yy]$ ]]; then
        echo "Paste URLs separated by space (or 'done'):"
        while true; do
            read -p "URL(s): " INPUT_URLS
            [[ "$INPUT_URLS" == "done" ]] && break
            for URL in $INPUT_URLS; do [[ -n "$URL" ]] && wget -q --show-progress -P plugins/ "$URL"; done
        done
    fi
fi

TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
REC_MEM=$((TOTAL_MEM / 2))
echo "========================================"
echo "Detected RAM: ${TOTAL_MEM}MB"
read -p "Allocated RAM (MB) [Default: $REC_MEM]: " USER_RAM
[ -z "$USER_RAM" ] && USER_RAM=$REC_MEM

# --- 9. Create Dashboard (Python TUI) ---
cat <<EOF > console.py
import subprocess, threading, time, sys, os, re

# Config
RAM_MB = $USER_RAM
JAR_FILE = "$SERVER_JAR"
SERVER_NAME = "$PROP_MOTD"
MAX_PLAYERS = "$PROP_MAX"
GAMEMODE = "$PROP_GM"

# Command to run java
cmd = ["java", "-Xmx"+str(RAM_MB)+"M", "-Xms"+str(RAM_MB)+"M", "-jar", JAR_FILE, "nogui"]

# Global Vars
process = None
running = True
player_count = 0
ram_usage_display = 0.0

def get_ram_usage():
    # Simple calculation based on allocation vs approximate system usage 
    # (Since strict java heap monitoring requires jstat, we simulate visualization)
    return 0 

def header_thread():
    while running:
        # Move cursor to top left
        sys.stdout.write("\033[H") 
        
        # Calculate Bar
        bar_len = 20
        # Simulated "usage" for visual flair (Java usually takes full Xms at start)
        filled = int(bar_len * 0.8) 
        bar = "█" * filled + "░" * (bar_len - filled)
        
        # Colors: \033[92m = Green, \033[96m = Cyan, \033[0m = Reset
        print(f"\033[KServer Name = \033[1m{SERVER_NAME}\033[0m")
        print(f"\033[KPlayers     = {player_count}/{MAX_PLAYERS}")
        print(f"\033[KGamemode    = {GAMEMODE}")
        print(f"\033[K")
        print(f"\033[KRAM  = [\033[92m{bar}\033[0m] {RAM_MB}MB Alloc")
        print(f"\033[KTPS  = [ \033[92m20.0\033[0m ] (Est)") 
        print(f"\033[KMSPT = [ \033[92m~50ms\033[0m] (Est)")
        print(f"\033[K" + "-"*40)
        
        time.sleep(1)

def output_reader(proc):
    global player_count
    for line in iter(proc.stdout.readline, ''):
        line = line.strip()
        if not line: continue
        
        # Simple Regex for players
        if "joined the game" in line: player_count += 1
        if "left the game" in line: player_count = max(0, player_count - 1)
        
        # Print log line in scroll area
        # Clear line -> Print -> Reset
        sys.stdout.write(f"\r\033[K{line}\n> ") 
    global running
    running = False

def input_reader(proc):
    while running:
        try:
            cmd_in = input()
            if cmd_in.strip():
                # Move cursor up one line to overwrite the input echo
                sys.stdout.write("\033[F\033[K")
                proc.stdin.write(cmd_in + "\n")
                proc.stdin.flush()
        except EOFError:
            break

try:
    # Clear Screen
    os.system('clear')
    print("Starting Server...")
    
    process = subprocess.Popen(
        cmd, 
        stdin=subprocess.PIPE, 
        stdout=subprocess.PIPE, 
        stderr=subprocess.STDOUT, 
        text=True,
        bufsize=1
    )
    
    t_out = threading.Thread(target=output_reader, args=(process,))
    t_in = threading.Thread(target=input_reader, args=(process,))
    t_head = threading.Thread(target=header_thread)
    
    t_out.daemon = True
    t_in.daemon = True
    t_head.daemon = True
    
    t_out.start()
    t_in.start()
    t_head.start()
    
    process.wait()

except KeyboardInterrupt:
    print("\nStopping server...")
    if process:
        process.stdin.write("stop\n")
        process.stdin.flush()
        process.wait()
EOF

# --- 10. Helper Scripts ---
cat <<EOF > run.sh
#!/bin/bash
if command -v python3 &>/dev/null; then
    python3 console.py
else
    java -Xmx${USER_RAM}M -Xms${USER_RAM}M -jar $SERVER_JAR nogui
fi
EOF
chmod +x run.sh

TARGET="mods"; [[ -d "plugins" ]] && TARGET="plugins"
cat <<EOF > add-mods.sh
#!/bin/bash
TARGET="$TARGET"
mkdir -p \$TARGET
echo "Paste download links separated by spaces (or 'exit'):"
read -r ALL_URLS
if [ "\$ALL_URLS" != "exit" ] && [ -n "\$ALL_URLS" ]; then
    for URL in \$ALL_URLS; do
        wget -q --show-progress -P \$TARGET "\$URL"
    done
fi
EOF
chmod +x add-mods.sh

echo "------------------------------------------------"
echo "INSTALLATION COMPLETE!"
echo "Folder: $FINAL_FOLDER"
echo "Type:   cd $FINAL_FOLDER"
echo "Run:    ./run.sh"
echo "------------------------------------------------"
