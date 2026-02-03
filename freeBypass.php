#!/bin/bash
set -euo pipefail

########################################
# USER CONFIG
########################################

GAIA_HOME="$HOME/.gaia"
CHAIN_ID="cosmoshub-4"
MONIKER="my-node"
MIN_GAS="0.025uatom"
SESSION_NAME="gaia_node"

# Fallback genesis URLs
GENESIS_URLS=(
    "https://cosmoshub.snapshots.nodestake.top/genesis.json"
    "https://cosmoshub.stake.link/genesis.json"
)

# Some known public seed nodes (may change over time)
PEERS="ba3bacc714817218562f743178228f23678b2873@public-seed-node.cosmoshub.certus.one:26656,ade4d8bc8cbe0146ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:14956"

########################################
# HELPER FUNCTIONS
########################################

log() { echo -e "\e[34m[`date '+%H:%M:%S'`]\e[0m $*"; }

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log ">> Installing missing command: $1"
        sudo apt update
        sudo apt install -y "$1"
    fi
}

download_genesis() {
    mkdir -p "$GAIA_HOME/config"
    for url in "${GENESIS_URLS[@]}"; do
        log "Trying genesis from: $url"
        if curl -sL "$url" -o "$GAIA_HOME/config/genesis.json"; then
            # Quick sanity check: file should be JSON starting with '{'
            if [[ -s "$GAIA_HOME/config/genesis.json" && $(head -c1 "$GAIA_HOME/config/genesis.json") == "{" ]]; then
                log "Genesis downloaded and looks valid!"
                ls -lh "$GAIA_HOME/config/genesis.json"
                return 0
            fi
        fi
        log "Genesis invalid from $url, trying next..."
    done
    log "ERROR: could not get a valid genesis.json"
    exit 1
}

########################################
# REQUIREMENTS
########################################

log "=== Checking required tools ==="
for cmd in curl jq gzip tar sed tmux git make g++; do
    check_command "$cmd"
done

########################################
# BUILD GAIA v24
########################################

log "=== Cloning and building Gaia v24 ==="
mkdir -p "$HOME/cosmos"
cd "$HOME/cosmos"

if [[ ! -d "gaia" ]]; then
    git clone https://github.com/cosmos/gaia.git
fi
cd gaia
git fetch --all --tags
git checkout v24.0.0

log "Building Gaia (this may take ~2-4 minutes)..."
make install > /dev/null

log "Gaia version:"
gaiad version

########################################
# NODE INITIALIZATION
########################################

log "=== Cleaning old data ==="
rm -rf "$GAIA_HOME"

log "=== Initializing Gaia node ==="
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

########################################
# GET GENESIS
########################################

log "=== Downloading Cosmos Hub genesis.json ==="
download_genesis

########################################
# SET MIN GAS PRICE
########################################

log "=== Setting minimum gas prices ==="
if grep -q "^minimum-gas-prices" "$GAIA_HOME/config/app.toml"; then
    sed -i "s|^minimum-gas-prices=.*|minimum-gas-prices = \"$MIN_GAS\"|" "$GAIA_HOME/config/app.toml"
else
    echo "minimum-gas-prices = \"$MIN_GAS\"" >> "$GAIA_HOME/config/app.toml"
fi

########################################
# ADD PEERS
########################################

log "=== Adding persistent peers ==="
sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$GAIA_HOME/config/config.toml"

########################################
# STATE SYNC CONFIGURATION
########################################

log "=== Enabling state sync ==="

# Get latest block height & hash from a public RPC
RPC="https://rpc.cosmos.network:443"
LATEST_HEIGHT=$(curl -s "$RPC/status" | jq -r '.result.sync_info.latest_block_height')
# Use height ~5000 blocks behind to trust
TRUST_HEIGHT=$((LATEST_HEIGHT - 5000))
TRUST_HASH=$(curl -s "$RPC/block?height=$TRUST_HEIGHT" | jq -r '.result.block_id.hash')

log "Latest height: $LATEST_HEIGHT"
log "Using trust_height: $TRUST_HEIGHT"
log "Using trust_hash: $TRUST_HASH"

sed -i "s|^enable *=.*|enable = true|" "$GAIA_HOME/config/config.toml"
sed -i "s|^rpc_servers *=.*|rpc_servers = \"$RPC,$RPC\"|" "$GAIA_HOME/config/config.toml"
sed -i "s|^trust_height *=.*|trust_height = $TRUST_HEIGHT|" "$GAIA_HOME/config/config.toml"
sed -i "s|^trust_hash *=.*|trust_hash = \"$TRUST_HASH\"|" "$GAIA_HOME/config/config.toml"

########################################
# SHOW CONFIG
########################################

log "=== Config summary ==="
ls -lh "$GAIA_HOME/config"

########################################
# START NODE (in tmux)
########################################

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "Tmux session already exists. Attaching..."
    tmux attach -t "$SESSION_NAME"
else
    log "Starting Gaia node in tmux session: $SESSION_NAME"
    tmux new-session -d -s "$SESSION_NAME" \
        "gaiad start --home '$GAIA_HOME' --minimum-gas-prices='$MIN_GAS'"

    log "Node started in tmux session."
    log "Attach at any time with: tmux attach -t $SESSION_NAME"
fi

########################################
# CREATE A WALLET
########################################

# Ask user for wallet name
read -p "Enter a wallet name (no spaces): " WALLET_NAME

log "Creating wallet: $WALLET_NAME"
gaiad keys add "$WALLET_NAME" --home "$GAIA_HOME" --keyring-backend test

ADDRESS=$(gaiad keys show "$WALLET_NAME" -a --home "$GAIA_HOME" --keyring-backend test)
log "Your wallet address is: $ADDRESS"

log "=== DONE ==="
echo "You can now check balance once synced:"
echo "  gaiad query bank balances $ADDRESS --home $GAIA_HOME"
echo "Send txs like:"
echo "  gaiad tx bank send $ADDRESS <to_address> 10uatom --home $GAIA_HOME --fees $MIN_GAS --chain-id $CHAIN_ID"
