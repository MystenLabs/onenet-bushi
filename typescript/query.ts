import { JsonRpcProvider, SUI_FRAMEWORK_ADDRESS, mainnetConnection } from "@mysten/sui.js";

const provider = new JsonRpcProvider(mainnetConnection);

let address = "0x3abe6197fa743a86bfc88d4cdfca7982282b03eed067f7a76c98a08cbd512035";
let OB_KIOSK_OWNER_TOKEN = `0x95a441d389b07437d00dd07e0b6f05f513d7659b13fd7c5d3923c7d9d847199b::ob_kiosk::OwnerToken`

let getKioskTokensofAddressQuery = {
  filter:{ StructType: OB_KIOSK_OWNER_TOKEN },
  owner: address,
  options: { showContent: true, showOwner: true, showType: true },
}

async function getKioskOwnerTokenOfAddress(address: String){
  let result = await provider.getOwnedObjects(getKioskTokensofAddressQuery);
  return result;
}

async function main() {
  let result = await getKioskOwnerTokenOfAddress(address);
  console.log(result.data);
}

main();