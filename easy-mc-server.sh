#!/bin/bash

# ==========================================
# Easy MC Server Installer for Arch (Termux)
# ==========================================

# --- 1. Initial Setup & Updates ---
echo "Checking for program updates..."
if [ -d ".git" ]; then
    git pull origin main || echo "Git pull failed (ignoring)."
fi

echo "Updating system package database..."
pacman -Sy

echo "Checking dependencies..."
# Added 'unzip' and 'file' to dependencies
NEEDED_DEPS=""
for dep in wget jq unzip git file; do
    if ! command -v $dep &> /dev/null; then
        NEEDED_DEPS="$NEEDED_DEPS $dep"
    fi
done

if [ -n "$NEEDED_DEPS" ]; then
    echo "Installing missing dependencies:$NEEDED_DEPS"
    pacman -S --noconfirm $NEEDED_DEPS
fi

# Ensure basic Java is present to start with
if ! pacman -Qs jre-openjdk-headless > /dev/null; then
    echo "Installing default Java..."
    pacman -S --noconfirm jre-openjdk-headless
fi

# --- 2. User Selection ---
echo "------------------------------------------------"
echo "Select Server Type:"
echo "1) Vanilla (Latest Version)"
echo "2) Vanilla (Older Version)"
echo "3) Paper (Latest Version)"
echo "4) Purpur (Latest Version)"
echo "------------------------------------------------"
read -p "Enter choice [1-4]: " CHOICE

SERVER_JAR="server.jar"
SERVER_Folder=""
TYPE=""
DOWNLOAD_URL=""

# Helper: Get Vanilla URL
get_vanilla_url() {
    local version_id=$1
    local manifest_url="https://launchermeta.mojang.com/mc/game/version_manifest.json"
    local version_url=$(curl -s $manifest_url | jq -r --arg vid "$version_id" '.versions[] | select(.id == $vid) | .url')
    
    if [ -z "$version_url" ] || [ "$version_url" == "null" ]; then
        echo "Error: Version $version_id not found!"
        exit 1
    fi
    curl -s $version_url | jq -r '.downloads.server.url'
}

case $CHOICE in
    1)
        TYPE="Vanilla"
        SERVER_Folder="Vanilla"
        LATEST_VER=$(curl -s "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r '.latest.release')
        echo "Latest Version: $LATEST_VER"
        DOWNLOAD_URL=$(get_vanilla_url "$LATEST_VER")
        ;;
    2)
        TYPE="Vanilla"
        SERVER_Folder="Vanilla_Old"
        read -p "Enter Minecraft Version (e.g., 1.16.5): " USER_VER
        DOWNLOAD_URL=$(get_vanilla_url "$USER_VER")
        ;;
    3)
        TYPE="Paper"
        SERVER_Folder="Paper"
        PAPER_VER=$(curl -s "https://api.papermc.io/v2/projects/paper" | jq -r '.versions[-1]')
        PAPER_BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$PAPER_VER" | jq -r '.builds[-1]')
        echo "Latest Paper: $PAPER_VER (Build $PAPER_BUILD)"
        DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$PAPER_VER/builds/$PAPER_BUILD/downloads/paper-$PAPER_VER-$PAPER_BUILD.jar"
        ;;
    4)
        TYPE="Purpur"
        SERVER_Folder="Purpur"
        PURPUR_VER=$(curl -s "https://api.purpurmc.org/v2/purpur" | jq -r '.versions[-1]')
        PURPUR_BUILD=$(curl -s "https://api.purpurmc.org/v2/purpur/$PURPUR_VER" | jq -r '.builds.all[-1]')
        echo "Latest Purpur: $PURPUR_VER (Build $PURPUR_BUILD)"
        DOWNLOAD_URL="https://api.purpurmc.org/v2/purpur/$PURPUR_VER/$PURPUR_BUILD/download"
        ;;
    *) echo "Invalid option."; exit 1 ;;
esac

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    echo "Failed to get download URL."
    exit 1
fi

echo "Creating folder: $SERVER_Folder"
mkdir -p "$SERVER_Folder"
cd "$SERVER_Folder"

echo "Downloading server jar..."
wget -q --show-progress -O "$SERVER_JAR" "$DOWNLOAD_URL"

# --- 3. Java Version Detection & Installation ---
echo "Detecting required Java version..."

# Extract a class file to read bytecode
CLASS_FILE=$(unzip -l "$SERVER_JAR" | grep ".class" | head -n 1 | awk '{print $4}')
unzip -p "$SERVER_JAR" "$CLASS_FILE" > temp.class
# Read Major Version byte
CLASS_VER=$(od -j 7 -N 1 -t u1 temp.class | head -n 1 | awk '{print $2}')
rm temp.class

JAVA_PKG=""

if [ "$CLASS_VER" -ge 65 ]; then
    echo "Detected: Java 21 required."
    JAVA_PKG="jre21-openjdk-headless"
elif [ "$CLASS_VER" -ge 61 ]; then
    echo "Detected: Java 17 required."
    JAVA_PKG="jre17-openjdk-headless"
elif [ "$CLASS_VER" -ge 52 ]; then
    echo "Detected: Java 8 required."
    JAVA_PKG="jre8-openjdk-headless"
else
    echo "Could not detect version. Defaulting to Java 21."
    JAVA_PKG="jre21-openjdk-headless"
fi

# Install Java Package
if ! pacman -Qs $JAVA_PKG > /dev/null; then
    echo "Installing $JAVA_PKG..."
    pacman -S --noconfirm $JAVA_PKG || { echo "Failed to install Java. Exiting."; exit 1; }
fi

# FIX: Dynamic Path Detection
# We ask pacman where it put the binary instead of guessing
echo "Locating Java binary..."
JAVA_BIN=$(pacman -Ql $JAVA_PKG | grep -E '/bin/java$' | head -n 1)

if [ -z "$JAVA_BIN" ] || [ ! -f "$JAVA_BIN" ]; then
    echo "Error: Could not find java binary for $JAVA_PKG."
    echo "Falling back to system default 'java' (Check 'archlinux-java status' if this fails)."
    JAVA_BIN="java"
fi

echo "Using Java executable: $JAVA_BIN"

# --- 4. EULA ---
echo "Running server to generate EULA..."
"$JAVA_BIN" -Xmx512M -Xms512M -jar "$SERVER_JAR" nogui &
PID=$!
wait $PID

if [ -f "eula.txt" ]; then
    echo "Accepting EULA..."
    sed -i 's/eula=false/eula=true/g' eula.txt
fi

# --- 5. Generate Files & Stop ---
echo "Starting server to generate files (Waiting for 'Done')..."
"$JAVA_BIN" -Xmx1G -Xms1G -jar "$SERVER_JAR" nogui > server_log.txt 2>&1 &
SERVER_PID=$!

echo "Waiting for start..."
while true; do
    if grep -q "Done" server_log.txt; then
        echo "Server initialized."
        break
    fi
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "Server stopped/crashed. Checking log..."
        tail -n 10 server_log.txt
        exit 1
    fi
    sleep 2
done

kill $SERVER_PID
wait $SERVER_PID 2>/dev/null
echo "Server stopped."

# --- 6. Plugins (Multiple Support) ---
if [[ "$TYPE" == "Paper" || "$TYPE" == "Purpur" ]]; then
    mkdir -p plugins
    echo "------------------------------------------------"
    read -p "Install plugins? (y/n): " PLUG_OPT
    if [[ "$PLUG_OPT" == "y" || "$PLUG_OPT" == "Y" ]]; then
        echo "Enter plugin URLs separated by spaces."
        echo "Example: https://link1.jar https://link2.jar"
        echo "Type 'done' when finished."
        
        while true; do
            read -p "URL(s): " INPUT_URLS
            if [[ "$INPUT_URLS" == "done" ]]; then
                break
            fi
            
            # Loop through all space-separated links
            for URL in $INPUT_URLS; do
                if [[ -n "$URL" ]]; then
                    echo "Downloading: $URL"
                    wget -q --show-progress -P plugins/ "$URL"
                fi
            done
        done
    fi
fi

# --- 7. RAM & Scripts ---
TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM / 1024))
REC_MEM=$((TOTAL_MEM_MB / 2))

echo "Detected RAM: ${TOTAL_MEM_MB}MB. Recommended: ${REC_MEM}MB"
read -p "Enter RAM (MB): " USER_RAM
[ -z "$USER_RAM" ] && USER_RAM=$REC_MEM

# Generate run.sh
echo "Creating run.sh..."
cat <<EOF > run.sh
#!/bin/bash
"$JAVA_BIN" -Xmx${USER_RAM}M -Xms${USER_RAM}M -jar $SERVER_JAR nogui
EOF
chmod +x run.sh

# Generate add-mods.sh (With Multiple Link Support)
TARGET_DIR="mods"
[[ -d "plugins" ]] && TARGET_DIR="plugins"

cat <<EOF > add-mods.sh
#!/bin/bash
TARGET="$TARGET_DIR"
mkdir -p \$TARGET

echo "Paste download links separated by spaces (e.g., link1 link2 link3):"
echo "Or type 'exit' to quit."
read -r ALL_URLS

if [ "\$ALL_URLS" != "exit" ] && [ -n "\$ALL_URLS" ]; then
    for URL in \$ALL_URLS; do
        echo "Downloading: \$URL"
        wget -q --show-progress -P \$TARGET "\$URL"
    done
    echo "All downloads complete."
else
    echo "Cancelled."
fi
EOF
chmod +x add-mods.sh

echo "------------------------------------------------"
echo "Setup Complete!"
echo "Run server: ./run.sh"
echo "Add addons: ./add-mods.sh"
echo "Java Path: $JAVA_BIN"
echo "------------------------------------------------"
