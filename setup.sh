#!/bin/bash
# Please note this resets configs, if you already partially or fully installed use the helper.sh instead or you can potentially LOSE earnings!!
set -euo pipefail

# =====================
# CONFIGURATION
# =====================
GAIA_HOME="${HOME}/.gaia"
CHAIN_ID="cosmoshub-4"
MONIKER="my-node"
MIN_GAS="0.025uatom"
EXPECTED_GENESIS_SIZE=5000000  # bytes, approximate for fallback logic

# Multiple potential genesis/snapshot URLs
GENESIS_URLS=(
  "https://github.com/cosmos/mainnet/raw/master/genesis/genesis.cosmoshub-4.json.gz"
  "https://snapshots-cosmoshub.certus.one/genesis.json.gz"
  "https://snapshots.polkachu.com/genesis.json.gz"
)

PEERS="ba3bacc714817218562f743178228f23678b2873@public-seed-node.cosmoshub.certus.one:26656,ade4d8bc8cbe0146ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:14956"

# =====================
# HELPER FUNCTIONS
# =====================
function log() {
    echo -e "[`date +"%H:%M:%S"`] $1"
}

function check_install() {
    command -v $1 >/dev/null 2>&1 || {
        log "$1 not found. Installing..."
        if [[ "$1" == "gaiad" ]]; then
            log "Please install gaiad manually from https://docs.cosmos.network/master/run-node/install.html"
            exit 1
        elif [[ "$1" == "apt-get" ]]; then
            sudo apt update
        else
            sudo apt install -y $1
        fi
    }
}

function download_genesis() {
    local url=$1
    local dest=$2

    log "Attempting to download genesis from $url"
    curl -fSL "$url" -o "$dest" && log "Downloaded $url successfully" && return 0
    log "Failed to download from $url"
    return 1
}

# =====================
# CHECK DEPENDENCIES
# =====================
log "Checking dependencies..."
for cmd in gaiad curl gzip sed tar lz4; do
    check_install $cmd
done

# =====================
# CLEAN OLD DATA
# =====================
log "Removing old Gaia data..."
rm -rf "$GAIA_HOME"

# =====================
# INIT GAIA NODE
# =====================
log "Initializing Gaia node..."
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

# =====================
# DOWNLOAD & DECOMPRESS GENESIS
# =====================
GENESIS_DEST="$GAIA_HOME/config/genesis.json.gz"
SUCCESS=false

for url in "${GENESIS_URLS[@]}"; do
    if download_genesis "$url" "$GENESIS_DEST"; then
        FILE_SIZE=$(stat -c%s "$GENESIS_DEST" 2>/dev/null || stat -f%z "$GENESIS_DEST")
        log "Downloaded file size: $FILE_SIZE bytes"
        if (( FILE_SIZE >= EXPECTED_GENESIS_SIZE )); then
            SUCCESS=true
            break
        else
            log "File size smaller than expected ($EXPECTED_GENESIS_SIZE), trying next URL..."
        fi
    fi
done

if [ "$SUCCESS" = false ]; then
    log "Failed to download a valid genesis file from all sources. Exiting."
    exit 1
fi

log "Decompressing genesis..."
gzip -d -f "$GENESIS_DEST"

# =====================
# CONFIGURE GAIA
# =====================
log "Setting minimum gas prices..."
sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"$MIN_GAS\"|" "$GAIA_HOME/config/app.toml" \
    || echo "minimum-gas-prices = \"$MIN_GAS\"" >> "$GAIA_HOME/config/app.toml"

log "Adding persistent peers..."
sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$GAIA_HOME/config/config.toml" \
    || echo "persistent_peers = \"$PEERS\"" >> "$GAIA_HOME/config/config.toml"

# =====================
# SUMMARY
# =====================
log "[SUMMARY]"
ls -lh "$GAIA_HOME/config/genesis.json"
echo "Config files in $GAIA_HOME/config:"
ls "$GAIA_HOME/config"

# =====================
# START NODE
# =====================
log "Starting Gaia node..."
gaiad start --home "$GAIA_HOME" --minimum-gas-prices="$MIN_GAS"
