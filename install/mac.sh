#!/bin/bash
# Blueberry Minecraft - macOS installer
# Sets up (or repairs) the "Blueberry" instance in Prism Launcher.
# Mods download automatically on every launch via packwiz, so this only ever needs running once.
#
# Run it any of these ways:
#   - double-click "Install Blueberry.command"
#   - Terminal:  curl -fsSL https://voidgl.github.io/blueberry-pack/install/mac.sh | bash
#
# Sticks to macOS's built-in bash 3.2 + curl - no python, no Homebrew needed.

NAME="Blueberry"
SERVER="sale-existed.gl.joinmc.link"
PACK_URL="https://voidgl.github.io/blueberry-pack/pack.toml"
ICON_URL="https://voidgl.github.io/blueberry-pack/install/icon.png"
BOOTSTRAP_URL="https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/v0.0.3/packwiz-installer-bootstrap.jar"
MC_VERSION="1.21.10"
FABRIC_VERSION="0.18.4"
# servers.dat with one entry: Blueberry -> SERVER, resource packs auto-accepted
SERVERS_DAT='\012\000\000\011\000\007\163\145\162\166\145\162\163\012\000\000\000\001\010\000\002\151\160\000\033\163\141\154\145\055\145\170\151\163\164\145\144\056\147\154\056\152\157\151\156\155\143\056\154\151\156\153\010\000\004\156\141\155\145\000\011\102\154\165\145\142\145\162\162\171\001\000\016\141\143\143\145\160\164\124\145\170\164\165\162\145\163\001\000\000'

C_STEP=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[0;31m'; C_HEAD=$'\033[0;35m'; C_DIM=$'\033[0;90m'; C_OFF=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$C_STEP" "$1" "$C_OFF"; }
ok()   { printf '    %s[OK] %s%s\n' "$C_OK" "$1" "$C_OFF"; }
info() { printf '    %s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }
warn() { printf '    %s[!] %s%s\n' "$C_WARN" "$1" "$C_OFF"; }
fail() {
    printf '\n  %s[ERROR] %s%s\n' "$C_ERR" "$1" "$C_OFF"
    printf '  %sScreenshot this window and send it to Seth.%s\n\n' "$C_WARN" "$C_OFF"
    exit 1
}

find_prism() {
    local p
    for p in "/Applications/Prism Launcher.app" "$HOME/Applications/Prism Launcher.app"; do
        [[ -d "$p" ]] && { echo "$p"; return; }
    done
    mdfind "kMDItemCFBundleIdentifier == 'org.prismlauncher.PrismLauncher'" 2>/dev/null | head -n 1
}

install_prism() {
    info "Prism Launcher not found - downloading it..."
    local url tmp dest
    url=$(curl -fsSL https://api.github.com/repos/PrismLauncher/PrismLauncher/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*macOS[^"]*\.zip"' | head -n 1 | sed 's/.*"\(https[^"]*\)"/\1/')
    [[ -n "$url" ]] || fail "Couldn't find Prism Launcher on GitHub. Install it from https://prismlauncher.org then run this again."
    tmp=$(mktemp -d)
    curl -fL --progress-bar -o "$tmp/prism.zip" "$url" || fail "Prism Launcher download failed."
    ditto -x -k "$tmp/prism.zip" "$tmp" || fail "Couldn't unpack Prism Launcher."
    dest="/Applications"
    [[ -w "$dest" ]] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
    rm -rf "$dest/Prism Launcher.app"
    ditto "$tmp/Prism Launcher.app" "$dest/Prism Launcher.app" || fail "Couldn't copy Prism Launcher to $dest."
    rm -rf "$tmp"
}

# Respect a custom instance folder set in Prism's settings
instances_dir() {
    local data="$1" val
    val=$(grep -m 1 '^InstanceDir=' "$data/prismlauncher.cfg" 2>/dev/null | sed 's/^InstanceDir=//; s/^"//; s/"$//')
    if [[ -z "$val" ]]; then echo "$data/instances"
    elif [[ "$val" == /* ]]; then echo "$val"
    else echo "$data/$val"; fi
}

memory_mb() {
    local gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
    if (( gb >= 15 )); then echo 6144
    elif (( gb >= 11 )); then echo 5120
    else echo 4096; fi
}

printf '\n%s  ==========================================%s\n' "$C_HEAD" "$C_OFF"
printf '%s        Blueberry - Minecraft installer%s\n' "$C_HEAD" "$C_OFF"
printf '%s  ==========================================%s\n' "$C_HEAD" "$C_OFF"
echo "  Sets up the Blueberry modpack in Prism Launcher"
echo "  with the server already in your list."

# --- 1. Prism ---------------------------------------------------------------
step "Looking for Prism Launcher"
PRISM_APP=$(find_prism)
if [[ -n "$PRISM_APP" ]]; then
    ok "Found it: $PRISM_APP"
else
    install_prism
    PRISM_APP=$(find_prism)
    [[ -n "$PRISM_APP" ]] && ok "Prism Launcher installed" || warn "Installed, but couldn't locate it - open Prism from Applications afterwards."
fi

if pgrep -qf "Prism Launcher.app/Contents/MacOS" 2>/dev/null; then
    info "Closing Prism so it picks up the new instance..."
    osascript -e 'quit app "Prism Launcher"' >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -qf "Prism Launcher.app/Contents/MacOS" || break
        sleep 1
    done
fi

# --- 2. Instance --------------------------------------------------------------
step "Setting up the Blueberry instance"
DATA="$HOME/Library/Application Support/PrismLauncher"
INSTANCES=$(instances_dir "$DATA")
INST="$INSTANCES/$NAME"
if [[ -d "$INST" ]]; then
    info "Existing Blueberry instance found - updating it (your worlds, settings and screenshots are kept)."
else
    info "Creating $INST"
fi

# Prism uses "minecraft" for newer instances, ".minecraft" for older ones - keep whichever exists
GAME="$INST/.minecraft"
[[ ! -d "$GAME" && -d "$INST/minecraft" ]] && GAME="$INST/minecraft"
mkdir -p "$GAME" || fail "Couldn't create $GAME"

MEM=$(memory_mb)
cat > "$INST/mmc-pack.json" <<EOF
{
    "components": [
        { "uid": "net.minecraft", "version": "$MC_VERSION", "important": true },
        { "uid": "net.fabricmc.intermediary", "version": "$MC_VERSION", "dependencyOnly": true },
        { "uid": "net.fabricmc.fabric-loader", "version": "$FABRIC_VERSION" }
    ],
    "formatVersion": 1
}
EOF
# \$INST_JAVA is quoted so Java paths with spaces ("Application Support") work
cat > "$INST/instance.cfg" <<EOF
[General]
ConfigVersion=1.2
InstanceType=OneSix
name=$NAME
iconKey=blueberry
notes=Seth's modded survival server - Fabric $MC_VERSION\nMods update automatically every time you launch.
AutomaticJava=true
OverrideMemory=true
MinMemAlloc=1024
MaxMemAlloc=$MEM
OverrideCommands=true
PreLaunchCommand="\\"\$INST_JAVA\\" -jar packwiz-installer-bootstrap.jar $PACK_URL"
EOF
ok "Instance config written ($(( MEM / 1024 )) GB RAM for the game)"

info "Downloading the mod updater..."
curl -fsSL -o "$GAME/packwiz-installer-bootstrap.jar" "$BOOTSTRAP_URL" || fail "Couldn't download the mod updater - check your internet and try again."
ok "Mod updater ready"

SERVERS="$GAME/servers.dat"
if ! grep -q "$SERVER" "$SERVERS" 2>/dev/null; then
    [[ -f "$SERVERS" ]] && cp "$SERVERS" "$SERVERS.bak"
    printf "$SERVERS_DAT" > "$SERVERS"
fi
ok "Blueberry server added to your server list"

mkdir -p "$DATA/icons"
curl -fsSL -o "$DATA/icons/blueberry.png" "$ICON_URL" 2>/dev/null || info "(Skipped the instance icon - not important)"

# --- 3. Done --------------------------------------------------------------------
printf '\n%s  ==========================================%s\n' "$C_OK" "$C_OFF"
printf '%s        All set!%s\n' "$C_OK" "$C_OFF"
printf '%s  ==========================================%s\n\n' "$C_OK" "$C_OFF"
echo "  Prism is opening and starting Blueberry now."
printf '  %sFirst launch downloads ~110 mods - give it a few minutes.%s\n' "$C_WARN" "$C_OFF"
echo "  Then: Multiplayer -> Blueberry -> Join."
printf '  %s(If the server is asleep it takes ~1 minute to wake up - just rejoin.)%s\n\n' "$C_DIM" "$C_OFF"
printf '  %sServer: %s%s\n' "$C_WARN" "$SERVER" "$C_OFF"
printf '  %sProblems? Screenshot this window and send it to Seth.%s\n\n' "$C_DIM" "$C_OFF"

if [[ -n "$PRISM_APP" ]]; then
    open -a "$PRISM_APP" --args --launch "$NAME"
fi
echo "  You can close this window."
