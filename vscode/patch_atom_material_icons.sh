#!/usr/bin/env bash
# Reapplies the local tweaks to the "Atom Material Icons" VS Code extension.
# An extension update wipes them, so run this again after every update.
set -euo pipefail

atom=$(ls -d "$HOME"/.vscode/extensions/atommaterial.a-file-icon-vscode-* | sort -V | tail -1)
theme="$atom/dist/a-file-icon-vscode-icon-theme.json"
product="$atom/dist/a-file-icon-vscode-product-icon-theme.json"

# The VS Code port knows far fewer file names than the IntelliJ plugin of the same theme, so
# mise.toml, ruff.toml and thousands of others fall back to their extension's icon. Bring the
# missing names — and any icon they need — over from the IntelliJ plugin.
python3 - "$atom" <<'PY'
import io, json, os, re, sys, urllib.request, xml.etree.ElementTree as ET, zipfile

marketplace = "https://plugins.jetbrains.com"

def plugin_jar():
    """The IntelliJ plugin's jar, from the Marketplace so IntelliJ need not be installed."""
    update = json.load(urllib.request.urlopen(f"{marketplace}/api/plugins/10044/updates?size=1"))[0]
    download = urllib.request.urlopen(f"{marketplace}/plugin/download?updateId={update['id']}")

    plugin = zipfile.ZipFile(io.BytesIO(download.read()))
    lib = next(name for name in plugin.namelist() if "/lib/a-file-icon-idea-" in name)
    return zipfile.ZipFile(io.BytesIO(plugin.read(lib))), update["version"]

atom = sys.argv[1]
theme_path = f"{atom}/dist/a-file-icon-vscode-icon-theme.json"
theme = json.load(open(theme_path))
icons, names = theme["iconDefinitions"], theme["fileNames"]
jar, jar_version = plugin_jar()
jar_entries = set(jar.namelist())

def whitened(svg):
    """IntelliJ tints its near-black icons for its dark theme; VS Code draws them as they come."""
    def white_if_dark(fill):
        digits = fill.group(1).decode()
        if len(digits) == 3:
            digits = "".join(digit * 2 for digit in digits)

        channels = [int(digits[at:at + 2], 16) for at in (0, 2, 4)]
        return b'fill="#fff"' if max(channels) < 64 else fill.group(0)

    def whiten(part):
        return re.sub(rb'fill="#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})"', white_if_dark, part)

    # A rect as large as the icon is a backdrop IntelliJ hides against its own dark sidebar.
    # Whitening it would bury the glyph drawn over it, so it keeps its colour.
    size = re.search(rb'viewBox="0 0 (\d+) (\d+)"', svg)
    backdrop = size and re.search(rb'<rect width="%b" height="%b"[^>]*/>' % size.groups(), svg)
    if backdrop is None:
        return whiten(svg)

    return whiten(svg[:backdrop.start()]) + backdrop.group() + whiten(svg[backdrop.end():])

def icon_key(icon):
    """The definition to point a name at, copying the icon over when the port lacks it."""
    entry = f"assets/icons/files/{icon}.svg"
    svg = f"{atom}/dist/files/{icon}.svg"
    if not os.path.exists(svg):
        if entry not in jar_entries:
            return None
        with open(svg, "wb") as out:
            out.write(whitened(jar.read(entry)))

    icons.setdefault(icon, {"iconPath": f"./../dist/files/{icon}.svg"})
    return icon

taken = {name.lower() for name in names}
added = 0
for rule in ET.fromstring(jar.read("iconGenerator/icon_associations.xml")).iter("regex"):
    icon = os.path.basename(rule.get("icon") or "")[:-4]
    if not icon:
        continue

    for name in (n.strip().lower() for n in (rule.get("fileNames") or "").split(",")):
        # VS Code matches a file name, never a path, so the plugin's path rules are dropped.
        if not name or "/" in name or name in taken:
            continue
        key = icon_key(icon)
        if key is None:
            continue
        names[name] = key
        taken.add(name)
        added += 1

names.setdefault(".gitmojirc.json", theme["fileExtensions"]["gitattributes"])

tmp = f"{theme_path}.tmp"
with open(tmp, "w") as out:
    json.dump(theme, out, indent=2)
os.replace(tmp, theme_path)
print(f"{added} file names taken from the IntelliJ plugin {jar_version}")
PY

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
