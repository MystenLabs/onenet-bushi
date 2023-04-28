#[test_only]
module bushi::cosmetic_skins_test {
  use std::string::{utf8, String};

  use sui::object::ID;
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;
  use sui::url::{Self, Url};

  use bushi::cosmetic_skin::{Self, CosmeticSkin, UpdateTicket};

  // use nft_protocol::collection::Collection;
  use nft_protocol::mint_cap::MintCap;

  // error codes
  const EIncorrectName: u64 = 0;
  const EIncorrectDescription: u64 = 1;
  const EIncorrectUrl: u64 = 2;
  const EIncorrectLevel: u64 = 3;
  const EIncorrectLevelCap: u64 = 4;
  const EObjectShouldHaveNotBeenFound: u64 = 5;

  // const addresses
  const ADMIN: address = @0x1;
  const USER: address = @0x2;

  #[test]
  fun test_mint(){

    // test is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    // init module
    cosmetic_skin::test_init(test_scenario::ctx(scenario));

    // next transaction by admin to mint a cosmetic skin
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(b"This skin will make your character look like a fairy"), b"dummy.com", 1, 3, scenario);
    ensure_cosmetic_skin_fields_are_correct(&cosmetic_skin, utf8(b"Fairy"), utf8(b"This skin will make your character look like a fairy"), url::new_unsafe_from_bytes(b"dummy.com"), 1, 3);

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
    let cosmetic_skin = mint(utf8(b"Fairy"), utf8(b"This skin will make your character look like a fairy"), b"dummy.com", 1, 3, scenario);
    // keep id of cosmetic skin for update ticket later
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    // admin transfers cosmetic skin to user
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by admin to create an update ticket
    test_scenario::next_tx(scenario, ADMIN);
    let update_ticket = create_update_ticket(cosmetic_skin_id, 2, scenario);
    // admin transfers update ticket to user
    transfer::public_transfer(update_ticket, USER);

    // next transaction by user to update their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    update_cosmetic_skin(USER, scenario);

    // next transaction by user to make sure that
    // 1. cosmetic skin is updated properly
    // 2. update ticket is burned
    test_scenario::next_tx(scenario, USER);
    ensure_cosmetic_skin_is_updated_properly(USER, 2, scenario);
    assert!(!test_scenario::has_most_recent_for_address<UpdateTicket>(USER), EObjectShouldHaveNotBeenFound);


    // end test
    test_scenario::end(scenario_val);

  }

  fun mint(name: String, description:String, img_url_bytes: vector<u8>, level: u64, level_cap: u64, scenario: &mut Scenario): CosmeticSkin{
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let cosmetic_skin = cosmetic_skin::mint(&mint_cap, name, description, img_url_bytes, level, level_cap, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    cosmetic_skin
  }

  fun create_update_ticket(cosmetic_skin_id: ID, new_level: u64, scenario: &mut Scenario): UpdateTicket{
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let update_ticket = cosmetic_skin::create_update_ticket(&mint_cap, cosmetic_skin_id, new_level, test_scenario::ctx(scenario));
    test_scenario::return_to_address(ADMIN, mint_cap);
    update_ticket
  }

  fun update_cosmetic_skin(user: address, scenario: &mut Scenario){
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    let update_ticket = test_scenario::take_from_address<UpdateTicket>(scenario, user);
    cosmetic_skin::update_cosmetic_skin(&mut cosmetic_skin, update_ticket);
    test_scenario::return_to_address(user, cosmetic_skin);
  }

  fun ensure_cosmetic_skin_fields_are_correct(cosmetic_skin: &CosmeticSkin, intended_name: String, intended_description: String, intended_img_url: Url, intended_level: u64, intended_level_cap: u64){
    assert!(cosmetic_skin::name(cosmetic_skin) == intended_name, EIncorrectName);
    assert!(cosmetic_skin::description(cosmetic_skin) == intended_description, EIncorrectDescription);
    assert!(cosmetic_skin::img_url(cosmetic_skin) == intended_img_url, EIncorrectUrl);
    assert!(cosmetic_skin::level(cosmetic_skin) == intended_level, EIncorrectLevel);
    assert!(cosmetic_skin::level_cap(cosmetic_skin) == intended_level_cap, EIncorrectLevelCap);
  }

  fun ensure_cosmetic_skin_is_updated_properly(user: address, intended_level: u64, scenario: &mut Scenario){
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, user);
    assert!(cosmetic_skin::level(&cosmetic_skin) == intended_level, EIncorrectLevel);
    test_scenario::return_to_address(user, cosmetic_skin);
  }

}