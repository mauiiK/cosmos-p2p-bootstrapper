#!/bin/bash
set -euo pipefail

########################################
# USER CONFIG — customize if desired
########################################

GAIA_HOME="$HOME/.gaia"
CHAIN_ID="custom-chain-1"
MONIKER="my-node"
DENOM="stake"
STAKE_AMOUNT="1000000000${DENOM}"
GENTX_AMOUNT="500000000${DENOM}"
SESSION_NAME="gaia_node"
WALLET_NAME="validator"

########################################
# LOGGING
########################################

log() { echo -e "\e[34m[`date '+%H:%M:%S'`]\e[0m $*"; }

########################################
# DEPENDENCY CHECK
########################################

install_if_missing() {
    if ! command -v "$1" &>/dev/null; then
        log "Installing missing tool: $1"
        sudo apt update
        sudo apt install -y "$1"
    fi
}

log "Checking and installing dependencies..."
for tool in curl jq wget tar sed tmux git make gcc; do
    install_if_missing "$tool"
done

########################################
# INSTALL GO
########################################

log "Installing Go 1.23.3..."
sudo rm -rf /usr/local/go
wget -q https://dl.google.com/go/go1.23.3.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.23.3.linux-amd64.tar.gz
rm -f go1.23.3.linux-amd64.tar.gz
export PATH="/usr/local/go/bin:$PATH"
echo 'export PATH="/usr/local/go/bin:$PATH"' >> ~/.profile

log "Go version: $(go version)"

########################################
# BUILD GAIA (Cosmos Hub app framework)
########################################

log "Cloning and building Gaia app..."
mkdir -p "$HOME/cosmos"
cd "$HOME/cosmos"

if [[ ! -d "gaia" ]]; then
    git clone https://github.com/cosmos/gaia.git
fi
cd gaia
git fetch --all --tags
git checkout v24.0.0

log "Compiling Gaia (takes a few minutes)..."
make install

log "Gaia install check: $(gaiad version)"

########################################
# CLEAN & INIT NODE
########################################

log "Removing old chain data..."
rm -rf "$GAIA_HOME"

log "Initializing node..."
gaiad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$GAIA_HOME"

########################################
# CREATE KEYS & GENESIS ACCOUNTS
########################################

log "Creating wallet: $WALLET_NAME"
gaiad keys add "$WALLET_NAME" --home "$GAIA_HOME" --keyring-backend test

ADDR=$(gaiad keys show "$WALLET_NAME" -a --home "$GAIA_HOME" --keyring-backend test)
log "Adding genesis account with $STAKE_AMOUNT to $ADDR"
gaiad add-genesis-account "$ADDR" "$STAKE_AMOUNT" --home "$GAIA_HOME" --keyring-backend test

########################################
# GENERATE GENTX
########################################

log "Generating gentx of $GENTX_AMOUNT..."
gaiad genesis gentx "$WALLET_NAME" "$GENTX_AMOUNT" --chain-id "$CHAIN_ID" --home "$GAIA_HOME" --keyring-backend test

log "Collecting gentxs..."
gaiad genesis collect-gentxs --home "$GAIA_HOME"

########################################
# VALIDATE GENESIS
########################################

log "Validating genesis file..."
gaiad validate-genesis --home "$GAIA_HOME"

########################################
# START NODE (tmux)
########################################

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "Tmux session exists — attaching..."
    tmux attach -t "$SESSION_NAME"
else
    log "Starting chain in tmux session: $SESSION_NAME"
    tmux new-session -d -s "$SESSION_NAME" \
        "gaiad start --home '$GAIA_HOME' --minimum-gas-prices='0${DENOM}'"
    log "Started. Use: tmux attach -t $SESSION_NAME"
fi

log "=== CHAIN READY ==="
echo "Wallet address: $ADDR"
echo "Query balance after chain is running:"
echo "  gaiad query bank balances $ADDR --home $GAIA_HOME"
echo "Send coins example:"
echo "  gaiad tx bank send $ADDR <dest> 10${DENOM} --home $GAIA_HOME --fees 2000${DENOM} --chain-id $CHAIN_ID"
