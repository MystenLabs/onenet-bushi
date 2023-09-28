#[test_only]
module bushi::item_test {
    use std::debug;
  use std::string::{utf8, String};
  use std::vector;

  use sui::coin;
  use sui::object::{ID};
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;
  use sui::transfer_policy::TransferPolicy;
  use sui::sui::SUI;
  use sui::package::Publisher;
  use sui::kiosk::{Kiosk};

  use nft_protocol::mint_cap::MintCap;
  use nft_protocol::royalty_strategy_bps::{Self, BpsRoyaltyStrategy};
  use nft_protocol::transfer_allowlist;

  use liquidity_layer_v1::orderbook::{Self, Orderbook};

  use ob_allowlist::allowlist::{Self , Allowlist};

  use ob_kiosk::ob_kiosk;

  use ob_utils::dynamic_vector;

  use ob_request::transfer_request;

  use ob_launchpad::warehouse::{Self, Warehouse};

  use bushi::item::{Self, Item, UnlockUpdatesTicket, EWrongToken, ECannotUpdate, ELevelGreaterThanLevelCap};

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
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a item
    test_scenario::next_tx(scenario, ADMIN);
    let item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    ensure_item_fields_are_correct(&item, utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, false);

    // transfer item to user
    transfer::public_transfer(item, USER);
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
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a item with level > level_cap and try to transfer it to user
    test_scenario::next_tx(scenario, ADMIN);
    // in this test level = 4 and level_cap = 3
    let item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 4, 3, scenario);
    transfer::public_transfer(item, USER);

    // end test
    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_update(){

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a item
    test_scenario::next_tx(scenario, ADMIN);
    let item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep id of item for unlock updates ticket later
    let item_id = item::id(&item);
    // admin transfers item to user
    // assume user here is a custodial wallet
    transfer::public_transfer(item, USER);

    // next transaction by admin to create an unlock updates ticket for the item
    test_scenario::next_tx(scenario, ADMIN);
    let unlock_updates_ticket = create_unlock_updates_ticket(item_id, scenario);
    // admin transfers unlock updates ticket to user
    transfer::public_transfer(unlock_updates_ticket, USER);

    // next transaction by user's custodial wallet to unlock updates for their item
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user's custodial wallet to
    // 1. make sure that the unlock updates ticket is burned
    // 2. update their item
    test_scenario::next_tx(scenario, USER);
    assert!(!test_scenario::has_most_recent_for_address<UnlockUpdatesTicket>(USER), EObjectShouldHaveNotBeenFound);
    update(USER, 2, scenario);

    // next transaction by user to make sure that
    // item is updated properly
    test_scenario::next_tx(scenario, USER);
    ensure_item_is_updated_properly(USER, 2, scenario);

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
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a item and send it to user1
    test_scenario::next_tx(scenario, ADMIN);
    let item_1 = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep the id of the item 1 for later
    let item_1_id = item::id(&item_1);
    transfer::public_transfer(item_1, USER_1);

    // next transaction by admin to mint a item and send it to user2
    test_scenario::next_tx(scenario, ADMIN);
    let item_2 = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    transfer::public_transfer(item_2, USER_2);

    // next transaction by admin to create an unlock updates ticket for the item of user1
    test_scenario::next_tx(scenario, ADMIN);
    let unlock_updates_ticket = create_unlock_updates_ticket(item_1_id, scenario);
    // admin transfers unlock updates ticket to user1
    transfer::public_transfer(unlock_updates_ticket, USER_1);

    // next transaction by user1 that sends their unlock updates ticket to user2
    test_scenario::next_tx(scenario, USER_1);
    let unlock_updates_ticket = test_scenario::take_from_address<UnlockUpdatesTicket>(scenario, USER_1);
    transfer::public_transfer(unlock_updates_ticket, USER_2);

    // next transaction by user2 to try and unlock their item with the unlock ticket of user1
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
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a item and send it to user
    test_scenario::next_tx(scenario, ADMIN);
    let item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    transfer::public_transfer(item, USER);

    // next transaction by user that tries to update their item
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
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a item and send it to user
    test_scenario::next_tx(scenario, ADMIN);
    let item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep the id of the item to create update ticket later
    let item_id = item::id(&item);
    transfer::public_transfer(item, USER);

    // next transaction by admin to issue an unlock updates ticket for the item of user
    test_scenario::next_tx(scenario, ADMIN);
    let unlock_updates_ticket = create_unlock_updates_ticket(item_id, scenario);
    // admin transfers unlock updates ticket to user
    transfer::public_transfer(unlock_updates_ticket, USER);

    // next transaction by user to unlock updates for their item
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user to update their item with level that is greater than level cap
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
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a item
    test_scenario::next_tx(scenario, ADMIN);
    let item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep id of item for unlock updates ticket later
    let item_id = item::id(&item);
    // admin transfers item to user
    // assume user here is a custodial wallet
    transfer::public_transfer(item, USER);

    // next transaction by admin to create an unlock updates ticket for the item
    test_scenario::next_tx(scenario, ADMIN);
    let unlock_updates_ticket = create_unlock_updates_ticket(item_id, scenario);
    // admin transfers unlock updates ticket to user
    transfer::public_transfer(unlock_updates_ticket, USER);

    // next transaction by user's custodial wallet to unlock updates for their item
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user's custodial wallet to lock updates for their item
    test_scenario::next_tx(scenario, USER);
    // lock_updates(USER, scenario);
    let item = test_scenario::take_from_address<Item>(scenario, USER);
    item::lock_updates(&mut item);
    // transfer item to user's non-custodial
    transfer::public_transfer(item, USER_NON_CUSTODIAL);

    // next transaction by non-custodial to try and update the item
    test_scenario::next_tx(scenario, USER_NON_CUSTODIAL);
    update(USER_NON_CUSTODIAL, 2, scenario);

    // end test
    test_scenario::end(scenario_val);
  }

    #[test]
  fun test_burn() {
    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a battle pass
    test_scenario::next_tx(scenario, ADMIN);
    let minted_item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    transfer::public_transfer(minted_item, USER);
    test_scenario::next_tx(scenario, ADMIN);

    let item = test_scenario::take_from_address<Item>(scenario, USER);

    item::burn(item);
    test_scenario::next_tx(scenario, USER);

    assert!(!test_scenario::has_most_recent_for_address<Item>(USER), EObjectShouldHaveNotBeenFound);

    // end test
    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_add_or_edit_dfs(){

    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by ADMIN to mint a Cosmetic Skin and transfer it to the user
    test_scenario::next_tx(scenario, ADMIN);
    let item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    transfer::public_transfer(item, USER);

    // next transaction by ADMIN to issue an unlock updates ticket for user
    test_scenario::next_tx(scenario, ADMIN);
    // find ID of item
    let item = test_scenario::take_from_address<Item>(scenario, USER);
    let item_id = item::id(&item);
    test_scenario::return_to_address(USER, item);
    // create and transfer unlock updates ticket
    let unlock_updates_ticket = create_unlock_updates_ticket(item_id, scenario);
    transfer::public_transfer(unlock_updates_ticket, USER);

    // next transaction by user to unlock updates for their item
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user to update their item kills stat
    test_scenario::next_tx(scenario, USER);
    let item = test_scenario::take_from_address<Item>(scenario, USER);
    let stat_names = vector<String>[utf8(b"kills")];
    let stat_values = vector<String>[utf8(b"10")];
    item::update_stats(
      &mut item,
      stat_names,
      stat_values,
    );
    
    test_scenario::next_tx(scenario, USER);

    debug::print(vector::borrow(&item::stat_names(&item), 0));

    assert!(*vector::borrow(&item::stat_names(&item), 0) == utf8(b"kills"), EIncorrectName);
    assert!(*vector::borrow(&item::stat_values(&item), 0) == utf8(b"10"), EIncorrectName);
    
    assert!(item::stat_names(&item) == stat_names, EIncorrectName);
    assert!(item::stat_values(&item) == stat_values, EIncorrectName);

    test_scenario::return_to_address(USER, item);
    test_scenario::end(scenario_val);
  }


  #[test]
  fun test_secondary_market_sale(){
    // in this test we skip the launchpad sale and transfer directly from admin to user kiosk after minting
    // the user then sells the item in a secondary market sale

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    item::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create an allowlist
    test_scenario::next_tx(scenario, ADMIN);
    // create allowlist
    let (allowlist, allowlist_cap) = allowlist::new(test_scenario::ctx(scenario));
    // orderbooks can perform trades with our allowlist
    allowlist::insert_authority<orderbook::Witness>(&allowlist_cap, &mut allowlist);
    // take publisher and insert collection to allowlist
    let publisher = test_scenario::take_from_address<Publisher>(scenario, ADMIN);
    allowlist::insert_collection<Item>(&mut allowlist, &publisher);
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

    // next transaction by admin to mint a item and send it to user kiosk
    test_scenario::next_tx(scenario, ADMIN);
    let item = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), utf8(DUMMY_URL_BYTES), 1, 3, scenario);
    // keep the id for later
    let item_id = item::id(&item);
    // deposit item to user kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    ob_kiosk::deposit(&mut user_1_kiosk, item, test_scenario::ctx(scenario));
    test_scenario::return_shared(user_1_kiosk);

    // next transaction by user 1 to put the item for sale in a secondary market sale
    test_scenario::next_tx(scenario, USER_1_NON_CUSTODIAL);
    // user 1 takes the orderbook
    let orderbook = test_scenario::take_shared<Orderbook<Item, SUI>>(scenario);
    // user 1 finds their kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    // user 1 puts the item for sale
    orderbook::create_ask(
      &mut orderbook,
      &mut user_1_kiosk,
      100_000_000,
      item_id,
      test_scenario::ctx(scenario),
    );
    test_scenario::return_shared(user_1_kiosk);
    test_scenario::return_shared(orderbook);

    // next transaction by user 2 to buy the item from user 1
    test_scenario::next_tx(scenario, USER_2_NON_CUSTODIAL);
    // take sui coins for testing
    let coins = coin::mint_for_testing<SUI>(100_000_000, test_scenario::ctx(scenario));
    // user 2 creates a kiosk
    let (user_2_kiosk, _) = ob_kiosk::new(test_scenario::ctx(scenario));
    // user 2 takes the orderbook and user's 1 kiosk
    let user_1_kiosk = test_scenario::take_shared<Kiosk>(scenario);
    let orderbook = test_scenario::take_shared<Orderbook<Item, SUI>>(scenario);
    // user 2 buys the nft from user's 1 kiosk
    let transfer_request = orderbook::buy_nft(
      &mut orderbook,
      &mut user_1_kiosk,
      &mut user_2_kiosk,
      item_id,
      100_000_000,
      &mut coins,
      test_scenario::ctx(scenario),
    );

    // user 2 goes through trade resolution to pay for royalties
    // user 2 takes the allowlist
    let allowlist = test_scenario::take_shared<Allowlist>(scenario);
    transfer_allowlist::confirm_transfer(&allowlist, &mut transfer_request);
    let royalty_engine = test_scenario::take_shared<BpsRoyaltyStrategy<Item>>(scenario);
    // confirm user 2 has payed royalties
    royalty_strategy_bps::confirm_transfer<Item, SUI>(&mut royalty_engine, &mut transfer_request);
    // confirm transfer
    let transfer_policy = test_scenario::take_shared<TransferPolicy<Item>>(scenario);
    transfer_request::confirm<Item, SUI>(transfer_request, &transfer_policy, test_scenario::ctx(scenario));

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
    ob_kiosk::assert_has_nft(&user_2_kiosk, item_id);
    test_scenario::return_shared(user_2_kiosk);

    // end test 
    test_scenario::end(scenario_val);

  }

  fun mint(name: String, description:String, image_url: String, level: u64, level_cap: u64, scenario: &mut Scenario): Item{
    let mint_cap = test_scenario::take_from_address<MintCap<Item>>(scenario, ADMIN);
    let item = item::mint(&mint_cap, name, description, image_url, level, level_cap, utf8(b"id"), vector<String>[], vector<String>[], false, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    item
  }
  
  public fun create_unlock_updates_ticket(item_id: ID, scenario: &mut Scenario): UnlockUpdatesTicket{
    let mint_cap = test_scenario::take_from_address<MintCap<Item>>(scenario, ADMIN);
    let unlock_updates_ticket = item::create_unlock_updates_ticket(&mint_cap, item_id, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    unlock_updates_ticket
  }

  public fun unlock_updates(user: address, scenario: &mut Scenario){
    let unlock_updates_ticket = test_scenario::take_from_address<UnlockUpdatesTicket>(scenario, user);
    let item = test_scenario::take_from_address<Item>(scenario, user);
    item::unlock_updates(&mut item, unlock_updates_ticket);
    test_scenario::return_to_address(user, item);
  }

  fun update(user: address, new_level: u64, scenario: &mut Scenario){
    let item = test_scenario::take_from_address<Item>(scenario, user);
    item::update(&mut item, new_level);
    test_scenario::return_to_address(user, item);
  }

  fun ensure_item_fields_are_correct(item: &Item, intended_name: String, intended_description: String, intended_img_url: String, intended_level: u64, intended_level_cap: u64, intended_in_game: bool){
    assert!(item::name(item) == intended_name, EIncorrectName);
    assert!(item::description(item) == intended_description, EIncorrectDescription);
    assert!(item::image_url(item) == intended_img_url, EIncorrectUrl);
    assert!(item::level(item) == intended_level, EIncorrectLevel);
    assert!(item::level_cap(item) == intended_level_cap, EIncorrectLevelCap);
    assert!(item::in_game(item) == intended_in_game, EIncorrectInGame);
  }

  fun ensure_item_is_updated_properly(user: address, intended_level: u64, scenario: &mut Scenario){
    let item = test_scenario::take_from_address<Item>(scenario, user);
    assert!(item::level(&item) == intended_level, EIncorrectLevel);
    test_scenario::return_to_address(user, item);
  }

  fun get_nft_id(warehouse: &Warehouse<Item>): ID {
    let chunk = dynamic_vector::borrow_chunk(warehouse::nfts(warehouse), 0);
    *vector::borrow(chunk, 0)
  }

}