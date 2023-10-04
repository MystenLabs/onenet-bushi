import {
  Ed25519Keypair,
  JsonRpcProvider,
  RawSigner,
  SuiTransactionBlockResponse,
  TransactionBlock,
  fromB64,
  testnetConnection,
} from "@mysten/sui.js";

import * as dotenv from "dotenv";
dotenv.config();

const packageID = process.env.PACKAGE_ID!;
const newPackageID = process.env.NEW_PACKAGE_ID;
const mintCap = process.env.CS_MINT_CAP!;

/// helper to make keypair from private key that is in string format
function getKeyPair(privateKey: string): Ed25519Keypair {
  let privateKeyArray = Array.from(fromB64(privateKey));
  privateKeyArray.shift();
  return Ed25519Keypair.fromSecretKey(Uint8Array.from(privateKeyArray));
}

// TODO: convert to new version of sui.js

// provider
const provider = new JsonRpcProvider(testnetConnection);

// make adminSigner
const onenetPrivKey = process.env.ADMIN_PRIVATE_KEY!;
const onenetKeyPair = getKeyPair(onenetPrivKey);
const onenet = new RawSigner(onenetKeyPair, provider);

// make userSigner (custodial)
const userPrivKey = process.env.USER_PRIVATE_KEY!;
const userKeyPair = getKeyPair(userPrivKey);
const userSigner = new RawSigner(userKeyPair, provider);

// mints a cosmetic skin and transfers it to user
async function mintWithDfs(
  userAddress: string
): Promise<SuiTransactionBlockResponse> {
  let txb = new TransactionBlock();

  // get a cosmetic skin
  let [cosmetic_skin] = txb.moveCall({
    target: `${newPackageID}::stats::mint_with_dfs`,
    arguments: [
      txb.object(mintCap),
      txb.pure("fairy skin"), // name
      txb.pure("a skin of a fairy"), // description
      txb.pure("dummy.com"), // image url
      txb.pure(1), // level
      txb.pure(3), // level cap
      txb.pure("1111"), // game asset ID
      txb.pure(["games", "kills"]), // stat_names
      txb.pure(["0", "0"]), // stat_values
    ],
  });

  // transfer it to user
  txb.transferObjects([cosmetic_skin], txb.pure(userAddress));

  // sign and execute the transaction
  let result = await onenet.signAndExecuteTransactionBlock({
    transactionBlock: txb,
    requestType: "WaitForLocalExecution",
    options: {
      showEffects: true,
      showEvents: true,
      showObjectChanges: true,
    },
  });
  return result;
}

// create an unlock updates ticket for the user and transfer it
async function createUnlockUpdatesTicket(
  cosmeticSkinId: string,
  userAddress: string
): Promise<SuiTransactionBlockResponse> {
  let txb = new TransactionBlock();

  const unlockUpdatesTicket = txb.moveCall({
    target: `${newPackageID}::cosmetic_skin::create_unlock_updates_ticket`,
    arguments: [txb.object(mintCap), txb.pure(cosmeticSkinId)],
  });

  txb.transferObjects([unlockUpdatesTicket], txb.pure(userAddress));

  // sign and execute the transaction
  let result = await onenet.signAndExecuteTransactionBlock({
    transactionBlock: txb,
    requestType: "WaitForLocalExecution",
    options: {
      showEffects: true,
      showEvents: true,
      showObjectChanges: true,
    },
  });
  return result;
}

async function unlockUpdates(
  cosmeticSkin: string,
  unlockUpdatesTicket: string
): Promise<SuiTransactionBlockResponse> {
  let txb = new TransactionBlock();

  txb.moveCall({
    target: `${newPackageID}::cosmetic_skin::unlock_updates`,
    arguments: [txb.object(cosmeticSkin), txb.object(unlockUpdatesTicket)],
  });

  // sign and execute the transaction
  let result = await userSigner.signAndExecuteTransactionBlock({
    transactionBlock: txb,
    requestType: "WaitForLocalExecution",
    options: {
      showEffects: true,
      showEvents: true,
      showObjectChanges: true,
    },
  });
  return result;
}

async function udateOrAddStats(
  cosmeticSkin: string
): Promise<SuiTransactionBlockResponse> {
  let txb = new TransactionBlock();

  txb.moveCall({
    target: `${newPackageID}::stats::update_or_add_stats`,
    arguments: [
      txb.object(cosmeticSkin),
      txb.pure(["kills"]),
      txb.pure(["20"]),
    ],
  });

  // sign and execute the transaction
  let result = await userSigner.signAndExecuteTransactionBlock({
    transactionBlock: txb,
    requestType: "WaitForLocalExecution",
    options: {
      showEffects: true,
      showEvents: true,
      showObjectChanges: true,
    },
  });
  return result;
}

// checks what dynamic fields the cosmetic skin has and formats the answer
async function readStatAndGameAssetIdValues(cosmeticSkin: string) {
  // get all dynamic fields
  let dynamicFieldsResponse = await provider.getDynamicFields({
    parentId: cosmeticSkin,
  });

  // this is for stats
  let statDataArray: { statName: string; statValue: string }[] = [];
  // this is for game_asset_id
  let gameAssetId = "not set";

  let dynamicFields = dynamicFieldsResponse.data;

  // for every one dynamic field, ask the provider for more details on it
  for (const dynamicField of dynamicFields) {
    let dynamicFieldKey = dynamicField.name;

    // check the type of the dynamic field key
    // if it is a game_asset_id
    if (dynamicFieldKey.type == `${newPackageID}::stats::GameAssetIDKey`) {
      // ask the provider
      let dynamicFieldResult = await provider.getDynamicFieldObject({
        parentId: cosmeticSkin,
        name: dynamicFieldKey,
      });
      let content: any = dynamicFieldResult.data?.content;

      // set the game asset id variable
      gameAssetId = content.fields.value;

      // else if it is a stat
    } else if (dynamicFieldKey.type == `${newPackageID}::stats::StatKey`) {
      // TODO: when updating to the new sdk version, it might be possible that this is dynamicFieldKey.value instead of value.name
      let statName = dynamicFieldKey.value.name;
      let dynamicFieldResult = await provider.getDynamicFieldObject({
        parentId: cosmeticSkin,
        name: dynamicFieldKey,
      });

      let content: any = dynamicFieldResult.data?.content;
      let statValue = content.fields.value as string;
      let statData = {
        statName,
        statValue,
      };
      statDataArray.push(statData);
    }
  }
  return { gameAssetId, statDataArray };
}

// get the value of a stat of a cosmetic skin
async function getStat(
  cosmeticSkin: string,
  statName: string
): Promise<string> {
  const dynamicFieldResult = await provider.getDynamicFieldObject({
    parentId: cosmeticSkin,
    name: { type: `${newPackageID}::stats::StatKey`, value: { name: statName } },
  });

  let content: any = dynamicFieldResult.data?.content;
  return content.fields.value as string;
}

async function getGameAssetId(cosmeticSkin: string): Promise<string> {
  const dynamicFieldResult = await provider.getDynamicFieldObject({
    parentId: cosmeticSkin,
    // found 'name' field by console-logging
    // 'value' field is necessary (fullnode throws error), although sdk does not complain
    name: {
      type: `${newPackageID}::stats::GameAssetIDKey`,
      value: { dummy_field: false },
    },
  });
  let content: any = dynamicFieldResult.data?.content;
  return content.fields.value as string;
}

// Note: console.log the results if you need them
// 1. create a cosmetic skin and transfer it to user: function -> mintWithDfs
// 2. print initial stat values and game asset ID of the cosmetic skin: function -> readStatAndGameAssetIdValues
// 3. create unlock updates ticket and transfer it to user: function -> createUnlockUpdatesTicket
// 4. unlock updates for the cosmetic skin: function -> unlockUpdates
// 5. update 'kills' value: function -> udateOrAddStats
// 6. print the value of kills: function -> getStat
// 7. find its game_asset_id: function -> getGameAssetId
async function main() {
  // or just set an address
  const userAddress = userKeyPair.getPublicKey().toSuiAddress();

  const mintResult = await mintWithDfs(userAddress);

  // find id of cosmetic skin created
  // in reality we could check the user's wallet or check a DB
  const [cosmeticSkinData]: any = mintResult.objectChanges?.filter(
    (elem) =>
      elem.type == "created" &&
      elem.objectType == `${packageID}::cosmetic_skin::CosmeticSkin`
  );
  const cosmeticSkin = cosmeticSkinData.objectId;
  console.log("Cosmetic skin id is: " + cosmeticSkin);

  let { gameAssetId, statDataArray } = await readStatAndGameAssetIdValues(
    cosmeticSkin
  );
  console.log("Game asset id has been set to " + gameAssetId);
  console.log("Stats are:");
  for (const statData of statDataArray) {
    console.log(`${statData.statName}: ${statData.statValue}`);
  }

  // create unlock updates ticket and transfer it to user
  const createUnlockUpdatesTicketResult = await createUnlockUpdatesTicket(
    cosmeticSkin,
    userAddress
  );

  // from the result, find the id of the unlock updates ticket
  const [unlockUpdatesTicketData]: any =
    createUnlockUpdatesTicketResult.objectChanges?.filter(
      (elem) =>
        elem.type == "created" &&
        elem.objectType == `${packageID}::cosmetic_skin::UnlockUpdatesTicket`
    );
  const unlockUpdatesTicket = unlockUpdatesTicketData.objectId;

  const unlockUpdatesResult = await unlockUpdates(
    cosmeticSkin,
    unlockUpdatesTicket
  );

  // now update the 'kills' stat to 20
  const updateOrAddStatsResult = await udateOrAddStats(cosmeticSkin);
  // console.log(updateOrAddStatsResult);

  // now check the kills updated value
  const killsStatValue = await getStat(cosmeticSkin, "kills");
  console.log("New value of kills is: " + killsStatValue);

  // find game asset id
  gameAssetId = await getGameAssetId(cosmeticSkin);
  console.log("Game asset id is: " + gameAssetId);
}

main();