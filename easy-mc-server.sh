#!/bin/bash

# ==========================================
# Easy MC Server Installer for Arch (Termux)
# ==========================================

# 1. Update Check (GitHub)
# Checks if the script is inside a git repository and pulls updates.
echo "Checking for program updates..."
if [ -d ".git" ]; then
    echo "Git repository detected. Attempting to pull updates..."
    git pull origin main || echo "Failed to pull updates (Repo might be private or unreachable)."
else
    echo "Not a git repository. Skipping auto-update."
fi

# 2. Dependency Check
echo "Checking dependencies..."
for dep in wget jq java git; do
    if ! command -v $dep &> /dev/null; then
        echo "$dep is not installed. Installing..."
        pacman -Sy --noconfirm $dep jre-openjdk-headless || { echo "Failed to install $dep"; exit 1; }
    fi
done

echo "------------------------------------------------"
echo "Select Server Type:"
echo "1) Vanilla (Latest Version)"
echo "2) Vanilla (Older Version)"
echo "3) Paper (Latest Version)"
echo "4) Purpur (Latest Version)"
echo "------------------------------------------------"
read -p "Enter choice [1-4]: " CHOICE

SERVER_JAR=""
SERVER_Folder=""
TYPE=""

# Function to get Vanilla URL from Mojang Manifest
get_vanilla_url() {
    local version_id=$1
    local manifest_url="https://launchermeta.mojang.com/mc/game/version_manifest.json"
    
    # Get the URL for the specific version's JSON
    local version_url=$(curl -s $manifest_url | jq -r --arg vid "$version_id" '.versions[] | select(.id == $vid) | .url')
    
    if [ -z "$version_url" ] || [ "$version_url" == "null" ]; then
        echo "Error: Version $version_id not found!"
        exit 1
    fi
    
    # Get the server download URL from the version JSON
    curl -s $version_url | jq -r '.downloads.server.url'
}

case $CHOICE in
    1)
        TYPE="Vanilla"
        SERVER_Folder="Vanilla"
        echo "Fetching latest Vanilla version info..."
        MANIFEST_URL="https://launchermeta.mojang.com/mc/game/version_manifest.json"
        LATEST_VER=$(curl -s $MANIFEST_URL | jq -r '.latest.release')
        echo "Latest Version: $LATEST_VER"
        DOWNLOAD_URL=$(get_vanilla_url "$LATEST_VER")
        ;;
    2)
        TYPE="Vanilla"
        SERVER_Folder="Vanilla_Old"
        echo "Fetching version list..."
        read -p "Enter Minecraft Version (e.g., 1.16.5): " USER_VER
        DOWNLOAD_URL=$(get_vanilla_url "$USER_VER")
        ;;
    3)
        TYPE="Paper"
        SERVER_Folder="Paper"
        echo "Fetching latest Paper version..."
        # Get latest version
        PAPER_VER=$(curl -s "https://api.papermc.io/v2/projects/paper" | jq -r '.versions[-1]')
        # Get latest build
        PAPER_BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$PAPER_VER" | jq -r '.builds[-1]')
        echo "Latest Paper: $PAPER_VER (Build $PAPER_BUILD)"
        DOWNLOAD_URL="https://api.papermc.io/v2/projects/paper/versions/$PAPER_VER/builds/$PAPER_BUILD/downloads/paper-$PAPER_VER-$PAPER_BUILD.jar"
        ;;
    4)
        TYPE="Purpur"
        SERVER_Folder="Purpur"
        echo "Fetching latest Purpur version..."
        PURPUR_VER=$(curl -s "https://api.purpurmc.org/v2/purpur" | jq -r '.versions[-1]')
        PURPUR_BUILD=$(curl -s "https://api.purpurmc.org/v2/purpur/$PURPUR_VER" | jq -r '.builds.all[-1]')
        echo "Latest Purpur: $PURPUR_VER (Build $PURPUR_BUILD)"
        DOWNLOAD_URL="https://api.purpurmc.org/v2/purpur/$PURPUR_VER/$PURPUR_BUILD/download"
        ;;
    *)
        echo "Invalid option."
        exit 1
        ;;
esac

# Create Directory
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    echo "Failed to get download URL."
    exit 1
fi

echo "Creating folder: $SERVER_Folder"
mkdir -p "$SERVER_Folder"
cd "$SERVER_Folder"

# Download Server Jar
SERVER_JAR="server.jar"
echo "Downloading server jar from $DOWNLOAD_URL..."
wget -O "$SERVER_JAR" "$DOWNLOAD_URL"

# 3. EULA Handling
echo "Running server to generate EULA..."
# Run momentarily to generate files
java -Xmx512M -Xms512M -jar "$SERVER_JAR" nogui &
PID=$!
wait $PID

if [ -f "eula.txt" ]; then
    echo "Found eula.txt. Accepting EULA..."
    sed -i 's/eula=false/eula=true/g' eula.txt
else
    echo "Warning: eula.txt not found. The server might have failed to start or is an old version."
fi

# 4. First Run & Stop (To generate folders)
echo "Starting server to generate files (Waiting for 'Done')..."
# Run in background, pipe output to log to monitor
java -Xmx512M -Xms512M -jar "$SERVER_JAR" nogui > server_log.txt 2>&1 &
SERVER_PID=$!

# Monitor log for "Done"
echo "Waiting for server to start..."
while true; do
    if grep -q "Done" server_log.txt; then
        echo "Server started successfully!"
        break
    fi
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "Server stopped unexpectedly. Check server_log.txt inside $SERVER_Folder."
        cat server_log.txt
        exit 1
    fi
    sleep 2
done

# Stop the server
echo "Stopping server..."
kill $SERVER_PID
wait $SERVER_PID 2>/dev/null
echo "Server stopped."

# 5. Plugin Installation (Paper/Purpur only)
if [[ "$TYPE" == "Paper" || "$TYPE" == "Purpur" ]]; then
    mkdir -p plugins
    echo "------------------------------------------------"
    read -p "Do you want to install plugins? (y/n): " INSTALL_PLUGINS
    if [[ "$INSTALL_PLUGINS" == "y" || "$INSTALL_PLUGINS" == "Y" ]]; then
        echo "Enter direct download links for plugins. Type 'done' when finished."
        while true; do
            read -p "Plugin URL: " P_URL
            if [[ "$P_URL" == "done" ]]; then
                break
            fi
            if [[ -n "$P_URL" ]]; then
                wget -P plugins/ "$P_URL"
            fi
        done
    else
        echo "Skipping plugins."
    fi
fi

# 6. RAM Configuration
echo "------------------------------------------------"
TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM / 1024))
REC_MEM=$((TOTAL_MEM_MB / 2))

echo "Detected Total RAM: ${TOTAL_MEM_MB}MB"
echo "Recommended RAM: ${REC_MEM}MB"
read -p "Enter RAM to allocate in MB (e.g., 1024): " USER_RAM

if [ -z "$USER_RAM" ]; then
    USER_RAM=$REC_MEM
    echo "Defaulting to ${USER_RAM}MB"
fi

# 7. Create run.sh
echo "Creating run.sh..."
cat <<EOF > run.sh
#!/bin/bash
java -Xmx${USER_RAM}M -Xms${USER_RAM}M -jar $SERVER_JAR nogui
EOF
chmod +x run.sh

# 8. Create add-mods.sh
# Note: Paper/Purpur use 'plugins', but this script creates a generic downloader
# into the 'plugins' folder if it exists, or 'mods' if user manually creates it later.
TARGET_DIR="plugins"
if [ ! -d "plugins" ]; then
    TARGET_DIR="mods" # Fallback for potential modded setup or vanilla
fi

echo "Creating add-mods.sh..."
cat <<EOF > add-mods.sh
#!/bin/bash
# Helper to download mods/plugins
TARGET="$TARGET_DIR"
mkdir -p \$TARGET

echo "Enter direct download link for Mod/Plugin (or 'exit'):"
read URL
if [ "\$URL" != "exit" ] && [ -n "\$URL" ]; then
    wget -P \$TARGET "\$URL"
    echo "Downloaded to \$TARGET"
else
    echo "Cancelled."
fi
EOF
chmod +x add-mods.sh

echo "------------------------------------------------"
echo "Installation Complete!"
echo "Server is located in: $PWD"
echo "To start the server, run: ./run.sh"
echo "To add mods/plugins, run: ./add-mods.sh"
echo "------------------------------------------------"
```[[1](https://www.google.com/url?sa=E&q=https%3A%2F%2Fvertexaisearch.cloud.google.com%2Fgrounding-api-redirect%2FAUZIYQF1g365Eb43LMGTd_6WIjHqHfekXggXwzi53sIyyQiKsdM8-jLw7C2yBIJJtpGE542dOXe7rAzJSonWvJiAv2kxFdpFQB2N4HVggpXGT7qEThQYgcAymlLbavLe3DUwaTHF_rYmSP0G32MqyexlTodzEc-sWGt6Q_wJ49GRYL5p2L0j2MBeoZxruk3oKhBoROvQ_0ihlNvz)]
