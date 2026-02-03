#!/bin/bash
set -euo pipefail

# ======================================
# Quick Install + State Sync Node Script
# for Cosmos Hub Mainnet (cosmoshub-4)
# ======================================

############################
# USER CONFIG (Change if desired)
############################

GAIA_HOME="$HOME/.gaia"
CHAIN_ID="cosmoshub-4"
MONIKER="${MONIKER:-kubeo}"
MIN_GAS="0.001uatom"

# State Sync RPCs to trust for syncing
# (multiple for redundancy)
RPC_SERVERS="https://rpc.cosmos.network:443,https://cosmos-rpc.polkachu.com:443,https://rpc-cosmoshub-ia.cosmosia.notional.ventures:443"

########################################
# LOGGING
########################################

log() { echo -e "\e[34m[`date '+%H:%M:%S'`]\e[0m $*"; }

########################################
# CHECK DEPENDENCIES
########################################

install_if_missing() {
    if ! command -v "$1" &>/dev/null; then
        log "Installing $1..."
        sudo apt update
        sudo apt install -y "$1"
    fi
}

log "=== Checking dependencies ==="
for tool in curl jq wget tar sed tmux; do
    install_if_missing "$tool"
done

########################################
# INSTALL gaiad (official Gaia release)
########################################

log "=== Installing Cosmos Gaia ==="
# Try downloading prebuilt binary if available
GAIA_VERSION="v28.0.1" # adjust if a newer recommended version exists
BIN="gaiad"
INSTALL_DIR="$HOME/go/bin"

if ! command -v gaiad &>/dev/null; then
    mkdir -p "$INSTALL_DIR"
    log "Downloading gaiad $GAIA_VERSION..."
    wget -q "https://github.com/cosmos/gaia/releases/download/${GAIA_VERSION}/gaiad_${GAIA_VERSION}_linux_amd64.tar.gz"
    tar -xzf "gaiad_${GAIA_VERSION}_linux_amd64.tar.gz"
    mv gaiad "$INSTALL_DIR/"
    rm -f "gaiad_${GAIA_VERSION}_linux_amd64.tar.gz"
    export PATH="$INSTALL_DIR:$PATH"
else
    log "gaiad already installed: $(gaiad version)"
fi

########################################
# INIT COSMOS CONFIG
########################################

log "=== Initializing Gaia config for cosmoshub-4 ==="
rm -rf "$GAIA_HOME"
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

########################################
# DOWNLOAD GENESIS + ADDRBOOK
########################################

log "=== Downloading mainnet genesis and addrbook ==="
# errors here
mkdir -p "$GAIA_HOME/config"
curl -Ls "https://github.com/cosmos/mainnet/raw/master/genesis/genesis.cosmoshub-4.json.gz" \
     -o "$GAIA_HOME/config/genesis.json.gz"
gzip -d -f "$GAIA_HOME/config/genesis.json.gz"

# Optional: community published addrbook for peers
curl -Ls "https://snapshots.kjnodes.com/cosmoshub/addrbook.json" \
     -o "$GAIA_HOME/config/addrbook.json"

########################################
# CONFIGURE PERSISTENT PEERS (optional)
########################################

log "=== Updating peers ==="
PEERS="d6318b3bd51a5e2b8ed08f2e520d50289ed32bf1@52.79.43.100:26656"
sed -i "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" "$GAIA_HOME/config/config.toml"

########################################
# STATE SYNC SETUP
########################################

log "=== Configuring State Sync ==="

LATEST=$(curl -s "$RPC_SERVERS"/status | jq -r '.result.sync_info.latest_block_height')
# Use a safe height ~1000 blocks prior
TRUST_HEIGHT=$((LATEST - 1000))
TRUST_HASH=$(curl -s "$RPC_SERVERS"/block?height=$TRUST_HEIGHT | jq -r '.result.block_id.hash')

log "HEIGHT $LATEST, TRUST_HEIGHT $TRUST_HEIGHT, HASH $TRUST_HASH"

sed -i "s|enable *=.*|enable = true|" "$GAIA_HOME/config/config.toml"
sed -i "s|rpc_servers *=.*|rpc_servers = \"$RPC_SERVERS\"|" "$GAIA_HOME/config/config.toml"
sed -i "s|trust_height *=.*|trust_height = $TRUST_HEIGHT|" "$GAIA_HOME/config/config.toml"
sed -i "s|trust_hash *=.*|trust_hash = \"$TRUST_HASH\"|" "$GAIA_HOME/config/config.toml"

########################################
# SET MIN GAS PRICES
########################################

log "=== Setting minimum gas prices ==="
sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"$MIN_GAS\"|" "$GAIA_HOME/config/app.toml"

########################################
# START NODE
########################################

log "=== Starting Gaia in tmux session cosmoshub_node ==="
SESSION="cosmoshub_node"
if tmux has-session -t "$SESSION" 2>/dev/null; then
    log "Attaching to existing session..."
    tmux attach -t "$SESSION"
else
    tmux new-session -d -s "$SESSION" "gaiad start --x-crisis-skip-assert-invariants --home '$GAIA_HOME'"
    log "Node started. Attach with: tmux attach -t $SESSION"
fi

log "=== DONE — Syncing mainnet ==="
echo "Use: gaiad query bank balances <your_address> --home $GAIA_HOME"
echo "Use: gaiad tx bank send <to_address> <amt>uatom --home $GAIA_HOME --chain-id cosmoshub-4"
