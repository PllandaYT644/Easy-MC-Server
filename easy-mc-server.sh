#!/bin/bash

# ==================================================
# Easy MC Server Installer (Arch & Ubuntu Supported)
# ==================================================

# --- 1. Detect OS & Update ---
OS="Unknown"
if command -v pacman &> /dev/null; then
    OS="Arch"
    echo "Detected OS: Arch Linux"
elif command -v apt &> /dev/null; then
    OS="Ubuntu"
    echo "Detected OS: Ubuntu/Debian"
else
    echo "Error: Unsupported OS. Only Arch (pacman) and Ubuntu (apt) are supported."
    exit 1
fi

# Update & Install Dependencies
echo "Checking for program updates..."
[ -d ".git" ] && git pull origin main

echo "Updating package lists..."
if [ "$OS" == "Arch" ]; then
    pacman -Sy
    DEPS="wget jq unzip git file"
    MISSING=""
    for d in $DEPS; do command -v $d &>/dev/null || MISSING="$MISSING $d"; done
    [ -n "$MISSING" ] && pacman -S --noconfirm $MISSING
else
    apt update
    DEPS="wget jq unzip git file"
    MISSING=""
    for d in $DEPS; do command -v $d &>/dev/null || MISSING="$MISSING $d"; done
    [ -n "$MISSING" ] && apt install -y $MISSING
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
TYPE=""
VERSION_TAG=""
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
        LATEST_VER=$(curl -s "https://launchermeta.mojang.com/mc/game/version_manifest.json" | jq -r '.latest.release')
        VERSION_TAG="$LATEST_VER"
        echo "Latest Version: $VERSION_TAG"
        DOWNLOAD_URL=$(get_vanilla_url "$LATEST_VER")
        ;;
    2)
        TYPE="Vanilla"
        read -p "Enter Minecraft Version (e.g., 1.16.5): " USER_VER
        VERSION_TAG="$USER_VER"
        DOWNLOAD_URL=$(get_vanilla_url "$USER_VER")
        ;;
    3)
        TYPE="Paper"
        PAPER_VER=$(curl -s "https://api.papermc.io/v2/projects/paper" | jq -r '.versions[-1]')
        PAPER_BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$PAPER_VER" | jq -r '.builds[-1]')
        VERSION_TAG="$PAPER_VER"
        echo "Latest Paper: $PAPER_VER (Build $PAPER_BUILD)"
        DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$PAPER_VER/builds/$PAPER_BUILD/downloads/paper-$PAPER_VER-$PAPER_BUILD.jar"
        ;;
    4)
        TYPE="Purpur"
        PURPUR_VER=$(curl -s "https://api.purpurmc.org/v2/purpur" | jq -r '.versions[-1]')
        PURPUR_BUILD=$(curl -s "https://api.purpurmc.org/v2/purpur/$PURPUR_VER" | jq -r '.builds.all[-1]')
        VERSION_TAG="$PURPUR_VER"
        echo "Latest Purpur: $PURPUR_VER (Build $PURPUR_BUILD)"
        DOWNLOAD_URL="https://api.purpurmc.org/v2/purpur/$PURPUR_VER/$PURPUR_BUILD/download"
        ;;
    *) echo "Invalid option."; exit 1 ;;
esac

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    echo "Failed to get download URL."
    exit 1
fi

# --- 3. Folder Creation (Renaming) ---
FINAL_FOLDER="${TYPE}-${VERSION_TAG}"
echo "Creating server folder: $FINAL_FOLDER"
mkdir -p "$FINAL_FOLDER"
cd "$FINAL_FOLDER"

echo "Downloading server jar..."
wget -q --show-progress -O "$SERVER_JAR" "$DOWNLOAD_URL"

# --- 4. Java Detection & Installation ---
echo "Detecting required Java version..."
CLASS_FILE=$(unzip -l "$SERVER_JAR" | grep ".class" | head -n 1 | awk '{print $4}')
unzip -p "$SERVER_JAR" "$CLASS_FILE" > temp.class
# Bytecode: 65=J21, 61=J17, 52=J8
CLASS_VER=$(od -j 7 -N 1 -t u1 temp.class | head -n 1 | awk '{print $2}')
rm temp.class

REQ_JAVA="21"
if [ "$CLASS_VER" -ge 65 ]; then REQ_JAVA="21";
elif [ "$CLASS_VER" -ge 61 ]; then REQ_JAVA="17";
elif [ "$CLASS_VER" -ge 52 ]; then REQ_JAVA="8";
fi

echo "Detected requirement: Java $REQ_JAVA"

# Determine Package Names
if [ "$OS" == "Arch" ]; then
    PKG_NAME="jre${REQ_JAVA}-openjdk-headless"
    CHECK_CMD="pacman -Qs $PKG_NAME"
    INSTALL_CMD="pacman -S --noconfirm $PKG_NAME"
else
    # Ubuntu naming
    PKG_NAME="openjdk-${REQ_JAVA}-jre-headless"
    CHECK_CMD="dpkg -l | grep $PKG_NAME"
    INSTALL_CMD="apt install -y $PKG_NAME"
fi

# Install if missing
if eval $CHECK_CMD > /dev/null; then
    echo "$PKG_NAME is already installed."
else
    echo "Installing $PKG_NAME..."
    $INSTALL_CMD || { echo "Failed to install Java."; exit 1; }
fi

# Switch System Default Java
echo "Switching system 'java' to version $REQ_JAVA..."
if [ "$OS" == "Arch" ]; then
    # Arch Logic
    archlinux-java set "java-${REQ_JAVA}-openjdk"
else
    # Ubuntu Logic (update-alternatives)
    # Find the path for the specific version
    JAVA_PATH=$(update-alternatives --list java | grep "java-$REQ_JAVA" | head -n 1)
    if [ -n "$JAVA_PATH" ]; then
        update-alternatives --set java "$JAVA_PATH"
    else
        # Fallback if list fails, try auto
        update-alternatives --auto java
    fi
fi

echo "Active Java Version:"
java -version 2>&1 | head -n 1

# --- 5. Simplified EULA Generation ---
echo "Running server to generate EULA (Simplified Start)..."
# Simplified command as requested
java -jar "$SERVER_JAR"

# Wait a moment for files to write if it crashes fast
sleep 2

if [ -f "eula.txt" ]; then
    echo "Accepting EULA..."
    sed -i 's/eula=false/eula=true/g' eula.txt
else
    echo "Warning: eula.txt not found. Did the server start?"
fi

# --- 6. Full Start (Generate Files) ---
echo "Starting server fully to generate files..."
# Using memory flags here for the actual run
java -Xmx1G -Xms1G -jar "$SERVER_JAR" nogui > server_log.txt 2>&1 &
SERVER_PID=$!

echo "Waiting for initialization..."
while true; do
    if grep -q "Done" server_log.txt; then
        echo "Server initialized."
        break
    fi
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "Server stopped. Checking log..."
        tail -n 5 server_log.txt
        exit 1
    fi
    sleep 2
done

kill $SERVER_PID
wait $SERVER_PID 2>/dev/null
echo "Server stopped."

# --- 7. Plugins ---
if [[ "$TYPE" == "Paper" || "$TYPE" == "Purpur" ]]; then
    mkdir -p plugins
    echo "------------------------------------------------"
    read -p "Install plugins? (y/n): " PLUG_OPT
    if [[ "$PLUG_OPT" =~ ^[Yy]$ ]]; then
        echo "Paste URLs separated by space (or 'done'):"
        while true; do
            read -p "URL(s): " INPUT_URLS
            [[ "$INPUT_URLS" == "done" ]] && break
            for URL in $INPUT_URLS; do
                [[ -n "$URL" ]] && wget -q --show-progress -P plugins/ "$URL"
            done
        done
    fi
fi

# --- 8. RAM & Scripts ---
TOTAL_MEM_MB=$(grep MemTotal /proc/meminfo | awk '{print $2/1024}' | cut -d. -f1)
REC_MEM=$((TOTAL_MEM_MB / 2))

echo "Total RAM: ${TOTAL_MEM_MB}MB. Recommended: ${REC_MEM}MB"
read -p "Enter RAM (MB): " USER_RAM
[ -z "$USER_RAM" ] && USER_RAM=$REC_MEM

# Create run.sh
cat <<EOF > run.sh
#!/bin/bash
java -Xmx${USER_RAM}M -Xms${USER_RAM}M -jar $SERVER_JAR nogui
EOF
chmod +x run.sh

# Create add-mods.sh
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
echo "Done! Server folder: $FINAL_FOLDER"
echo "Run: cd $FINAL_FOLDER && ./run.sh"
echo "------------------------------------------------"
