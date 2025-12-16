#!/bin/bash
set -e

echo "--- [Proton] Setting up Compatibility Tools ---"

# 1. Define Paths
# System source (where the Docker image puts them)
SYSTEM_TOOLS="/usr/share/steam/compatibilitytools.d"
# User destination (where Steam looks, and pressure-vessel accepts)
USER_TOOLS="/home/steam/.local/share/Steam/compatibilitytools.d"

mkdir -p "$USER_TOOLS"

# 2. Link Tools
# We loop through the system tools and symlink them to the user folder.
# This "tricks" Steam into thinking they are user-installed, bypassing the /usr restriction.
if [ -d "$SYSTEM_TOOLS" ]; then
    find "$SYSTEM_TOOLS" -mindepth 1 -maxdepth 1 -type d | while read -r tool; do
        tool_name=$(basename "$tool")
        target="$USER_TOOLS/$tool_name"
        
        if [ ! -e "$target" ]; then
            echo "    -> Linking $tool_name to user home..."
            ln -s "$tool" "$target"
        else
            echo "    -> $tool_name already linked."
        fi
    done
fi

echo "Proton setup complete."
