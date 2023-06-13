#[test_only]
module bushi::cosmetic_skin_test {
  use std::string::{utf8, String};
  use std::vector;

  use sui::coin;
  use sui::object::{Self, ID};
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;
  use sui::transfer_policy::TransferPolicy;
  use sui::sui::SUI;
  use sui::package::Publisher;
  use sui::kiosk::{Self, Kiosk};

  use nft_protocol::mint_cap::MintCap;
  use nft_protocol::royalty_strategy_bps::{Self, BpsRoyaltyStrategy};
  use nft_protocol::transfer_allowlist;
  use nft_protocol::transfer_token::{Self, TransferToken};

  use liquidity_layer_v1::orderbook::{Self, Orderbook};

  use ob_allowlist::allowlist::{Self , Allowlist};

  use ob_launchpad::listing::{Self, Listing};
  use ob_launchpad::fixed_price;

  use ob_kiosk::ob_kiosk;

  use ob_utils::dynamic_vector;

  use ob_permissions::witness;

  use ob_request::withdraw_request::{Self, WITHDRAW_REQ};
  use ob_request::request::{Policy, WithNft};
  use ob_request::transfer_request;

  use ob_launchpad::warehouse::{Self, Warehouse};

  use bushi::cosmetic_skin::{Self, CosmeticSkin, UnlockUpdatesTicket, EWrongToken, ECannotUpdate, ELevelGreaterThanLevelCap};

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
  const USER_1_NON_CUSTODIAL: address = @0x6;
  const USER_2_NON_CUSTODIAL: address = @0x7;

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
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    ensure_cosmetic_skin_fields_are_correct(&cosmetic_skin, utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, false);

    // transfer cosmetic skin to user
    transfer::public_transfer(cosmetic_skin, USER);
    // end test
    test_scenario::end(scenario_val);
  }

  #[test]
  #[expected_failure(abort_code = ELevelGreaterThanLevelCap)]
  fun test_mint_with_level_greater_than_level_cap(){

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin with level > level_cap and try to transfer it to user
    test_scenario::next_tx(scenario, ADMIN);
    // in this test level = 4 and level_cap = 3
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 4, 3, scenario);
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
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep id of cosmetic skin for unlock updates ticket later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    // admin transfers cosmetic skin to user
    // assume user here is a custodial wallet
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by admin to create an unlock updates ticket for the cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let unlock_updates_ticket = create_unlock_updates_ticket(cosmetic_skin_id, scenario);
    // admin transfers unlock updates ticket to user
    transfer::public_transfer(unlock_updates_ticket, USER);

    // next transaction by user's custodial wallet to unlock updates for their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user's custodial wallet to
    // 1. make sure that the unlock updates ticket is burned
    // 2. update their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    assert!(!test_scenario::has_most_recent_for_address<UnlockUpdatesTicket>(USER), EObjectShouldHaveNotBeenFound);
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
    let cosmetic_skin_1 = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep the id of the cosmetic skin 1 for later
    let cosmetic_skin_1_id = cosmetic_skin::id(&cosmetic_skin_1);
    transfer::public_transfer(cosmetic_skin_1, USER_1);

    // next transaction by admin to mint a cosmetic skin and send it to user2
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin_2 = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    transfer::public_transfer(cosmetic_skin_2, USER_2);

    // next transaction by admin to create an unlock updates ticket for the cosmetic skin of user1
    test_scenario::next_tx(scenario, ADMIN);
    let unlock_updates_ticket = create_unlock_updates_ticket(cosmetic_skin_1_id, scenario);
    // admin transfers unlock updates ticket to user1
    transfer::public_transfer(unlock_updates_ticket, USER_1);

    // next transaction by user1 that sends their unlock updates ticket to user2
    test_scenario::next_tx(scenario, USER_1);
    let unlock_updates_ticket = test_scenario::take_from_address<UnlockUpdatesTicket>(scenario, USER_1);
    transfer::public_transfer(unlock_updates_ticket, USER_2);

    // next transaction by user2 to try and unlock their cosmetic skin with the unlock ticket of user1
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
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by user that tries to update their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    update(USER, 2, scenario);

    // end test
    test_scenario::end(scenario_val);

  }

  #[test]
  #[expected_failure(abort_code = ELevelGreaterThanLevelCap)]
  fun test_update_when_reached_level_cap() {

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin and send it to user
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep the id of the cosmetic skin to create update ticket later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by admin to issue an unlock updates ticket for the cosmetic skin of user
    test_scenario::next_tx(scenario, ADMIN);
    let unlock_updates_ticket = create_unlock_updates_ticket(cosmetic_skin_id, scenario);
    // admin transfers unlock updates ticket to user
    transfer::public_transfer(unlock_updates_ticket, USER);

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
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep id of cosmetic skin for unlock updates ticket later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    // admin transfers cosmetic skin to user
    // assume user here is a custodial wallet
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by admin to create an unlock updates ticket for the cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let unlock_updates_ticket = create_unlock_updates_ticket(cosmetic_skin_id, scenario);
    // admin transfers unlock updates ticket to user
    transfer::public_transfer(unlock_updates_ticket, USER);

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

    // next transaction by admin to create a Clutchy Warehouse, mint a cosmetic skin and transfer to it

    // 1. Create Clutchy `Warehouse`
    test_scenario::next_tx(scenario, ADMIN);
    let warehouse = warehouse::new<CosmeticSkin>(
        test_scenario::ctx(scenario),
    );

    // 2. Admin pre-mints NFTs to the Warehouse
    mint_to_launchpad(
      utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, &mut warehouse, scenario
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

  #[test]
  fun test_secondary_market_sale(){
    // in this test we skip the launchpad sale and transfer directly from admin to user kiosk after minting
    // the user then sells the cosmetic skin in a secondary market sale

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create an allowlist
    test_scenario::next_tx(scenario, ADMIN);
    // create allowlist
    let (allowlist, allowlist_cap) = allowlist::new(test_scenario::ctx(scenario));
    // orderbooks can perform trades with our allowlist
    allowlist::insert_authority<orderbook::Witness>(&allowlist_cap, &mut allowlist);
    // take publisher and insert collection to allowlist
    let publisher = test_scenario::take_from_address<Publisher>(scenario, ADMIN);
    allowlist::insert_collection<CosmeticSkin>(&mut allowlist, &publisher);
    // return publisher
    test_scenario::return_to_address(ADMIN, publisher);
    // share the allowlist
    transfer::public_share_object(allowlist);
    // send the allowlist cap to admin
    transfer::public_transfer(allowlist_cap, ADMIN);

    // next transaction by user 1 to create an ob_kiosk
    test_scenario::next_tx(scenario, USER_1_NON_CUSTODIAL);
    let (user_1_kiosk, _) = ob_kiosk::new(test_scenario::ctx(scenario));
    transfer::public_share_object(user_1_kiosk);

    // next transaction by admin to mint a cosmetic skin and send it to user kiosk
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep the id for later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    // deposit cosmetic skin to user kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    ob_kiosk::deposit(&mut user_1_kiosk, cosmetic_skin, test_scenario::ctx(scenario));
    test_scenario::return_shared(user_1_kiosk);

    // next transaction by user 1 to put the cosmetic skin for sale in a secondary market sale
    test_scenario::next_tx(scenario, USER_1_NON_CUSTODIAL);
    // user 1 takes the orderbook
    let orderbook = test_scenario::take_shared<Orderbook<CosmeticSkin, SUI>>(scenario);
    // user 1 finds their kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    // user 1 puts the cosmetic skin for sale
    orderbook::create_ask(
      &mut orderbook,
      &mut user_1_kiosk,
      100_000_000,
      cosmetic_skin_id,
      test_scenario::ctx(scenario),
    );
    test_scenario::return_shared(user_1_kiosk);
    test_scenario::return_shared(orderbook);

    // next transaction by user 2 to buy the cosmetic skin from user 1
    test_scenario::next_tx(scenario, USER_2_NON_CUSTODIAL);
    // take sui coins for testing
    let coins = coin::mint_for_testing<SUI>(100_000_000, test_scenario::ctx(scenario));
    // user 2 creates a kiosk
    let (user_2_kiosk, _) = ob_kiosk::new(test_scenario::ctx(scenario));
    // user 2 takes the orderbook and user's 1 kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    let orderbook = test_scenario::take_shared<Orderbook<CosmeticSkin, SUI>>(scenario);
    // user 2 buys the nft from user's 1 kiosk
    let transfer_request = orderbook::buy_nft(
      &mut orderbook,
      &mut user_1_kiosk,
      &mut user_2_kiosk,
      cosmetic_skin_id,
      100_000_000,
      &mut coins,
      test_scenario::ctx(scenario),
    );

    // user 2 goes through trade resolution to pay for royalties
    // user 2 takes the allowlist
    let allowlist = test_scenario::take_shared<Allowlist>(scenario);
    transfer_allowlist::confirm_transfer(&allowlist, &mut transfer_request);
    let royalty_engine = test_scenario::take_shared<BpsRoyaltyStrategy<CosmeticSkin>>(scenario);
    // confirm user 2 has payed royalties
    royalty_strategy_bps::confirm_transfer<CosmeticSkin, SUI>(&mut royalty_engine, &mut transfer_request);
    // confirm transfer
    let transfer_policy = test_scenario::take_shared<TransferPolicy<CosmeticSkin>>(scenario);
    transfer_request::confirm<CosmeticSkin, SUI>(transfer_request, &transfer_policy, test_scenario::ctx(scenario));

    // return objects
    test_scenario::return_shared(allowlist);
    test_scenario::return_shared(royalty_engine);
    test_scenario::return_shared(orderbook);
    test_scenario::return_shared(user_1_kiosk);
    test_scenario::return_shared(transfer_policy);

    // public share user 2 kiosk
    transfer::public_share_object(user_2_kiosk);

    // send coin to user 2 (just to be able to end the test)
    transfer::public_transfer(coins, USER_2_NON_CUSTODIAL);

    // Confirm the transfer of the NFT
    test_scenario::next_tx(scenario, USER_2_NON_CUSTODIAL);
    let user_2_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    ob_kiosk::assert_has_nft(&user_2_kiosk, cosmetic_skin_id);
    test_scenario::return_shared(user_2_kiosk);

    // end test 
    test_scenario::end(scenario_val);

  }



  fun mint(name: String, description:String, image_url: String, level: u64, level_cap: u64, scenario: &mut Scenario): CosmeticSkin{
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let cosmetic_skin = cosmetic_skin::mint(&mint_cap, name, description, image_url, level, level_cap, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    cosmetic_skin
  }
  
  fun mint_to_launchpad(name: String, description:String, image_url: String, level: u64, level_cap: u64, warehouse: &mut Warehouse<CosmeticSkin>, scenario: &mut Scenario) {
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    cosmetic_skin::mint_to_launchpad(&mint_cap, name, description, image_url, level, level_cap, warehouse, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
  }

  fun create_unlock_updates_ticket(cosmetic_skin_id: ID, scenario: &mut Scenario): UnlockUpdatesTicket{
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let unlock_updates_ticket = cosmetic_skin::create_unlock_updates_ticket(&mint_cap, cosmetic_skin_id, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    unlock_updates_ticket
  }

  fun unlock_updates(user: address, scenario: &mut Scenario){
    let unlock_updates_ticket = test_scenario::take_from_address<UnlockUpdatesTicket>(scenario, user);
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    cosmetic_skin::unlock_updates(&mut cosmetic_skin, unlock_updates_ticket);
    test_scenario::return_to_address(user, cosmetic_skin);
  }

  fun update(user: address, new_level: u64, scenario: &mut Scenario){
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    cosmetic_skin::update(&mut cosmetic_skin, new_level);
    test_scenario::return_to_address(user, cosmetic_skin);
  }

  fun ensure_cosmetic_skin_fields_are_correct(cosmetic_skin: &CosmeticSkin, intended_name: String, intended_description: String, intended_img_url: String, intended_level: u64, intended_level_cap: u64, intended_in_game: bool){
    assert!(cosmetic_skin::name(cosmetic_skin) == intended_name, EIncorrectName);
    assert!(cosmetic_skin::description(cosmetic_skin) == intended_description, EIncorrectDescription);
    assert!(cosmetic_skin::image_url(cosmetic_skin) == intended_img_url, EIncorrectUrl);
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