// Important: here I am using the version of the contracts without the rarity field
// so mint() is missing one argument
import {Ed25519Keypair, JsonRpcProvider, RawSigner, SUI_FRAMEWORK_ADDRESS, TransactionBlock, fromB64, testnetConnection} from "@mysten/sui.js"
import * as dotenv from "dotenv";
dotenv.config();


const PACKAGE_ID = process.env.PACKAGE_ID!;
const OB_KIOSK_PACKAGE_ID = process.env.OB_KIOSK_PACKAGE_ID!;
const NFT_PROTOCOL_PACKAGE_ID = process.env.NFT_PROTOCOL_PACKAGE_ID!;
const OB_PERMISSIONS_PACKAGE_ID = process.env.OB_PERMISSIONS_PACKAGE_ID!;
const MINT_CAP_ID = process.env.MINT_CAP_ID!;
const PUBLISHER_ID = process.env.PUBLISHER_ID!;

const ONENET_PRIVATE_KEY = process.env.ONENET_PRIVATE_KEY!;
const CUSTODIAL_WALLET_PRIVATE_KEY = process.env.CUSTODIAL_WALLET_PRIVATE_KEY!;
const NON_CUSTODIAL_WALLET_PRIVATE_KEY = process.env.NON_CUSTODIAL_WALLET_PRIVATE_KEY!;



/// helper to make keypair from private key that is in string format
function getKeyPair(privateKey: string): Ed25519Keypair{
  let privateKeyArray = Array.from(fromB64(privateKey));
  privateKeyArray.shift();
  return Ed25519Keypair.fromSecretKey(Uint8Array.from(privateKeyArray));
}

// make the keypairs
const onenetKeyPair = getKeyPair(ONENET_PRIVATE_KEY);
const custodialWalletKeyPair = getKeyPair(CUSTODIAL_WALLET_PRIVATE_KEY);
const nonCustodialWalletKeyPair = getKeyPair(NON_CUSTODIAL_WALLET_PRIVATE_KEY);

// addresses
const onenetAddress = onenetKeyPair.getPublicKey().toSuiAddress();
const custodialWalletAddress = custodialWalletKeyPair.getPublicKey().toSuiAddress();
const nonCustodialWalletAddress = nonCustodialWalletKeyPair.getPublicKey().toSuiAddress();

// initialize a provider for testnet
const provider = new JsonRpcProvider(testnetConnection);
// make a signers
const onenet = new RawSigner(onenetKeyPair, provider);
const custodialWallet = new RawSigner(custodialWalletKeyPair, provider);
const nonCustodialWallet = new RawSigner(nonCustodialWalletKeyPair, provider);

// ------------------ prepare ------------------

// user creates a kiosk
async function userCreateKiosk() {

  let txb = new TransactionBlock();

  txb.moveCall(
    {
      target: `${OB_KIOSK_PACKAGE_ID}::ob_kiosk::create_for_sender`,
    }
  )

  // sign and execute
  // arbitrary value for gas budget
  txb.setGasBudget(100000000);
  // sign and execute the transaction
  let result = await nonCustodialWallet.signAndExecuteTransactionBlock({
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

  // in this function Onenet mints an NFT and deposits it to the kiosk
  // in reality the user would buy it from the marketplace
  async function mintNFTandDepositToKiosk(kioskID: string) {

    let txb = new TransactionBlock();

    // call the mint_default to mint a battle pass
    // this is missing the "rarity" argument because I am using the version of the contracts without the rarity field
    let battlePass = txb.moveCall(
      {
        target: `${PACKAGE_ID}::battle_pass::mint_default`,
        arguments: [
          txb.object(MINT_CAP_ID), 
          txb.pure("Play Bushi to earn in-game assets using this battle pass", "string"),
          txb.pure("https://dummy.com", "string"),
          txb.pure("70", "u64"),
          txb.pure("1000", "u64"),
          txb.pure("1", "u64"),
        ]
      })

    // deposit the battle pass to the user's kiosk
    txb.moveCall(
      {
        target: `${OB_KIOSK_PACKAGE_ID}::ob_kiosk::deposit`,
        arguments: [
          txb.object(kioskID),
          battlePass
        ]
      })

    // sign and execute
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

  // ------------------ import to kiosk ------------------

  // Onenet creates a transfer token to withdraw the NFT from the kiosk of the player
  async function createTransferToken() {

    let txb = new TransactionBlock();

    // create a delegated witness from publisher
    let delegatedWitness = txb.moveCall(
      {
        target: `${OB_PERMISSIONS_PACKAGE_ID}::witness::from_publisher`,
        arguments: [
          txb.object(PUBLISHER_ID),
        ],
        typeArguments: [`${PACKAGE_ID}::battle_pass::BattlePass`]
      })

      txb.moveCall(
        {
          target: `${NFT_PROTOCOL_PACKAGE_ID}::transfer_token::create_and_transfer`,
          arguments: [
            delegatedWitness,
            txb.pure(custodialWalletAddress, "address"),
            txb.pure(nonCustodialWalletAddress, "address"),
          ],
          typeArguments: [`${PACKAGE_ID}::battle_pass::BattlePass`]
        });

    // sign and execute
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




  async function main(){
    let result1 = await userCreateKiosk();
    console.log(result1);

    let [kioskResult]: any = result1.objectChanges?.filter(
      (objectChange) =>
        objectChange.type === "created" &&
        objectChange.objectType == `${SUI_FRAMEWORK_ADDRESS}::kiosk::Kiosk`
    )

    let kioskId = kioskResult.objectId;

    let result2 = await mintNFTandDepositToKiosk(kioskId);
    console.log(result2);
    let result3 = await createTransferToken()
    console.log(result3);




  }

main();
