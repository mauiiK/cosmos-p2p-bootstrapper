#!/bin/bash
set -euo pipefail

# -------------------------------
# Gaia mainnet node installer
# -------------------------------

GAIA_HOME="${GAIA_HOME:-$HOME/.gaia}"
CHAIN_ID="cosmoshub-4"
MONIKER="my-node"
MIN_GAS="0.025uatom"
GENESIS_URLS=(
    "https://snapshots-cosmoshub.mirror.guru/genesis.json"
    "https://mainnet-genesis.cosmos.network/genesis.json"
)

PEERS="ba3bacc714817218562f743178228f23678b2873@public-seed-node.cosmoshub.certus.one:26656,ade4d8bc8cbe0146ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:14956"

# -------------------------------
# Logging helpers
# -------------------------------
log() { echo -e "[`date '+%H:%M:%S'`] $*"; }

# -------------------------------
# Tool checks and install
# -------------------------------
log "Checking required commands..."
for cmd in gaiad curl jq gzip sed; do
    if ! command -v $cmd &>/dev/null; then
        log "$cmd not found. Installing..."
        if [[ "$cmd" == "gaiad" ]]; then
            log "Please install gaiad manually: https://docs.cosmos.network/main/tools/gaia"
            exit 1
        else
            sudo apt-get update && sudo apt-get install -y $cmd
        fi
    fi
done

# -------------------------------
# Clean old data
# -------------------------------
log "[1] Removing old Gaia data..."
rm -rf "$GAIA_HOME"

# -------------------------------
# Initialize Gaia node
# -------------------------------
log "[2] Initializing Gaia node..."
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

# -------------------------------
# Download genesis with fallback
# -------------------------------
download_genesis() {
    for url in "${GENESIS_URLS[@]}"; do
        log "[3] Downloading genesis from $url ..."
        curl -Ls "$url" -o "$GAIA_HOME/config/genesis.json"
        if jq empty "$GAIA_HOME/config/genesis.json" &>/dev/null; then
            log "Genesis downloaded and validated successfully."
            return 0
        else
            log "Genesis invalid JSON from $url, trying next..."
        fi
    done
    log "All genesis download attempts failed. Exiting."
    exit 1
}
download_genesis

# -------------------------------
# Set minimum gas prices
# -------------------------------
log "[4] Setting minimum gas prices..."
if grep -q "^minimum-gas-prices" "$GAIA_HOME/config/app.toml"; then
    sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"$MIN_GAS\"|" "$GAIA_HOME/config/app.toml"
else
    echo "minimum-gas-prices = \"$MIN_GAS\"" >> "$GAIA_HOME/config/app.toml"
fi

# -------------------------------
# Add persistent peers
# -------------------------------
log "[5] Adding persistent peers..."
sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$GAIA_HOME/config/config.toml"

# -------------------------------
# Show summary
# -------------------------------
log "[SUMMARY] Genesis file:"
ls -lh "$GAIA_HOME/config/genesis.json"
log "Config files in $GAIA_HOME/config:"
ls "$GAIA_HOME/config"

# -------------------------------
# Start Gaia node
# -------------------------------
log "[6] Starting Gaia node..."
log "If this is the first run, it will take some time to initialize..."
gaiad start --home "$GAIA_HOME" --minimum-gas-prices="$MIN_GAS"
