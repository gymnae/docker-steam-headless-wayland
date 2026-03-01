#!/bin/bash
set -e

echo "--- [File Browser] Initializing ---"

DB_PATH="/home/steam/.config/filebrowser.db"

# Ensure config folder exists and belongs to steam
mkdir -p /home/steam/.config
chown -R steam:steam /home/steam/.config

# Run DB creation and user setup AS STEAM
su - steam -c "
    if [ ! -f \"$DB_PATH\" ]; then
        echo '    -> Creating new File Browser database...'
        filebrowser config init --database=\"$DB_PATH\"
        
        # Set to 'noauth' to bypass the login screen entirely
        filebrowser config set --database=\"$DB_PATH\" \
            --address=\"0.0.0.0\" \
            --port=\"8080\" \
            --root=\"/home/steam\" \
            --log=\"/home/steam/filebrowser.log\" \
            --auth.method=\"noauth\"
            
        echo '    -> Creating default admin user...'
        # We MUST provide a 12-character password here to bypass the security check, 
        # even though noauth means you will never actually use it.
        filebrowser users add steam \"SteamAdmin2026!\" --perm.admin=true --database=\"$DB_PATH\"
    else
        echo '    -> Database found. Enforcing NoAuth...'
        filebrowser config set --auth.method=\"noauth\" --database=\"$DB_PATH\"
    fi
"