#!/bin/bash

# ==========================================================
# Easy MC Server Installer (Arch, Ubuntu, Fedora Supported)
# ==========================================================

# --- 1. Fixed Auto-Updater (Prevents Infinite Loop) ---
if [ -d ".git" ]; then
    echo "Checking for updates..."
    # Stash local changes to prevent merge errors
    git stash push -m "Auto-update stash" > /dev/null 2>&1
    
    # Capture the output of the pull command
    UPDATE_OUTPUT=$(git pull origin main 2>&1)
    
    # Check if the output actually says it updated something
    if [[ "$UPDATE_OUTPUT" == *"Already up to date."* ]]; then
        echo "Program is already up to date."
    else
        echo "Update successful! Restarting script..."
        chmod +x "$0"
        exec "$0" "$@"
        exit
    fi
fi

# --- 2. Detect OS & Install Dependencies ---
OS="Unknown"
if command -v pacman &> /dev/null; then
    OS="Arch"
elif command -v apt &> /dev/null; then
    OS="Ubuntu"
elif command -v dnf &> /dev/null; then
    OS="Fedora"
else
    echo "Error: OS not supported. (Requires pacman, apt, or dnf)"
    exit 1
fi

echo "Detected OS: $OS"

DEPS="wget jq unzip git file"
echo "Checking dependencies..."

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

# --- 4. Folder Creation ---
FINAL_FOLDER="${TYPE}-${VERSION_TAG}"
echo "Creating server folder: $FINAL_FOLDER"
mkdir -p "$FINAL_FOLDER"
cd "$FINAL_FOLDER"

echo "Downloading server jar..."
wget -q --show-progress -O "$SERVER_JAR" "$DOWNLOAD_URL"

# --- 5. Java Auto-Detection & Install ---
echo "Analyzing jar for Java version..."
CLASS_FILE=$(unzip -l "$SERVER_JAR" | grep ".class" | head -n 1 | awk '{print $4}')
unzip -p "$SERVER_JAR" "$CLASS_FILE" > temp.class
# Bytecode: 65=Java21, 61=Java17, 52=Java8
CLASS_VER=$(od -j 7 -N 1 -t u1 temp.class | head -n 1 | awk '{print $2}')
rm temp.class

REQ_JAVA="21"
if [ "$CLASS_VER" -ge 65 ]; then REQ_JAVA="21";
elif [ "$CLASS_VER" -ge 61 ]; then REQ_JAVA="17";
elif [ "$CLASS_VER" -ge 52 ]; then REQ_JAVA="8";
fi

echo "Required: Java $REQ_JAVA"

PKG_NAME=""
if [ "$OS" == "Arch" ]; then
    # Arch Naming
    PKG_NAME="jre${REQ_JAVA}-openjdk-headless"
    if ! pacman -Qs $PKG_NAME > /dev/null; then
        echo "Installing $PKG_NAME..."
        pacman -S --noconfirm $PKG_NAME
    fi
    archlinux-java set "java-${REQ_JAVA}-openjdk"

elif [ "$OS" == "Ubuntu" ]; then
    # Ubuntu Naming
    PKG_NAME="openjdk-${REQ_JAVA}-jre-headless"
    if ! dpkg -l | grep -q $PKG_NAME; then
        echo "Installing $PKG_NAME..."
        apt install -y $PKG_NAME
    fi
    # Switch via update-alternatives
    JAVA_PATH=$(update-alternatives --list java | grep "java-$REQ_JAVA" | head -n 1)
    [ -n "$JAVA_PATH" ] && update-alternatives --set java "$JAVA_PATH" || update-alternatives --auto java

elif [ "$OS" == "Fedora" ]; then
    # Fedora Naming
    if [ "$REQ_JAVA" == "8" ]; then
        PKG_NAME="java-1.8.0-openjdk-headless"
    else
        PKG_NAME="java-${REQ_JAVA}-openjdk-headless"
    fi
    
    if ! rpm -q $PKG_NAME > /dev/null; then
        echo "Installing $PKG_NAME..."
        dnf install -y $PKG_NAME
    fi
    
    # Switch via alternatives (Fedora/RHEL style)
    JAVA_PATH=$(alternatives --list | grep "java " | grep "$REQ_JAVA" | head -n 1 | awk '{print $3}')
    
    # Fallback search if alternatives list is messy
    if [ -z "$JAVA_PATH" ]; then
        JAVA_PATH=$(find /usr/lib/jvm -name java -type f | grep "java-$REQ_JAVA" | grep "/bin/java" | head -n 1)
    fi

    if [ -n "$JAVA_PATH" ]; then
        echo "Setting alternatives to $JAVA_PATH"
        alternatives --set java "$JAVA_PATH"
    else
        echo "Could not find exact path for alternatives. Trying auto."
        alternatives --auto java
    fi
fi

echo "Current Java:"
java -version 2>&1 | head -n 1

# --- 6. EULA (Simplified) ---
echo "Starting server to generate EULA..."
java -jar "$SERVER_JAR"

sleep 3

if [ -f "eula.txt" ]; then
    echo "Accepting EULA..."
    sed -i 's/eula=false/eula=true/g' eula.txt
else
    echo "Warning: eula.txt not found. If the server crashed, check your Java version."
fi

# --- 7. Initialize Server Files ---
echo "Starting server to generate world files..."
java -Xmx1G -Xms1G -jar "$SERVER_JAR" nogui > server_log.txt 2>&1 &
SERVER_PID=$!

echo "Waiting for initialization..."
while true; do
    if grep -q "Done" server_log.txt; then
        echo "Server initialized."
        break
    fi
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "Server stopped unexpectedly. Last log lines:"
        tail -n 5 server_log.txt
        exit 1
    fi
    sleep 2
done

kill $SERVER_PID
wait $SERVER_PID 2>/dev/null
echo "Server stopped."

# --- 8. Plugins / Mods ---
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

# --- 9. Final Scripts ---
TOTAL_MEM_MB=$(grep MemTotal /proc/meminfo | awk '{print $2/1024}' | cut -d. -f1)
REC_MEM=$((TOTAL_MEM_MB / 2))

echo "Total RAM: ${TOTAL_MEM_MB}MB. Recommended: ${REC_MEM}MB"
read -p "Enter RAM (MB): " USER_RAM
[ -z "$USER_RAM" ] && USER_RAM=$REC_MEM

cat <<EOF > run.sh
#!/bin/bash
java -Xmx${USER_RAM}M -Xms${USER_RAM}M -jar $SERVER_JAR nogui
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
echo "Done! Server is in: $FINAL_FOLDER"
echo "To start: cd $FINAL_FOLDER && ./run.sh"
echo "------------------------------------------------"
