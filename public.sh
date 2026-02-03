#!/bin/bash
set -euo pipefail

# ======================================
# Cosmos Hub (cosmoshub-4)
# Gaia Full Node – State Sync Installer
# ======================================

############################
# USER CONFIG
############################

GAIA_HOME="$HOME/.gaia"
CHAIN_ID="cosmoshub-4"
MONIKER="${MONIKER:-kubeo}"
MIN_GAS="0.001uatom"

# RPC candidates (checked sequentially)
RPC_CANDIDATES=(
  "https://rpc.cosmos.network:443"
  "https://cosmos-rpc.polkachu.com:443"
  "https://rpc-cosmoshub-ia.cosmosia.notional.ventures:443"
)

########################################
# LOGGING
########################################

log() {
  echo -e "\e[34m[`date '+%H:%M:%S'`]\e[0m $*"
}

die() {
  echo -e "\e[31mERROR:\e[0m $*" >&2
  exit 1
}

########################################
# DEPENDENCIES
########################################

install_if_missing() {
  if ! command -v "$1" &>/dev/null; then
    log "Installing $1..."
    sudo apt update
    sudo apt install -y "$1"
  fi
}

log "=== Checking dependencies ==="
for tool in curl jq wget tar sed tmux gzip; do
  install_if_missing "$tool"
done

########################################
# INSTALL GAIAD
########################################

log "=== Installing gaiad ==="

GAIA_VERSION="v28.0.1"
INSTALL_DIR="$HOME/go/bin"

if ! command -v gaiad &>/dev/null; then
  mkdir -p "$INSTALL_DIR"
  wget -q "https://github.com/cosmos/gaia/releases/download/${GAIA_VERSION}/gaiad_${GAIA_VERSION}_linux_amd64.tar.gz"
  tar -xzf "gaiad_${GAIA_VERSION}_linux_amd64.tar.gz"
  mv gaiad "$INSTALL_DIR/"
  rm -f "gaiad_${GAIA_VERSION}_linux_amd64.tar.gz"
  export PATH="$INSTALL_DIR:$PATH"
else
  log "gaiad already installed: $(gaiad version)"
fi

########################################
# INIT
########################################

log "=== Initializing chain ==="
rm -rf "$GAIA_HOME"
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

########################################
# GENESIS
########################################

log "=== Downloading genesis ==="
mkdir -p "$GAIA_HOME/config"

GENESIS_TMP="$GAIA_HOME/config/genesis.json.gz.tmp"
GENESIS_FINAL="$GAIA_HOME/config/genesis.json"

rm -f "$GENESIS_TMP" "$GENESIS_FINAL"

curl -L --fail --retry 5 --retry-delay 3 \
  "https://github.com/cosmos/mainnet/raw/master/genesis/genesis.cosmoshub-4.json.gz" \
  -o "$GENESIS_TMP"

gzip -dc "$GENESIS_TMP" > "$GENESIS_FINAL"
rm -f "$GENESIS_TMP"

########################################
# ADDRBOOK (BIG FILE SAFE DOWNLOAD)
########################################

log "=== Downloading addrbook (large file, resumable) ==="

ADDR_TMP="$GAIA_HOME/config/addrbook.json.tmp"
ADDR_FINAL="$GAIA_HOME/config/addrbook.json"

curl -L \
  --fail \
  --retry 10 \
  --retry-delay 5 \
  --connect-timeout 20 \
  --max-time 0 \
  --continue-at - \
  "https://snapshots.kjnodes.com/cosmoshub/addrbook.json" \
  -o "$ADDR_TMP"

mv "$ADDR_TMP" "$ADDR_FINAL"

########################################
# PEERS
########################################

log "=== Configuring peers ==="

PEERS="d6318b3bd51a5e2b8ed08f2e520d50289ed32bf1@52.79.43.100:26656"

sed -i "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" \
  "$GAIA_HOME/config/config.toml"

########################################
# PICK HEALTHY RPC
########################################

log "=== Selecting healthy RPC ==="

RPC=""
for CANDIDATE in "${RPC_CANDIDATES[@]}"; do
  if curl -sf "$CANDIDATE/status" | jq -e '.result.sync_info.latest_block_height' >/dev/null; then
    RPC="$CANDIDATE"
    break
  fi
done

[ -z "$RPC" ] && die "No healthy RPC endpoint found"

log "Using RPC: $RPC"

########################################
# STATE SYNC
########################################

log "=== Configuring state sync ==="

LATEST_HEIGHT=$(curl -s "$RPC/status" | jq -r '.result.sync_info.latest_block_height')
[ "$LATEST_HEIGHT" = "null" ] && die "Failed to fetch latest height"

TRUST_HEIGHT=$((LATEST_HEIGHT - 1000))

TRUST_HASH=$(curl -s "$RPC/block?height=$TRUST_HEIGHT" | jq -r '.result.block_id.hash')
[ "$TRUST_HASH" = "null" ] && die "Failed to fetch trust hash"

log "Latest height : $LATEST_HEIGHT"
log "Trust height  : $TRUST_HEIGHT"
log "Trust hash    : $TRUST_HASH"

sed -i \
  -e "s|enable *=.*|enable = true|" \
  -e "s|rpc_servers *=.*|rpc_servers = \"$RPC,$RPC\"|" \
  -e "s|trust_height *=.*|trust_height = $TRUST_HEIGHT|" \
  -e "s|trust_hash *=.*|trust_hash = \"$TRUST_HASH\"|" \
  "$GAIA_HOME/config/config.toml"

########################################
# GAS
########################################

log "=== Setting minimum gas prices ==="

sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"$MIN_GAS\"|" \
  "$GAIA_HOME/config/app.toml"

########################################
# START NODE
########################################

log "=== Starting gaiad ==="

SESSION="cosmoshub_node"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach -t "$SESSION"
else
  tmux new-session -d -s "$SESSION" \
    "gaiad start --x-crisis-skip-assert-invariants --home $GAIA_HOME"
  log "Node running in tmux session: $SESSION"
  log "Attach with: tmux attach -t $SESSION"
fi

log "=== DONE – STATE SYNC IN PROGRESS ==="
