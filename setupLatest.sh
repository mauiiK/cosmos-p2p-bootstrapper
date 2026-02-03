#!/bin/bash
set -euo pipefail

# ==== CONFIG ====
GAIA_HOME="$HOME/.gaia"
CHAIN_ID="cosmoshub-4"
MONIKER="my-node"
MIN_GAS="0.025uatom"

# Genesis sources fallback
GENESIS_URLS=(
    "https://snapshots-cosmoshub.mirror.guru/genesis.json"
    "https://github.com/cosmos/mainnet/raw/master/genesis/cosmoshub-4.json"
)

# Persistent peers
PEERS="ba3bacc714817218562f743178228f23678b2873@public-seed-node.cosmoshub.certus.one:26656,ade4d8bc8cbe0146ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:14956"

# Tmux session name
SESSION_NAME="gaia_node"

# ==== UTILITY FUNCTIONS ====
log() { echo "[`date '+%H:%M:%S'`] $*"; }

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log "$1 not found, installing..."
        if [[ "$1" == "tmux" || "$1" == "curl" || "$1" == "gzip" || "$1" == "sed" ]]; then
            sudo apt update && sudo apt install -y "$1"
        else
            log "Please install $1 manually."
            exit 1
        fi
    fi
}

download_genesis() {
    for url in "${GENESIS_URLS[@]}"; do
        log "Trying $url ..."
        if curl -sL "$url" -o "$GAIA_HOME/config/genesis.json"; then
            size=$(stat -c%s "$GAIA_HOME/config/genesis.json" 2>/dev/null || echo 0)
            if [[ "$size" -gt 100000 ]]; then
                log "Genesis downloaded successfully: $(ls -lh $GAIA_HOME/config/genesis.json)"
                # Quick validity check: must start with '{'
                first_char=$(head -c 1 "$GAIA_HOME/config/genesis.json")
                if [[ "$first_char" != "{" ]]; then
                    log "Genesis file invalid (does not start with '{'), trying next URL..."
                    continue
                fi
                return 0
            else
                log "Genesis file too small ($size bytes), trying next URL..."
            fi
        fi
    done
    log "Failed to download a valid genesis.json"
    exit 1
}

# ==== MAIN SCRIPT ====
log "Checking dependencies..."
check_command curl
check_command gzip
check_command sed
check_command tmux

log "[1] Removing old Gaia data..."
rm -rf "$GAIA_HOME"

log "[2] Initializing Gaia node..."
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

log "[3] Downloading genesis..."
mkdir -p "$GAIA_HOME/config"
download_genesis

log "[4] Setting minimum gas prices..."
if grep -q "^minimum-gas-prices" "$GAIA_HOME/config/app.toml"; then
    sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"$MIN_GAS\"|" "$GAIA_HOME/config/app.toml"
else
    echo "minimum-gas-prices = \"$MIN_GAS\"" >> "$GAIA_HOME/config/app.toml"
fi

log "[5] Adding persistent peers..."
sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$GAIA_HOME/config/config.toml"

log "[6] Summary of config files:"
ls -lh "$GAIA_HOME/config"

# ==== START NODE IN TMUX ====
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "Tmux session $SESSION_NAME already exists, attaching..."
    tmux attach -t "$SESSION_NAME"
else
    log "[7] Starting Gaia node inside tmux session '$SESSION_NAME'..."
    # Start Gaia in a background tmux session with logs visible
    tmux new-session -d -s "$SESSION_NAME" "gaiad start --home '$GAIA_HOME' --minimum-gas-prices='$MIN_GAS' 2>&1 | tee '$GAIA_HOME/gaia.log'"
    log "Node started in background tmux session."
    log "Attach anytime with: tmux attach -t $SESSION_NAME"
fi
