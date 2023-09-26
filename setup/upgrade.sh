UPGRADE_CAP_ID= # add here your upgrade_cap_id
publish_res=$(sui client upgrade --gas-budget 200000000 --upgrade-capability $UPGRADE_CAP_ID --json ../bushi_v2 --skip-dependency-verification)

echo ${publish_res} >.publish_upgrade.res.json

if [[ "$publish_res" =~ "error" ]]; then
  # If yes, print the error message and exit the script
  echo "Error during move contract upgrade.  Details : $publish_res"
  exit 1
fi
echo "Contract Upgrade finished!"

DIGEST=$(echo "${publish_res}" | jq -r '.digest')
PACKAGE_ID=$(echo "${publish_res}" | jq -r '.effects.created[] | select(.owner == "Immutable").reference.objectId')

echo "New Package ID(v2): $PACKAGE_ID"

echo "Setting .env.upgrade variables..."

cat >.env.upgrade <<-UPGRADE_ENV
DIGEST=$DIGEST
UPGRADE_CAP_ID=$UPGRADE_CAP_ID
NEW_PACKAGE_ID=$PACKAGE_ID
ADMIN_PRIVATE_KEY=$(cat ~/.sui/sui_config/sui.keystore | jq -r '.[0]')
UPGRADE_ENV

echo "Contract Deployment finished!"