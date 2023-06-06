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