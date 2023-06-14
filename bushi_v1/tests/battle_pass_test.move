#[test_only]
module bushi::battle_pass_test{
  use std::string::{String, utf8};
  use std::vector;

  use sui::coin;
  use sui::object::{Self, ID};
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer_policy::TransferPolicy;
  use sui::transfer;
  use sui::sui::SUI;
  use sui::package::Publisher;
  use sui::kiosk::{Self, Kiosk};
  
  use nft_protocol::mint_cap::MintCap;
  use nft_protocol::transfer_allowlist;
  use nft_protocol::transfer_token::{Self, TransferToken};
  use nft_protocol::royalty_strategy_bps::{Self, BpsRoyaltyStrategy};

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

  use bushi::battle_pass::{BattlePass, Self, UnlockUpdatesTicket, ELevelGreaterThanLevelCap, ECannotUpdate, EWrongToken};

  // errors
  const EIncorrectDescription: u64 = 0;
  const EIncorrectUrl: u64 = 1;
  const EIncorrectLevel: u64 = 2;
  const EIncorrectLevelCap: u64 = 3;
  const EIncorrectXP: u64 = 4;
  const EIncorrectXPToNextLevel: u64 = 5;
  const EIncorrectRarity: u64 = 6;
  const EIncorrectSeason: u64 = 7;
  const EObjectShouldHaveNotBeenFound: u64 = 8;

  // const addresses
  const ADMIN: address = @0x1;
  const USER: address = @0x2;
  const USER_1: address = @0x3;
  const USER_2: address = @0x4;
  const USER_NON_CUSTODIAL: address = @0x5;
  const USER_1_NON_CUSTODIAL: address = @0x6;
  const USER_2_NON_CUSTODIAL: address = @0x7;

  // const values
  const SAMPLE_DESCRIPTION_BYTES: vector<u8> = b"Play Bushi to earn in-game assets using this battle pass";
  const DUMMY_URL_BYTES: vector<u8> = b"dummy.com";

  #[test]
  fun test_mint_default(){

    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass and transfer it to user
    test_scenario::next_tx(scenario, ADMIN);
    // admin mints a battle pass with level = 1, xp = 0
    let battle_pass = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 70, 1000, 2, 1, scenario);
    transfer::public_transfer(battle_pass, USER);

    // next transaction by user to ensure battle pass fields are correct
    test_scenario::next_tx(scenario, USER);
    // make sure that:
    // 1. description is "Play Bushi to earn in-game assets using this battle pass"
    // 2. img_url is "dummy.com"
    // 3. level = 1
    // 4. level_cap = 70
    // 5. xp = 0
    // 6. xp_to_next_level = 1000
    // 7. rarity = 2
    // 8. season = 1
    ensure_correct_battle_pass_fields(USER, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 70, 0, 1000, 2, 1, scenario);

    test_scenario::end(scenario_val);

  }

  #[test]
  fun test_mint() {

    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass and transfer it to user
    test_scenario::next_tx(scenario, ADMIN);
    // admin mints a battle pass with level = 2, level_cap = 150, xp = 500, xp_to_next_level = 2000
    let battle_pass = mint(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 2, 150, 500, 2000, 3, 2, scenario);
    transfer::public_transfer(battle_pass, USER);

    // next transaction by user to ensure battle pass fields are correct
    test_scenario::next_tx(scenario, USER);
    // make sure that:
    // 1. description is "Play Bushi to earn in-game assets using this battle pass"
    // 2. img_url is "dummy.com"
    // 3. level = 2
    // 4. level_cap = 150
    // 5. xp = 500
    // 6. xp_to_next_level = 2000
    // 7. rarity = 3
    // 8. season = 2
    ensure_correct_battle_pass_fields(USER, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 2, 150, 500, 2000, 3, 2, scenario);

    test_scenario::end(scenario_val);
  }

  #[test]
  #[expected_failure(abort_code = ELevelGreaterThanLevelCap)]
  fun test_mint_with_level_greater_than_level_cap(){

    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass with level > level_cap and try to transfer it to user
    test_scenario::next_tx(scenario, ADMIN);
    // in the following mint, level = 2, level_cap = 1
    let battle_pass = mint(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 2, 1, 500, 2000, 3, 2, scenario);
    transfer::public_transfer(battle_pass, USER);

    test_scenario::end(scenario_val);

  }

  #[test]
  #[expected_failure(abort_code = ELevelGreaterThanLevelCap)]
  fun test_mint_default_with_level_greater_than_level_cap(){

    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass with level_cap = 0 and try to transfer it to user
    // this is the only case where level > level_cap is allowed
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 0, 1000, 2, 1, scenario);
    transfer::public_transfer(battle_pass, USER);

    test_scenario::end(scenario_val);

  }

  #[test]
  fun test_update(){

    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass and transfer it to user
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 70, 1000, 2, 1, scenario);
    // keep the id of the battle pass to create update ticket later
    let battle_pass_id = battle_pass::id(&battle_pass);
    transfer::public_transfer(battle_pass, USER);

    // next transaction by admin to issue an unlock updates ticket for the battle pass of user
    test_scenario::next_tx(scenario, ADMIN);
    let in_game_token = create_unlock_updates_ticket(battle_pass_id, scenario);
    transfer::public_transfer(in_game_token, USER);

    // next transaction by user to unlock updates for their battle pass
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);
    

    // next transaction by user to update their battle pass
    test_scenario::next_tx(scenario, USER);
    // make sure first that the unlock updates ticket is burned
    assert!(!test_scenario::has_most_recent_for_address<UnlockUpdatesTicket>(USER), EObjectShouldHaveNotBeenFound);
    // new_level = 1, new_xp = 400, new_xp_to_next_level: 600
    update_battle_pass(USER, 1, 400, 600, scenario);

    // next transaction by user to ensure battle pass fields are updated properly
    test_scenario::next_tx(scenario, USER);
    ensure_battle_pass_updated_properly(1, 400, 600, USER, scenario);

    test_scenario::end(scenario_val);
  }

  #[test]
  #[expected_failure(abort_code = EWrongToken)]
  fun test_unlock_with_wrong_token() {

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a battle pass and send it to user1
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass_1 = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 70, 1000, 2, 1, scenario);
    // keep the id of the battle pass 1 for later
    let battle_pass_1_id = battle_pass::id(&battle_pass_1);
    transfer::public_transfer(battle_pass_1, USER_1);

    // next transaction by admin to mint a battle pass and send it to user2
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass_2 = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 70, 1000, 2, 1, scenario);
    transfer::public_transfer(battle_pass_2, USER_2);

    // next transaction by admin to create an unlock updates ticket for the battle pass of user1
    test_scenario::next_tx(scenario, ADMIN);
    let in_game_token = create_unlock_updates_ticket(battle_pass_1_id, scenario);
    // admin transfers unlock updates ticket to user1
    transfer::public_transfer(in_game_token, USER_1);

    // next transaction by user1 that sends their unlock updates ticket to user2
    test_scenario::next_tx(scenario, USER_1);
    let in_game_token = test_scenario::take_from_address<UnlockUpdatesTicket>(scenario, USER_1);
    transfer::public_transfer(in_game_token, USER_2);

    // next transaction by user2 to try and unlock their battle pass with the unlock ticket of user1
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
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a battle pass and send it to user
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 70, 1000, 2, 1, scenario);
    transfer::public_transfer(battle_pass, USER);

    // next transaction by user that tries to update their battle pass
    test_scenario::next_tx(scenario, USER);
    update_battle_pass(USER, 1, 400, 600, scenario);

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
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a battle pass and send it to user
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 70, 1000, 2, 1, scenario);
    // keep the id of the battle pass to create update ticket later
    let battle_pass_id = battle_pass::id(&battle_pass);
    transfer::public_transfer(battle_pass, USER);

    // next transaction by admin to issue an unlock updates ticket for the battle pass of user
    test_scenario::next_tx(scenario, ADMIN);
    let in_game_token = create_unlock_updates_ticket(battle_pass_id, scenario);
    // admin transfers unlock updates ticket to user
    transfer::public_transfer(in_game_token, USER);

    // next transaction by user to unlock updates for their battle pass
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user to update their battle pass with level that is greater than level cap
    test_scenario::next_tx(scenario, USER);
    update_battle_pass(USER, 71, 0, 1000, scenario);

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
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a battle pass
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 70, 1000, 1, 1, scenario);
    // keep id of battle pass for unlock updates ticket later
    let battle_pass_id = battle_pass::id(&battle_pass);
    // admin transfers battle pass to user
    // assume user here is a custodial wallet
    transfer::public_transfer(battle_pass, USER);

    // next transaction by admin to create an unlock updates ticket for the battle pass
    test_scenario::next_tx(scenario, ADMIN);
    let in_game_token = create_unlock_updates_ticket(battle_pass_id, scenario);
    // admin transfers unlock updates ticket to user
    transfer::public_transfer(in_game_token, USER);

    // next transaction by user's custodial wallet to unlock updates for their battle pass
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user's custodial wallet to lock updates for their battle pass
    test_scenario::next_tx(scenario, USER);
    // lock_updates(USER, scenario);
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, USER);
    battle_pass::lock_updates(&mut battle_pass);
    // transfer battle pass to user's non-custodial
    transfer::public_transfer(battle_pass, USER_NON_CUSTODIAL);

    // next transaction by non-custodial to try and update the battle pass
    test_scenario::next_tx(scenario, USER_NON_CUSTODIAL);
    update_battle_pass(USER_NON_CUSTODIAL, 71, 0, 1000, scenario);

    // end test
    test_scenario::end(scenario_val);
  }
  
  #[test]
  fun test_integration() {
    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // === Clutchy Launchpad Sale ===

    // next transaction by admin to create a Clutchy Warehouse, mint a battle pass and transfer to it

    // 1. Create Clutchy `Warehouse`
    test_scenario::next_tx(scenario, ADMIN);
    let warehouse = warehouse::new<BattlePass>(
        test_scenario::ctx(scenario),
    );

    // 2. Admin pre-mints NFTs to the Warehouse
    mint_to_launchpad(
      ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 2, 150, 500, 2000, 1, 2, &mut warehouse, scenario
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
    let venue_id = fixed_price::create_venue<BattlePass, SUI>(
        &mut listing, inventory_id, false, 100, test_scenario::ctx(scenario)
    );
    listing::sale_on(&mut listing, venue_id, test_scenario::ctx(scenario));

    // 6. Buy NFT from Clutchy
    test_scenario::next_tx(scenario, USER_NON_CUSTODIAL);

    let wallet = coin::mint_for_testing<SUI>(100, test_scenario::ctx(scenario));

    let (user_kiosk, _) = ob_kiosk::new(test_scenario::ctx(scenario));

    fixed_price::buy_nft_into_kiosk<BattlePass, SUI>(
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
    let withdraw_policy = test_scenario::take_shared<Policy<WithNft<BattlePass, WITHDRAW_REQ>>>(scenario);
    
    // Create delegated witness from Publisher
    let dw = witness::from_publisher<BattlePass>(&pub);
    transfer_token::create_and_transfer(dw, USER, USER_NON_CUSTODIAL, test_scenario::ctx(scenario));

    test_scenario::next_tx(scenario, USER_NON_CUSTODIAL);
    let transfer_auth = test_scenario::take_from_address<TransferToken<BattlePass>>(scenario, USER_NON_CUSTODIAL);
    
    // Withdraws NFT from the Kiosk with a WithdrawRequest promise that needs to be resolved in the same
    // programmable batch
    let (nft, req) = ob_kiosk::withdraw_nft_signed<BattlePass>(
      &mut user_kiosk, nft_id, test_scenario::ctx(scenario)
    );

    // Transfers NFT to the custodial wallet address
    transfer_token::confirm(nft, transfer_auth, withdraw_request::inner_mut(&mut req));

    // Resolves the WithdrawRequest
    withdraw_request::confirm(req, &withdraw_policy);

    // Assert that the NFT has been transferred successfully to the custodial wallet address
    test_scenario::next_tx(scenario, USER);
    let nft = test_scenario::take_from_address<BattlePass>(scenario, USER);
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
    // the user then sells the battle pass in a secondary market sale

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create an allowlist
    test_scenario::next_tx(scenario, ADMIN);
    // create allowlist
    let (allowlist, allowlist_cap) = allowlist::new(test_scenario::ctx(scenario));
    // orderbooks can perform trades with our allowlist
    allowlist::insert_authority<orderbook::Witness>(&allowlist_cap, &mut allowlist);
    // take publisher and insert collection to allowlist
    let publisher = test_scenario::take_from_address<Publisher>(scenario, ADMIN);
    allowlist::insert_collection<BattlePass>(&mut allowlist, &publisher);
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

    // next transaction by admin to mint a battle pass and send it to user kiosk
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass = mint_default(ADMIN, utf8(SAMPLE_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 70, 1000, 5, 1, scenario);
    // keep the id for later
    let battle_pass_id = battle_pass::id(&battle_pass);
    // deposit battle pass to user kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    ob_kiosk::deposit(&mut user_1_kiosk, battle_pass, test_scenario::ctx(scenario));
    test_scenario::return_shared(user_1_kiosk);

    // next transaction by user 1 to put the battle pass for sale in a secondary market sale
    test_scenario::next_tx(scenario, USER_1_NON_CUSTODIAL);
    // user 1 takes the orderbook
    let orderbook = test_scenario::take_shared<Orderbook<BattlePass, SUI>>(scenario);
    // user 1 finds their kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    // user 1 puts the battle pass for sale
    orderbook::create_ask(
      &mut orderbook,
      &mut user_1_kiosk,
      100_000_000,
      battle_pass_id,
      test_scenario::ctx(scenario),
    );
    test_scenario::return_shared(user_1_kiosk);
    test_scenario::return_shared(orderbook);

    // next transaction by user 2 to buy the battle pass from user 1
    test_scenario::next_tx(scenario, USER_2_NON_CUSTODIAL);
    // take sui coins for testing
    let coins = coin::mint_for_testing<SUI>(100_000_000, test_scenario::ctx(scenario));
    // user 2 creates a kiosk
    let (user_2_kiosk, _) = ob_kiosk::new(test_scenario::ctx(scenario));
    // user 2 takes the orderbook and user's 1 kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    let orderbook = test_scenario::take_shared<Orderbook<BattlePass, SUI>>(scenario);
    // user 2 buys the nft from user's 1 kiosk
    let transfer_request = orderbook::buy_nft(
      &mut orderbook,
      &mut user_1_kiosk,
      &mut user_2_kiosk,
      battle_pass_id,
      100_000_000,
      &mut coins,
      test_scenario::ctx(scenario),
    );

    // user 2 goes through trade resolution to pay for royalties
    // user 2 takes the allowlist
    let allowlist = test_scenario::take_shared<Allowlist>(scenario);
    transfer_allowlist::confirm_transfer(&allowlist, &mut transfer_request);
    let royalty_engine = test_scenario::take_shared<BpsRoyaltyStrategy<BattlePass>>(scenario);
    // confirm user 2 has payed royalties
    royalty_strategy_bps::confirm_transfer<BattlePass, SUI>(&mut royalty_engine, &mut transfer_request);
    // confirm transfer
    let transfer_policy = test_scenario::take_shared<TransferPolicy<BattlePass>>(scenario);
    transfer_request::confirm<BattlePass, SUI>(transfer_request, &transfer_policy, test_scenario::ctx(scenario));

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
    ob_kiosk::assert_has_nft(&user_2_kiosk, battle_pass_id);
    test_scenario::return_shared(user_2_kiosk);

    // end test 
    test_scenario::end(scenario_val);

  }

  // === helpers ===

  // mint a battle pass with level = 1, xp = 0 (default)
  fun mint_default(admin: address, description: String, image_url: String, level_cap: u64, xp_to_next_level: u64, rarity: u64, season: u64, scenario: &mut Scenario): BattlePass{
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    let battle_pass = battle_pass::mint_default(&mint_cap, description, image_url, level_cap, xp_to_next_level, rarity, season, false, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
    battle_pass
  }

  fun mint(admin: address, description: String, image_url: String, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, rarity: u64, season: u64, scenario: &mut Scenario): BattlePass{
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    let battle_pass = battle_pass::mint(&mint_cap, description, image_url, level, level_cap, xp, xp_to_next_level, rarity, season, false, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
    battle_pass
  }

  fun mint_to_launchpad(admin: address, description: String, image_url: String, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, rarity: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, scenario: &mut Scenario) {
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    battle_pass::mint_to_launchpad(&mint_cap, description, image_url, level, level_cap, xp, xp_to_next_level, rarity, season, warehouse, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
  }

  // ensure battle pass fields are correct
  fun ensure_correct_battle_pass_fields(user: address, intended_description: String, intended_url: String, intended_level: u64, intended_level_cap: u64, intended_xp: u64, intended_xp_to_next_level: u64, rarity: u64, season: u64, scenario: &mut Scenario){
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
    assert!(battle_pass::description(&battle_pass) == intended_description, EIncorrectDescription);
    assert!(battle_pass::image_url(&battle_pass) == intended_url, EIncorrectUrl);
    assert!(battle_pass::level(&battle_pass) == intended_level, EIncorrectLevel);
    assert!(battle_pass::level_cap(&battle_pass) == intended_level_cap, EIncorrectLevelCap);
    assert!(battle_pass::xp(&battle_pass) == intended_xp, EIncorrectXP);
    assert!(battle_pass::xp_to_next_level(&battle_pass) == intended_xp_to_next_level, EIncorrectXPToNextLevel);
    assert!(battle_pass::rarity(&battle_pass) == rarity, EIncorrectRarity);
    assert!(battle_pass::season(&battle_pass) == season, EIncorrectSeason);
    test_scenario::return_to_address(user, battle_pass);
  }

  fun create_unlock_updates_ticket(battle_pass_id: ID, scenario: &mut Scenario): UnlockUpdatesTicket{
  let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, ADMIN);
  let in_game_token = battle_pass::create_unlock_updates_ticket(&mint_cap, battle_pass_id, test_scenario::ctx(scenario));
  test_scenario::return_to_address(ADMIN, mint_cap);
  in_game_token
  }

  fun unlock_updates(user: address, scenario: &mut Scenario){
  let in_game_token = test_scenario::take_from_address<UnlockUpdatesTicket>(scenario, user);
  let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
  battle_pass::unlock_updates(&mut battle_pass, in_game_token);
  test_scenario::return_to_address(user, battle_pass);
  }

  /// update the last battle pass user has received
  fun update_battle_pass(user: address, new_level: u64, new_xp: u64, new_xp_to_next_level: u64, scenario: &mut Scenario){
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
    battle_pass::update(&mut battle_pass, new_level, new_xp, new_xp_to_next_level);
    test_scenario::return_to_address(user, battle_pass);
  }

  fun get_nft_id(warehouse: &Warehouse<BattlePass>): ID {
    let chunk = dynamic_vector::borrow_chunk(warehouse::nfts(warehouse), 0);
    *vector::borrow(chunk, 0)
  }

  /// ensures battle pass level and xp is as intended, aborts otherwise
  fun ensure_battle_pass_updated_properly(intended_level: u64, intended_xp: u64, intended_xp_to_next_level: u64, user: address, scenario: &mut Scenario){
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
    assert!(battle_pass::level(&battle_pass) == intended_level, EIncorrectLevel);
    assert!(battle_pass::xp_to_next_level(&battle_pass) == intended_xp_to_next_level, EIncorrectXPToNextLevel);
    assert!(battle_pass::xp(&battle_pass) == intended_xp, EIncorrectXP);
    test_scenario::return_to_address(user, battle_pass);
  }
  
}