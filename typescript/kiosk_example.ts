import {Ed25519Keypair, JsonRpcProvider, RawSigner, SUI_FRAMEWORK_ADDRESS, 
        TransactionBlock, fromB64, testnetConnection} from "@mysten/sui.js"
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