#!/bin/bash
set -euo pipefail

# =========================
# User Config
# =========================
GAIA_HOME="$HOME/.gaia"
CHAIN_ID="cosmoshub-4"
MONIKER="my-node"
MIN_GAS="0.025uatom"

# Correct Gaia version for Cosmos Hub v20
GAIA_VERSION="v20.0.0"

# Official genesis / snapshot sources (fallback list)
GENESIS_URLS=(
  "https://github.com/cosmos/mainnet/raw/master/genesis/cosmoshub-4.json"
  "https://cosmoshub-snapshots.polkachu.com/genesis.json"
  "https://cosmoshub-snapshots.certus.one/genesis.json"
)

# Persistent peers
PEERS="ba3bacc714817218562f743178228f23678b2873@public-seed-node.cosmoshub.certus.one:26656,ade4d8bc8cbe0146ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:14956"

# =========================
# Helpers
# =========================

function log() {
    echo -e "[`date +"%H:%M:%S"`] $1"
}

function ensure_cmd() {
    if ! command -v "$1" &>/dev/null; then
        log "$1 not found. Installing..."
        if [[ "$1" == "curl" || "$1" == "jq" || "$1" == "gzip" || "$1" == "sed" ]]; then
            sudo apt-get update && sudo apt-get install -y "$1"
        else
            log "Please install $1 manually."
            exit 1
        fi
    fi
}

function download_genesis() {
    for url in "${GENESIS_URLS[@]}"; do
        log "Trying $url ..."
        curl -Ls "$url" -o "$GAIA_HOME/config/genesis.json"
        if [[ -s "$GAIA_HOME/config/genesis.json" ]]; then
            log "Genesis downloaded successfully."
            return 0
        else
            log "Failed to download genesis from $url, trying next..."
        fi
    done
    log "All genesis download attempts failed."
    exit 1
}

function check_gaiad_version() {
    if ! command -v gaiad &>/dev/null || [[ "$(gaiad version | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')" != "${GAIA_VERSION#v}" ]]; then
        log "Installing Gaia $GAIA_VERSION..."
        curl -Ls https://github.com/cosmos/gaia/releases/download/$GAIA_VERSION/gaiad-$GAIA_VERSION-linux-amd64 -o /usr/local/bin/gaiad
        chmod +x /usr/local/bin/gaiad
    fi
}

# =========================
# Install dependencies
# =========================
ensure_cmd curl
ensure_cmd jq
ensure_cmd gzip
ensure_cmd sed

# =========================
# Check Gaia version
# =========================
check_gaiad_version

# =========================
# Clean old data
# =========================
log "Removing old Gaia data..."
rm -rf "$GAIA_HOME"

# =========================
# Initialize Gaia
# =========================
log "Initializing Gaia node..."
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

# =========================
# Download Genesis
# =========================
log "Downloading Genesis..."
download_genesis

# =========================
# Set minimum gas prices
# =========================
log "Setting minimum gas prices..."
if grep -q "^minimum-gas-prices" "$GAIA_HOME/config/app.toml"; then
    sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"$MIN_GAS\"|" "$GAIA_HOME/config/app.toml"
else
    echo "minimum-gas-prices = \"$MIN_GAS\"" >> "$GAIA_HOME/config/app.toml"
fi

# =========================
# Add persistent peers
# =========================
log "Adding persistent peers..."
sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$GAIA_HOME/config/config.toml"

# =========================
# Show summary
# =========================
log "Genesis file:"
ls -lh "$GAIA_HOME/config/genesis.json"
log "Config files in $GAIA_HOME/config:"
ls "$GAIA_HOME/config"

# =========================
# Start Gaia
# =========================
log "Starting Gaia node..."
gaiad start --home "$GAIA_HOME" --minimum-gas-prices="$MIN_GAS"
