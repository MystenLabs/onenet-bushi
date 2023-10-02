// example flow
// 1. Onenet mints a battle pass
// 2. Onenet sends the battle pass to a custodial wallet
// 3. Updates for the battle pass are unlocked
// 4. User's custodial wallet updates the battle pass fields
// 5. User's custodial wallet sends the battle pass to a user's non-custodial wallet
import {Ed25519Keypair, JsonRpcProvider, RawSigner, TransactionBlock, fromB64, testnetConnection} from "@mysten/sui.js"
import * as dotenv from "dotenv";
dotenv.config();


const PACKAGE_ID = process.env.PACKAGE_ID!;
const BP_MINT_CAP_ID = process.env.BP_MINT_CAP!;
const ONENET_PRIVATE_KEY = process.env.ONENET_PRIVATE_KEY!;
const CUSTODIAL_WALLET_PRIVATE_KEY = process.env.CUSTODIAL_WALLET_PRIVATE_KEY!;
// put another address here below because this is mine
const nonCustodialWalletAddress = "0xc692f98df9b0f68cda6627ff61a98eb3ac9f8a28daee3da8b64fc2f324e98f05";


/// helper to make keypair from private key that is in string format
function getKeyPair(privateKey: string): Ed25519Keypair{
  let privateKeyArray = Array.from(fromB64(privateKey));
  privateKeyArray.shift();
  return Ed25519Keypair.fromSecretKey(Uint8Array.from(privateKeyArray));
}


// make the public key for onenet from the private key stored in .env
const onenetKeyPair = getKeyPair(ONENET_PRIVATE_KEY);
const custodialWalletKeyPair = getKeyPair(CUSTODIAL_WALLET_PRIVATE_KEY);
// address of custodial wallet from keypair
const custodialWalletAddress = custodialWalletKeyPair.getPublicKey().toSuiAddress();


// initialize a provider for testnet
const provider = new JsonRpcProvider(testnetConnection);
// make a signer for onenet
const onenet = new RawSigner(onenetKeyPair, provider);
// make a signer for custodial wallet
const custodialWallet = new RawSigner(custodialWalletKeyPair, provider);

// Onenet mints a battle pass and sends it to a user
async function mintToAddress(recipient: string) {

  let txb = new TransactionBlock();

  // call the mint_default to mint a battle pass
  let battlePass = txb.moveCall(
    {
      target: `${PACKAGE_ID}::battle_pass::mint_default`,
      arguments: [
        txb.object(BP_MINT_CAP_ID), 
        txb.pure("Play Bushi to earn in-game assets using this battle pass", "string"),
        txb.pure("https://dummy.com", "string"),
        txb.pure("70", "u64"),
        txb.pure("1000", "u64"),
        txb.pure("1", "u64"),
        txb.pure("1", "u64"),
        txb.pure("1", "bool"),
      ]
    }
  )
  
  // transfer the battle pass to the custodial wallet
  txb.transferObjects([battlePass], txb.pure(recipient));

  // arbitrary value for gas budget
  txb.setGasBudget(100000000);
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

// create an unlock updates ticket and transfer it to an address
async function createUnlockUpdatesTicket(recipient: string, battlePassId: string) {

  let txb = new TransactionBlock();

  // call the create_unlock_updates_ticket to create a ticket
  let unlockUpdatesTicket = txb.moveCall(
    {
      target: `${PACKAGE_ID}::battle_pass::create_unlock_updates_ticket`,
      arguments: [
        txb.object(BP_MINT_CAP_ID),
        txb.pure(battlePassId),
      ]
    }
  )

  // transfer the ticket to the custodial wallet
  txb.transferObjects([unlockUpdatesTicket], txb.pure(recipient));

  // arbitrary value for gas budget
  txb.setGasBudget(100000000);
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

// TODO: make this transaction sponsored
async function unlockUpdates(battlePassId: string, unlockUpdatesTicketId: string) {

  let txb = new TransactionBlock();

  // call the unlock_updates to unlock updates for the battle pass
  txb.moveCall({
    target: `${PACKAGE_ID}::battle_pass::unlock_updates`,
    arguments: [txb.object(battlePassId), txb.object(unlockUpdatesTicketId)]
  }
  )

  // sign and execute the transaction
  // arbitrary value for gas budget
  txb.setGasBudget(100000000);
  let result = await custodialWallet.signAndExecuteTransactionBlock({
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

// TODO: make this transaction sponsored
async function update(battlePassId: string, newLevel: string, newXp: string, newXpToNextLevel: string){

  let txb = new TransactionBlock();

  // call the update function to update the battle pass fields
  txb.moveCall(
    {
      target: `${PACKAGE_ID}::battle_pass::update`,
      arguments: [
        txb.object(battlePassId),
        txb.pure(newLevel, "u64"),
        txb.pure(newXp, "u64"),
        txb.pure(newXpToNextLevel, "u64"),
      ]
    }
  )

  // sign and execute the transaction
  // arbitrary value for gas budget
  txb.setGasBudget(100000000);
  let result = await custodialWallet.signAndExecuteTransactionBlock({
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

// TODO: make this transaction sponsored
async function lockUpdatesAndTransferToNonCustodialWallet(battlePassId: string, nonCustodialWalletAddress: string) {

  let txb = new TransactionBlock();

  // call the lock function to lock the battle pass
  txb.moveCall(
    {
      target: `${PACKAGE_ID}::battle_pass::lock_updates`,
      arguments: [
        txb.object(battlePassId),
      ]
    }
  )

  // transfer the battle pass to the non custodial wallet
  txb.transferObjects([txb.object(battlePassId)], txb.pure(nonCustodialWalletAddress));

  // sign and execute the transaction
  // arbitrary value for gas budget
  txb.setGasBudget(100000000);
  let result = await custodialWallet.signAndExecuteTransactionBlock({
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

async function main(){

  // mint a battle pass to the custodial wallet
  let mintResult = await mintToAddress(custodialWalletAddress);
  console.log(mintResult);
  // find the battle pass id from the mint result
  let [battlePass]: any = mintResult.objectChanges?.filter((objectChange) => (objectChange.type === "created" && objectChange.objectType == `${PACKAGE_ID}::battle_pass::BattlePass`));
  console.log(battlePass);
  let battlePassId = battlePass.objectId;
  
  // create an update ticket and transfer it to the custodial wallet
  let unlockUpdatesTicketResult = await createUnlockUpdatesTicket(custodialWalletAddress, battlePassId);
  // find the unlock updates ticket id from the result
  let [unlockUpdatesTicket]: any = unlockUpdatesTicketResult.objectChanges?.filter((objectChange) => (objectChange.type === "created" && objectChange.objectType == `${PACKAGE_ID}::battle_pass::UnlockUpdatesTicket`));
  let unlockUpdatesTicketId = unlockUpdatesTicket.objectId;

  // unlock updates for the battle pass
  let unlockUpdatesResult = await unlockUpdates(battlePassId, unlockUpdatesTicketId);

  // update the battle pass fields
  await update(battlePassId, "2", "100", "1000");
  // lock updates and transfer the battle pass to the non custodial wallet
  let lockUpdatesAndTransferResult = await lockUpdatesAndTransferToNonCustodialWallet(battlePassId, nonCustodialWalletAddress);

}

main();



