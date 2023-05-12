#[test_only]
module bushi::cosmetic_skin_test {
  use std::string::{utf8, String};
  use std::vector;

  use sui::object::{Self, ID};
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;
  use sui::url::{Self, Url};
  use sui::coin;
  use sui::sui::SUI;
  use sui::package::Publisher;
  use sui::kiosk::{Self, Kiosk};

  use nft_protocol::mint_cap::MintCap;
  use nft_protocol::transfer_token::{Self, TransferToken};
  use ob_launchpad::listing::{Self, Listing};
  use ob_launchpad::fixed_price;
  use ob_kiosk::ob_kiosk;
  use ob_utils::dynamic_vector;
  use ob_permissions::witness;
  use ob_request::withdraw_request::{Self, WITHDRAW_REQ};
  use ob_request::request::{Policy, WithNft};
  use ob_launchpad::warehouse::{Self, Warehouse};

  use bushi::cosmetic_skin::{Self, CosmeticSkin, InGameToken, EWrongToken, ECannotUpdate, ELevelGreaterOrEqualThanLevelCap};

  // error codes
  const EIncorrectName: u64 = 0;
  const EIncorrectDescription: u64 = 1;
  const EIncorrectUrl: u64 = 2;
  const EIncorrectLevel: u64 = 3;
  const EIncorrectLevelCap: u64 = 4;
  const EObjectShouldHaveNotBeenFound: u64 = 5;
  const EIncorrectInGame: u64 = 6;

  // const addresses
  const ADMIN: address = @0x1;
  const USER: address = @0x2;
  const USER_1: address = @0x3;
  const USER_2: address = @0x4;
  const USER_NON_CUSTODIAL: address = @0x5;

  // const values
  const DUMMY_DESCRIPTION_BYTES: vector<u8> = b"This skin will make your character look like a fairy";
  const DUMMY_URL_BYTES: vector<u8> = b"dummy.com";

  #[test]
  fun test_mint(){

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    ensure_cosmetic_skin_fields_are_correct(&cosmetic_skin, utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), url::new_unsafe_from_bytes(DUMMY_URL_BYTES), 1, 3, false);

    // transfer cosmetic skin to user
    transfer::public_transfer(cosmetic_skin, USER);
    // end test
    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_update(){

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    // keep id of cosmetic skin for in-game token later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    // admin transfers cosmetic skin to user
    // assume user here is a custodial wallet
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by admin to create an in-game token for the cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let in_game_token = create_in_game_token(cosmetic_skin_id, scenario);
    // admin transfers in-game token to user
    transfer::public_transfer(in_game_token, USER);

    // next transaction by user's custodial wallet to unlock updates for their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user's custodial wallet to
    // 1. make sure that the in-game token is burned
    // 2. update their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    assert!(!test_scenario::has_most_recent_for_address<InGameToken>(USER), EObjectShouldHaveNotBeenFound);
    update(USER, 2, scenario);

    // next transaction by user to make sure that
    // cosmetic skin is updated properly
    test_scenario::next_tx(scenario, USER);
    ensure_cosmetic_skin_is_updated_properly(USER, 2, scenario);

    // end test
    test_scenario::end(scenario_val);

  }

  #[test]
  #[expected_failure(abort_code = EWrongToken)]
  fun test_unlock_with_wrong_token() {

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin and send it to user1
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin_1 = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    // keep the id of the cosmetic skin 1 for later
    let cosmetic_skin_1_id = cosmetic_skin::id(&cosmetic_skin_1);
    transfer::public_transfer(cosmetic_skin_1, USER_1);

    // next transaction by admin to mint a cosmetic skin and send it to user2
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin_2 = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    transfer::public_transfer(cosmetic_skin_2, USER_2);

    // next transaction by admin to create an in-game token for the cosmetic skin of user1
    test_scenario::next_tx(scenario, ADMIN);
    let in_game_token = create_in_game_token(cosmetic_skin_1_id, scenario);
    // admin transfers in-game token to user1
    transfer::public_transfer(in_game_token, USER_1);

    // next transaction by user1 that sends their in-game token to user2
    test_scenario::next_tx(scenario, USER_1);
    let in_game_token = test_scenario::take_from_address<InGameToken>(scenario, USER_1);
    transfer::public_transfer(in_game_token, USER_2);

    // next transaction by user2 to try and unlock their cosmetic skin with the unlock token of user1
    test_scenario::next_tx(scenario, USER_2);
    unlock_updates(USER_2, scenario);

    // end test
    test_scenario::end(scenario_val);
  }

  #[test]
  #[expected_failure(abort_code = ECannotUpdate)]
  fun test_update_when_locked() {

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin and send it to user
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by user that tries to update their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    update(USER, 2, scenario);

    // end test
    test_scenario::end(scenario_val);

  }

  #[test]
  #[expected_failure(abort_code = ELevelGreaterOrEqualThanLevelCap)]
  fun test_update_when_reached_level_cap() {

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin and send it to user
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    // keep the id of the cosmetic skin to create update token later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by admin to issue an in-game token for the cosmetic skin of user
    test_scenario::next_tx(scenario, ADMIN);
    let in_game_token = create_in_game_token(cosmetic_skin_id, scenario);
    // admin transfers in-game token to user
    transfer::public_transfer(in_game_token, USER);

    // next transaction by user to unlock updates for their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user to update their cosmetic skin with level that is greater than level cap
    test_scenario::next_tx(scenario, USER);
    update(USER, 4, scenario);

    // end test
    test_scenario::end(scenario_val);
    
  }

  #[test]
  #[expected_failure(abort_code = ECannotUpdate)]
  fun test_lock_updates() {

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    // keep id of cosmetic skin for in-game token later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    // admin transfers cosmetic skin to user
    // assume user here is a custodial wallet
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by admin to create an in-game token for the cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let in_game_token = create_in_game_token(cosmetic_skin_id, scenario);
    // admin transfers in-game token to user
    transfer::public_transfer(in_game_token, USER);

    // next transaction by user's custodial wallet to unlock updates for their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user's custodial wallet to lock updates for their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    // lock_updates(USER, scenario);
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, USER);
    cosmetic_skin::lock_updates(&mut cosmetic_skin);
    // transfer cosmetic skin to user's non-custodial
    transfer::public_transfer(cosmetic_skin, USER_NON_CUSTODIAL);

    // next transaction by non-custodial to try and update the cosmetic skin
    test_scenario::next_tx(scenario, USER_NON_CUSTODIAL);
    update(USER_NON_CUSTODIAL, 2, scenario);

    // end test
    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_integration() {
    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // === Clutchy Launchpad Sale ===

    // next transaction by admin to create a Clutchy Warehouse, mint a battle pass and transfer to it

    // 1. Create Clutchy `Warehouse`
    test_scenario::next_tx(scenario, ADMIN);
    let warehouse = warehouse::new<CosmeticSkin>(
        test_scenario::ctx(scenario),
    );

    // 2. Admin pre-mints NFTs to the Warehouse
    mint_to_launchpad(
      utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, &mut warehouse, scenario
    );

    let nft_id = get_nft_id(&warehouse);
    
    // 3. Create `Listing`
    test_scenario::next_tx(scenario, ADMIN);

    listing::init_listing(
        ADMIN, // Admin wallet
        ADMIN, // Receiver of proceeds wallet
        test_scenario::ctx(scenario),
    );

    // 4. Add Clutchy Warehouse to the Listing
    test_scenario::next_tx(scenario, ADMIN);
    let listing = test_scenario::take_shared<Listing>(scenario);

    let inventory_id = listing::insert_warehouse(&mut listing, warehouse, test_scenario::ctx(scenario));

    // 5. Create the launchpad sale
    let venue_id = fixed_price::create_venue<CosmeticSkin, SUI>(
        &mut listing, inventory_id, false, 100, test_scenario::ctx(scenario)
    );
    listing::sale_on(&mut listing, venue_id, test_scenario::ctx(scenario));

    // 6. Buy NFT from Clutchy
    test_scenario::next_tx(scenario, USER_NON_CUSTODIAL);

    let wallet = coin::mint_for_testing<SUI>(100, test_scenario::ctx(scenario));

    let (user_kiosk, _) = ob_kiosk::new(test_scenario::ctx(scenario));

    fixed_price::buy_nft_into_kiosk<CosmeticSkin, SUI>(
        &mut listing,
        venue_id,
        &mut wallet,
        &mut user_kiosk,
        test_scenario::ctx(scenario),
    );

    transfer::public_share_object(user_kiosk);

    // 6. Verify NFT was bought
    test_scenario::next_tx(scenario, USER_NON_CUSTODIAL);

    // Check NFT was transferred with correct logical owner
    let user_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    assert!(
      kiosk::has_item(&user_kiosk, nft_id), 0
    );

    // === Custodial Wallet - Owner Kiosk Interoperability ===

    // 7. Send NFT from Kiosk to custodial walet
    test_scenario::next_tx(scenario, ADMIN);

    // Get publisher as admin
    let pub = test_scenario::take_from_address<Publisher>(scenario, ADMIN);
    let withdraw_policy = test_scenario::take_shared<Policy<WithNft<CosmeticSkin, WITHDRAW_REQ>>>(scenario);
    
    // Create delegated witness from Publisher
    let dw = witness::from_publisher<CosmeticSkin>(&pub);
    transfer_token::create_and_transfer(dw, USER, USER_NON_CUSTODIAL, test_scenario::ctx(scenario));

    test_scenario::next_tx(scenario, USER_NON_CUSTODIAL);
    let transfer_auth = test_scenario::take_from_address<TransferToken<CosmeticSkin>>(scenario, USER_NON_CUSTODIAL);
    
    // Withdraws NFT from the Kiosk with a WithdrawRequest promise that needs to be resolved in the same
    // programmable batch
    let (nft, req) = ob_kiosk::withdraw_nft_signed<CosmeticSkin>(
      &mut user_kiosk, nft_id, test_scenario::ctx(scenario)
    );

    // Transfers NFT to the custodial wallet address
    transfer_token::confirm(nft, transfer_auth, withdraw_request::inner_mut(&mut req));

    // Resolves the WithdrawRequest
    withdraw_request::confirm(req, &withdraw_policy);

    // Assert that the NFT has been transferred successfully to the custodial wallet address
    test_scenario::next_tx(scenario, USER);
    let nft = test_scenario::take_from_address<CosmeticSkin>(scenario, USER);
    assert!(object::id(&nft) == nft_id, 0);

    // Return objects and end test
    transfer::public_transfer(wallet, USER_NON_CUSTODIAL);
    transfer::public_transfer(nft, USER);
    transfer::public_transfer(pub, ADMIN);
    test_scenario::return_shared(listing);
    test_scenario::return_shared(withdraw_policy);
    test_scenario::return_shared(user_kiosk);
    test_scenario::end(scenario_val);
  }



  fun mint(name: String, description:String, img_url_bytes: vector<u8>, level: u64, level_cap: u64, scenario: &mut Scenario): CosmeticSkin{
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let cosmetic_skin = cosmetic_skin::mint(&mint_cap, name, description, img_url_bytes, level, level_cap, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    cosmetic_skin
  }
  
  fun mint_to_launchpad(name: String, description:String, img_url_bytes: vector<u8>, level: u64, level_cap: u64, warehouse: &mut Warehouse<CosmeticSkin>, scenario: &mut Scenario) {
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    cosmetic_skin::mint_to_launchpad(&mint_cap, name, description, img_url_bytes, level, level_cap, warehouse, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
  }

  fun create_in_game_token(cosmetic_skin_id: ID, scenario: &mut Scenario): InGameToken{
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let in_game_token = cosmetic_skin::create_in_game_token(&mint_cap, cosmetic_skin_id, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    in_game_token
  }

  fun unlock_updates(user: address, scenario: &mut Scenario){
    let in_game_token = test_scenario::take_from_address<InGameToken>(scenario, user);
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    cosmetic_skin::unlock_updates(&mut cosmetic_skin, in_game_token);
    test_scenario::return_to_address(user, cosmetic_skin);
  }

  fun update(user: address, new_level: u64, scenario: &mut Scenario){
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    cosmetic_skin::update(&mut cosmetic_skin, new_level);
    test_scenario::return_to_address(user, cosmetic_skin);
  }

  fun ensure_cosmetic_skin_fields_are_correct(cosmetic_skin: &CosmeticSkin, intended_name: String, intended_description: String, intended_img_url: Url, intended_level: u64, intended_level_cap: u64, intended_in_game: bool){
    assert!(cosmetic_skin::name(cosmetic_skin) == intended_name, EIncorrectName);
    assert!(cosmetic_skin::description(cosmetic_skin) == intended_description, EIncorrectDescription);
    assert!(cosmetic_skin::img_url(cosmetic_skin) == intended_img_url, EIncorrectUrl);
    assert!(cosmetic_skin::level(cosmetic_skin) == intended_level, EIncorrectLevel);
    assert!(cosmetic_skin::level_cap(cosmetic_skin) == intended_level_cap, EIncorrectLevelCap);
    assert!(cosmetic_skin::in_game(cosmetic_skin) == intended_in_game, EIncorrectInGame);
  }

  fun ensure_cosmetic_skin_is_updated_properly(user: address, intended_level: u64, scenario: &mut Scenario){
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    assert!(cosmetic_skin::level(&cosmetic_skin) == intended_level, EIncorrectLevel);
    test_scenario::return_to_address(user, cosmetic_skin);
  }

  fun get_nft_id(warehouse: &Warehouse<CosmeticSkin>): ID {
    let chunk = dynamic_vector::borrow_chunk(warehouse::nfts(warehouse), 0);
    *vector::borrow(chunk, 0)
  }

}