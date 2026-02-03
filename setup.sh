#!/bin/bash
set -e

GAIA_HOME="$HOME/.gaia"
CHAIN_ID="cosmoshub-4"
MONIKER="my-node"
MIN_GAS="0.025uatom"
GENESIS_GZ="https://github.com/cosmos/mainnet/raw/master/genesis/genesis.cosmoshub-4.json.gz"

# 1) Clean old data
echo "[1] Removing old Gaia data..."
rm -rf "$GAIA_HOME"

# 2) Initialize Gaia node (creates config files)
echo "[2] Initializing Gaia node..."
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

# 3) Download & decompress genesis
echo "[3] Downloading Cosmos Hub genesis..."
curl -Ls "$GENESIS_GZ" -o "$GAIA_HOME/config/genesis.json.gz"
echo "[4] Decompressing genesis..."
gzip -d -f "$GAIA_HOME/config/genesis.json.gz"

# 4) Set minimum gas prices
echo "[5] Setting minimum gas prices..."
sed -i "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"$MIN_GAS\"|" "$GAIA_HOME/config/app.toml"

# 5) Add persistent peers
echo "[6] Adding persistent peers..."
PEERS="ba3bacc714817218562f743178228f23678b2873@public-seed-node.cosmoshub.certus.one:26656,ade4d8bc8cbe0146ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:14956"
sed -i "s|^persistent_peers *=.*|persistent_peers = \"$PEERS\"|" "$GAIA_HOME/config/config.toml"

# 6) Show summary
echo "[SUMMARY]"
ls -lh "$GAIA_HOME/config/genesis.json"
echo "Config files in $GAIA_HOME/config:"
ls "$GAIA_HOME/config"

# 7) Start Gaia
echo "[7] Starting Gaia node..."
gaiad start --home "$GAIA_HOME" --minimum-gas-prices="$MIN_GAS"
