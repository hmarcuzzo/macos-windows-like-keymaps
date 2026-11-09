#!/usr/bin/env bash
# Reapplies the local tweaks to the "Atom Material Icons" VS Code extension.
# An extension update wipes them, so run this again after every update.
set -euo pipefail

atom=$(ls -d "$HOME"/.vscode/extensions/atommaterial.a-file-icon-vscode-* | sort -V | tail -1)
theme="$atom/dist/a-file-icon-vscode-icon-theme.json"
product="$atom/dist/a-file-icon-vscode-product-icon-theme.json"

# File names the VS Code port lacks, taken from the IntelliJ plugin of the same theme.
python3 "$(dirname "$0")/sync_intellij_file_names.py" "$atom"

# Open folders get the closed-folder icon (the theme's open variant is an empty outline).
test -d "$atom/foldersOpen.bak" || cp -R "$atom/dist/foldersOpen" "$atom/foldersOpen.bak"
cp "$atom"/dist/folders/*.svg "$atom/dist/foldersOpen/"

# Material's icons, under new filenames so VS Code's SVG cache does not serve the old ones.
# Terraform is the port's green one replaced by Material's indigo; the open folder keeps
# following the closed one, so Material's open variant is not needed.
material=https://raw.githubusercontent.com/PKief/vscode-material-icon-theme/main/icons
curl -fsSL -o "$atom/dist/files/python-material.svg" "$material/python.svg"
curl -fsSL -o "$atom/dist/files/terraform-material.svg" "$material/terraform.svg"
curl -fsSL -o "$atom/dist/files/hcl-material.svg" "$material/hcl.svg"
curl -fsSL -o "$atom/dist/folders/terraform-material.svg" "$material/folder-terraform.svg"
cp "$atom/dist/folders/terraform-material.svg" "$atom/dist/foldersOpen/terraform-material.svg"
/usr/bin/sed -i '' \
  -e 's|"./../dist/files/python.svg"|"./../dist/files/python-material.svg"|' \
  -e 's|"./../dist/files/terraform.svg"|"./../dist/files/terraform-material.svg"|' \
  -e 's|"./../dist/files/hcl.svg"|"./../dist/files/hcl-material.svg"|' \
  -e 's|"./../dist/folders/terraform.svg"|"./../dist/folders/terraform-material.svg"|' \
  -e 's|"./../dist/foldersOpen/terraform.svg"|"./../dist/foldersOpen/terraform-material.svg"|' \
  "$theme"

# The unsaved-file dot: dropping the entry falls back to VS Code's own codicon,
# which is round. The extension rewrites this file whenever its own icon
# settings change, not only on update, so rerun after touching those too.
/usr/bin/sed -i '' '/"circle-filled": {/,/^    },$/d' "$product"

grep -q 'dist/files/python-material.svg' "$theme" || { echo "theme json not patched"; exit 1; }
grep -q '<svg' "$atom/dist/files/python-material.svg" || { echo "python icon not downloaded"; exit 1; }
grep -q 'dist/foldersOpen/terraform-material.svg' "$theme" || { echo "terraform icons not repointed"; exit 1; }
grep -q '#5c6bc0' "$atom/dist/folders/terraform-material.svg" || { echo "terraform folder not downloaded"; exit 1; }
grep -q '#eceff1' "$atom/dist/files/hcl-material.svg" || { echo "hcl icon not downloaded"; exit 1; }
grep -q '"mise.toml": "mise"' "$theme" || { echo "file names not synced"; exit 1; }
grep -q '".gitmojirc.json": "git"' "$theme" || { echo "gitmoji name not mapped"; exit 1; }
test -f "$atom/dist/files/mise.svg"
grep -q 'fill="#222"' "$atom/dist/files/mise.svg" || { echo "backdrop rect whitened"; exit 1; }
diff -q "$atom/dist/folders/git.svg" "$atom/dist/foldersOpen/git.svg" >/dev/null
! grep -q '"circle-filled"' "$product" || { echo "product theme json not patched"; exit 1; }

echo "patched $atom — quit VS Code completely (Cmd+Q) and reopen it"
