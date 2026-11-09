#!/usr/bin/env bash
# Reapplies the local tweaks to the "Atom Material Icons" VS Code extension.
# An extension update wipes them, so run this again after every update.
set -euo pipefail

atom=$(ls -d "$HOME"/.vscode/extensions/atommaterial.a-file-icon-vscode-* | sort -V | tail -1)
material=$(ls -d "$HOME"/.vscode/extensions/pkief.material-icon-theme-* | sort -V | tail -1)
theme="$atom/dist/a-file-icon-vscode-icon-theme.json"
product="$atom/dist/a-file-icon-vscode-product-icon-theme.json"

# Open folders get the closed-folder icon (the theme's open variant is an empty outline).
test -d "$atom/foldersOpen.bak" || cp -R "$atom/dist/foldersOpen" "$atom/foldersOpen.bak"
cp "$atom"/dist/folders/*.svg "$atom/dist/foldersOpen/"

# Material's Python icon, under a new filename so VS Code's SVG cache does not serve the old one.
cp "$material/icons/python.svg" "$atom/dist/files/python-material.svg"
/usr/bin/sed -i '' 's|"./../dist/files/python.svg"|"./../dist/files/python-material.svg"|' "$theme"

# The unsaved-file dot: dropping the entry falls back to VS Code's own codicon,
# which is round. The extension rewrites this file whenever its own icon
# settings change, not only on update, so rerun after touching those too.
/usr/bin/sed -i '' '/"circle-filled": {/,/^    },$/d' "$product"

grep -q 'dist/files/python-material.svg' "$theme" || { echo "theme json not patched"; exit 1; }
diff -q "$material/icons/python.svg" "$atom/dist/files/python-material.svg" >/dev/null
diff -q "$atom/dist/folders/git.svg" "$atom/dist/foldersOpen/git.svg" >/dev/null
! grep -q '"circle-filled"' "$product" || { echo "product theme json not patched"; exit 1; }

echo "patched $atom — quit VS Code completely (Cmd+Q) and reopen it"
