#!/bin/bash
set -e

echo "--- [Proton] Linking Compatibility Tools ---"

DEST_DIR="/home/steam/.steam/root/compatibilitytools.d"
SRC_DIR="/usr/share/steam/compatibilitytools.d"

# Ensure destination exists
mkdir -p "$DEST_DIR"
chown steam:steam "$DEST_DIR"

if [ -d "$SRC_DIR" ]; then
    echo "Scanning system tools in $SRC_DIR..."
    
    for tool_path in "$SRC_DIR"/*; do
        tool_name=$(basename "$tool_path")
        target_path="$DEST_DIR/$tool_name"
        
        # 1. CLEANUP: Remove physical copies (from our previous debugging)
        # If it's a directory but NOT a symlink, delete it to restore the lightweight link.
        if [ -d "$target_path" ] && [ ! -L "$target_path" ]; then
            echo "   -> [Cleanup] Removing physical copy of $tool_name..."
            rm -rf "$target_path"
        fi

        # 2. SYMLINK: Create or Update
        # We force link (-f) to ensure it points to the correct current location
        if [ ! -e "$target_path" ] || [ -L "$target_path" ]; then
            # Only relink if the target is different to avoid log spam
            CURRENT_LINK=$(readlink "$target_path" || true)
            if [ "$CURRENT_LINK" != "$tool_path" ]; then
                echo "   -> [Link] Linking $tool_name..."
                ln -sfn "$tool_path" "$target_path"
            else
                echo "   -> [OK] $tool_name linked."
            fi
        fi
    done
fi

# Ensure steam owns the link objects themselves
chown -h -R steam:steam "$DEST_DIR"

echo "Proton setup complete."
