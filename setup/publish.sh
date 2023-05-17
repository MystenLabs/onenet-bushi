#!/bin/bash

# check dependencies are available.
for i in jq sui; do
  if ! command -V ${i} 2>/dev/null; then
    echo "${i} is not installed"
    exit 1
  fi
done

# default network is localnet
NETWORK=http://localhost:9000
FAUCET=https://localhost:9000/gas

# If otherwise specified chose testnet or devnet
if [ $# -ne 0 ]; then
  if [ $1 = "testnet" ]; then
    NETWORK="https://fullnode.testnet.sui.io:443"
    FAUCET="https://faucet.testnet.sui.io/gas"
  fi
  if [ $1 = "devnet" ]; then
    NETWORK="https://fullnode.devnet.sui.io:443"
    FAUCET="https://faucet.devnet.sui.io/gas"
  fi
fi

# publishes the script inside folder bushi_v1
publish_res=$(sui client publish --gas-budget 2000000000 --json ../bushi_v1)

echo ${publish_res} >.publish.res.json

if [[ "$publish_res" =~ "error" ]]; then
  # If yes, print the error message and exit the script
  echo "Error during move contract publishing.  Details : $publish_res"
  exit 1
fi

PACKAGE_ID=$(echo "${publish_res}" | jq -r '.effects.created[] | select(.owner == "Immutable").reference.objectId')
newObjs=$(echo "$publish_res" | jq -r '.objectChanges[] | select(.type == "created")')
UPGRADE_CAP_ID=$(echo "$newObjs" | jq -r 'select (.objectType | contains("::package::UpgradeCap)).objectId')

echo "Setting up environmental variables..."

cat >.env <<-API_ENV
SUI_NETWORK=$NETWORK
PACKAGE_ID=$PACKAGE_ID
UPGRADE_CAP_ID=$UPGRADE_CAP_ID
ADMIN_PHRASE=
API_ENV

echo "Contract Deployment finished!"
