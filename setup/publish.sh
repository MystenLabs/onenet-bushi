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

DIGEST=$(echo "${publish_res}" | jq -r '.digest')
PACKAGE_ID=$(echo "${publish_res}" | jq -r '.effects.created[] | select(.owner == "Immutable").reference.objectId')
newObjs=$(echo "$publish_res" | jq -r '.objectChanges[] | select(.type == "created")')
UPGRADE_CAP_ID=$(echo "$newObjs" | jq -r 'select (.objectType | contains("::package::UpgradeCap")).objectId')
BP_MINT_CAP=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::mint_cap::MintCap") and contains("::battle_pass::BattlePass")) | .objectId')
CS_MINT_CAP=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::mint_cap::MintCap") and contains("::cosmetic_skin::CosmeticSkin")) | .objectId')
BP_COLLECTION_ID=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::collection::Collection") and contains("::battle_pass::BattlePass")) | .objectId')
CS_COLLECTION_ID=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::collection::Collection") and contains("::cosmetic_skin::CosmeticSkin")) | .objectId')
BP_ROYALTY_STRATEGY=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::royalty_strategy_bps::BpsRoyaltyStrategy") and contains("::battle_pass::BattlePass")) | .objectId')
CS_ROYALTY_STRATEGY=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::royalty_strategy_bps::BpsRoyaltyStrategy") and contains("::cosmetic_skin::CosmeticSkin")) | .objectId')
BP_DISPLAY=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::display::Display") and contains("::battle_pass::BattlePass")) | .objectId')
CS_DISPLAY=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::display::Display") and contains("::cosmetic_skin::CosmeticSkin")) | .objectId')
BP_TRANSFER_POLICY_CAP=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::transfer_policy::TransferPolicyCap") and contains("::battle_pass::BattlePass")) | .objectId')
CS_TRANSFER_POLICY_CAP=$(echo "$newObjs" | jq -r 'select(.objectType | contains("::transfer_policy::TransferPolicyCap") and contains("::cosmetic_skin::CosmeticSkin")) | .objectId')



echo "Setting up environmental variables..."

cat >.env <<-API_ENV
SUI_NETWORK=$NETWORK
DIGEST=$DIGEST
UPGRADE_CAP_ID=$UPGRADE_CAP_ID
PACKAGE_ID=$PACKAGE_ID
BP_MINT_CAP=$BP_MINT_CAP
CS_MINT_CAP=$CS_MINT_CAP
BP_COLLECTION_ID=$BP_COLLECTION_ID
CS_COLLECTION_ID=$CS_COLLECTION_ID
BP_ROYALTY_STRATEGY=$BP_ROYALTY_STRATEGY
CS_ROYALTY_STRATEGY=$CS_ROYALTY_STRATEGY
BP_DISPLAY=$BP_DISPLAY
CS_DISPLAY=$CS_DISPLAY
BP_TRANSFER_POLICY_CAP=$BP_TRANSFER_POLICY_CAP
CS_TRANSFER_POLICY_CAP=$CS_TRANSFER_POLICY_CAP
ADMIN_PHRASE=
ADMIN_ADDRESS=
NON_CUSTODIAN_ADDRESS=
API_ENV

echo "Contract Deployment finished!"
