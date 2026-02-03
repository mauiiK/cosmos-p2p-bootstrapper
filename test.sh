#!/bin/bash
set -euo pipefail

# ================= CONFIG =================
GAIA_HOME="$HOME/.gaia"
CHAIN_ID="cosmoshub-4"
MONIKER="my-node"
MIN_GAS="0.025uatom"
SESSION_NAME="gaia_node"
STATE_SYNC_RPC="https://rpc.cosmos.network:26657"
TRUST_HEIGHT=9474400        # replace with recent trusted block
TRUST_HASH="9CC1F86C768C0A9650A874D2B4D1F718C00F0EE81E2B9BBDB354B4C9116D312D" # replace with correct hash

# Persistent peers
PEERS="ba3bacc714817218562f743178228f23678b2873@public-seed-node.cosmoshub.certus.one:26656,ade4d8bc8cbe0146ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:14956"

# Genesis URLs fallback
GENESIS_URLS=(
    "https://snapshots-cosmoshub.mirror.guru/genesis.json"
    "https://cosmoshub.stakesystems.io/genesis.json"
)

# ================= UTILITY =================
log() { echo "[`date '+%H:%M:%S'`] $*"; }

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log "$1 not found, installing..."
        sudo apt update && sudo apt install -y "$1"
    fi
}

download_genesis() {
    mkdir -p "$GAIA_HOME/config"
    for url in "${GENESIS_URLS[@]}"; do
        log "Trying $url ..."
        if curl -sL "$url" -o "$GAIA_HOME/config/genesis.json"; then
            if [[ -s "$GAIA_HOME/config/genesis.json" ]]; then
                first_char=$(head -c 1 "$GAIA_HOME/config/genesis.json")
                if [[ "$first_char" == "{" ]]; then
                    log "Genesis downloaded successfully: $(ls -lh $GAIA_HOME/config/genesis.json)"
                    return 0
                else
                    log "Genesis file invalid (does not start with '{'), trying next URL..."
                fi
            fi
        fi
    done
    log "Failed to download a valid genesis.json"
    exit 1
}

# ================= MAIN SCRIPT =================
log "Checking dependencies..."
check_command curl
check_command gzip
check_command sed
check_command tmux
check_command git
check_command make
check_command gcc
check_command build-essential

log "[1] Cloning Gaia v24..."
mkdir -p "$HOME/cosmos"
cd "$HOME/cosmos"
if [[ ! -d "gaia" ]]; then
    git clone https://github.com/cosmos/gaia
fi
cd gaia
git fetch --all
git checkout v24.0.0
make install

log "[2] Cleaning old Gaia data..."
rm -rf "$GAIA_HOME"

log "[3] Initializing Gaia node..."
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

log "[4] Downloading genesis..."
download_genesis

log "[5] Setting minimum gas prices..."
if grep -q "^minimum-gas-prices" "$GAIA_HOME/config/app.toml"; then
    sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"$MIN_GAS\"|" "$GAIA_HOME/config/app.toml"
else
    echo "minimum-gas-prices = \"$MIN_GAS\"" >> "$GAIA_HOME/config/app.toml"
fi

log "[6] Adding persistent peers..."
sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$GAIA_HOME/config/config.toml"

log "[7] Configuring state sync for fast sync..."
sed -i "s|^enable *=.*|enable = true|" "$GAIA_HOME/config/config.toml"
sed -i "s|^rpc_servers *=.*|rpc_servers = \"$STATE_SYNC_RPC,$STATE_SYNC_RPC\"|" "$GAIA_HOME/config/config.toml"
sed -i "s|^trust_height *=.*|trust_height = $TRUST_HEIGHT|" "$GAIA_HOME/config/config.toml"
sed -i "s|^trust_hash *=.*|trust_hash = \"$TRUST_HASH\"|" "$GAIA_HOME/config/config.toml"

log "[8] Summary of config files:"
ls -lh "$GAIA_HOME/config"

# ================= START NODE IN TMUX =================
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "Tmux session $SESSION_NAME already exists, attaching..."
    tmux attach -t "$SESSION_NAME"
else
    log "[9] Starting Gaia node inside tmux session '$SESSION_NAME'..."
    tmux new-session -d -s "$SESSION_NAME" "gaiad start --home '$GAIA_HOME' --minimum-gas-prices='$MIN_GAS'"
    log "Node started in background tmux session. Attach anytime with: tmux attach -t $SESSION_NAME"
fi

log "Gaia setup complete. After the node is synced, you can manage your wallet with:"
echo "  gaiad keys add <name> --home $GAIA_HOME --keyring-backend test"
echo "  gaiad query bank balances <address> --home $GAIA_HOME"
echo "  gaiad tx bank send <from> <to> <amount> --home $GAIA_HOME --fees $MIN_GAS --chain-id $CHAIN_ID"
