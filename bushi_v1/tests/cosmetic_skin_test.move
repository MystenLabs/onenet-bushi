#[test_only]
module bushi::cosmetic_skin_test {
  use std::string::{utf8, String};

  use sui::object::ID;
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;
  use sui::url::{Self, Url};

  use bushi::cosmetic_skin::{Self, CosmeticSkin, AllowUpdatesTicket, EWrongTicket, ECannotUpdate};

  // use nft_protocol::collection::Collection;
  use nft_protocol::mint_cap::MintCap;

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
  const USER1: address = @0x3;
  const USER2: address = @0x4;

  // const values
  const DUMMY_DESCRIPTION_BYTES: vector<u8> = b"This skin will make your character look like a fairy";
  const DUMMY_URL_BYTES: vector<u8> = b"dummy.com";

  #[test]
  fun test_mint(){

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::test_init(test_scenario::ctx(scenario));

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
    cosmetic_skin::test_init(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    // keep id of cosmetic skin for allow updates ticket later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    // admin transfers cosmetic skin to user
    // assume user here is a custodial wallet
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by admin to create an allow updates ticket for the cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let allow_updates_ticket = create_allow_updates_ticket(cosmetic_skin_id, scenario);
    // admin transfers allow updates ticket to user
    transfer::public_transfer(allow_updates_ticket, USER);

    // next transaction by user's custodial wallet to unlock updates for their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    unlock_updates(USER, scenario);

    // next transaction by user's custodial wallet to
    // 1. make suretyat the allow updates ticket is burned
    // 2. update their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    assert!(!test_scenario::has_most_recent_for_address<AllowUpdatesTicket>(USER), EObjectShouldHaveNotBeenFound);
    update_level(USER, 2, scenario);

    // next transaction by user to make sure that
    // cosmetic skin is updated properly
    test_scenario::next_tx(scenario, USER);
    ensure_cosmetic_skin_is_updated_properly(USER, 2, scenario);

    // end test
    test_scenario::end(scenario_val);

  }

 #[test]
  #[expected_failure(abort_code = EWrongTicket)]
  fun test_unlock_with_wrong_ticket() {

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::test_init(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin and send it to user1
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin_1 = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    // keep the id of the cosmetic skin 1 for later
    let cosmetic_skin_1_id = cosmetic_skin::id(&cosmetic_skin_1);
    transfer::public_transfer(cosmetic_skin_1, USER1);

    // next transaction by admin to mint a cosmetic skin and send it to user2
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin_2 = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    transfer::public_transfer(cosmetic_skin_2, USER2);

    // next transaction by admin to create an allow updates ticket for the cosmetic skin of user1
    test_scenario::next_tx(scenario, ADMIN);
    let allow_updates_ticket = create_allow_updates_ticket(cosmetic_skin_1_id, scenario);
    // admin transfers allow updates ticket to user1
    transfer::public_transfer(allow_updates_ticket, USER1);

    // next transaction by user1 that sends their allow updates ticket to user2
    test_scenario::next_tx(scenario, USER1);
    let allow_updates_ticket = test_scenario::take_from_address<AllowUpdatesTicket>(scenario, USER1);
    transfer::public_transfer(allow_updates_ticket, USER2);

    // next transaction by user2 to try and unlock their cosmetic skin with the unlock ticket of user1
    test_scenario::next_tx(scenario, USER2);
    unlock_updates(USER2, scenario);

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
    cosmetic_skin::test_init(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin and send it to user
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(DUMMY_DESCRIPTION_BYTES), DUMMY_URL_BYTES, 1, 3, scenario);
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by user that tries to update their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    update_level(USER, 2, scenario);

    // end test
    test_scenario::end(scenario_val);

  }



  fun mint(name: String, description:String, img_url_bytes: vector<u8>, level: u64, level_cap: u64, scenario: &mut Scenario): CosmeticSkin{
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let cosmetic_skin = cosmetic_skin::mint(&mint_cap, name, description, img_url_bytes, level, level_cap, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    cosmetic_skin
  }

  fun create_allow_updates_ticket(cosmetic_skin_id: ID, scenario: &mut Scenario): AllowUpdatesTicket{
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let allow_updates_ticket = cosmetic_skin::create_allow_updates_ticket(&mint_cap, cosmetic_skin_id, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    allow_updates_ticket
  }

  fun unlock_updates(user: address, scenario: &mut Scenario){
    let allow_updates_ticket = test_scenario::take_from_address<AllowUpdatesTicket>(scenario, user);
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    cosmetic_skin::unlock_updates(&mut cosmetic_skin, allow_updates_ticket);
    test_scenario::return_to_address(user, cosmetic_skin);
  }

  fun update_level(user: address, new_level: u64, scenario: &mut Scenario){
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    cosmetic_skin::update_level(&mut cosmetic_skin, new_level);
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

}