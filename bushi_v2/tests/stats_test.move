#[test_only]
module bushi::stat_test {

  use std::string::{String, utf8};

  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;

  use nft_protocol::mint_cap::{MintCap};

  use bushi::cosmetic_skin::{Self, CosmeticSkin};
  use bushi::stats;
  use bushi::cosmetic_skin_test;

  // error codes
  const EDFNotSetProperly: u64 = 0;

  // const addresses
  const ADMIN: address = @0x1;
  const USER: address = @0x2;

  // const values
  const DUMMY_DESCRIPTION_BYTES: vector<u8> = b"This skin will make your character look like a fairy";
  const DUMMY_URL_BYTES: vector<u8> = b"dummy.com";

  #[test]
  fun test_add_or_edit_dfs(){

    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    cosmetic_skin::init_test(test_scenario::ctx(scenario));

    // next transaction by ADMIN to mint a Cosmetic Skin and transfer it to the user
    test_scenario::next_tx(scenario, ADMIN);
    let cosmetic_skin = mint_with_dfs(scenario);
    transfer::public_transfer(cosmetic_skin, USER);

    // next transaction by ADMIN to issue an unlock updates ticket for user
    test_scenario::next_tx(scenario, ADMIN);
    // find ID of cosmetic skin
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, USER);
    let cosmetic_skin_id = cosmetic_skin::id(&cosmetic_skin);
    test_scenario::return_to_address(USER, cosmetic_skin);
    // create and transfer unlock updates ticket
    let unlock_updates_ticket = cosmetic_skin_test::create_unlock_updates_ticket(cosmetic_skin_id, scenario);
    transfer::public_transfer(unlock_updates_ticket, USER);

    // next transaction by user to unlock updates for their cosmetic skin
    test_scenario::next_tx(scenario, USER);
    cosmetic_skin_test::unlock_updates(USER, scenario);

    // next transaction by user to make sure their cosmetic skin has stats with proper values
    test_scenario::next_tx(scenario, USER);
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, USER);
    // the stats we have added is: games = 0, kills = 0.
    let stat_name_1 = utf8(b"games");
    let stat_name_2 = utf8(b"kills");
    let stat_value_1 = utf8(b"0");
    let stat_value_2 = utf8(b"0");
    assert!(stats::get_stat_value(&cosmetic_skin, stat_name_1) == stat_value_1, EDFNotSetProperly);
    assert!(stats::get_stat_value(&cosmetic_skin, stat_name_2) == stat_value_2, EDFNotSetProperly);
    test_scenario::return_to_address(USER, cosmetic_skin);

    // next transaction by user to update their cosmetic skin kills stat
    test_scenario::next_tx(scenario, USER);
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, USER);
    let stat_names = vector<String>[utf8(b"kills")];
    let stat_values = vector<String>[utf8(b"10")];
    stats::update_or_add_stats(
      &mut cosmetic_skin,
      stat_names,
      stat_values,
    );
    test_scenario::return_to_address(USER, cosmetic_skin);

    // next transaction by user to make sure kills are updated properly
    test_scenario::next_tx(scenario, USER);
    let cosmetic_skin = test_scenario::take_from_address<CosmeticSkin>(scenario, USER);
    let kills_value = stats::get_stat_value(&cosmetic_skin, utf8(b"kills"));
    assert!(kills_value == utf8(b"10"), EDFNotSetProperly);
    test_scenario::return_to_address(USER, cosmetic_skin);

    test_scenario::end(scenario_val);
  }

  fun mint_with_dfs(scenario: &mut Scenario): CosmeticSkin {
    let mint_cap = test_scenario::take_from_address<MintCap<CosmeticSkin>>(scenario, ADMIN);
    let cosmetic_skin = stats::mint_with_dfs(
      &mint_cap, 
      utf8(b"Fairy"), // name 
      utf8(DUMMY_DESCRIPTION_BYTES), //description
      utf8(DUMMY_URL_BYTES), //url
      1, // level
      3, // level cap
      utf8(b"1111"), // game asset id
      vector<String>[utf8(b"games"), utf8(b"kills")], // stat names
      vector<String>[utf8(b"0"), utf8(b"0")], // values
      test_scenario::ctx(scenario)
      ); 
    test_scenario::return_to_address(ADMIN, mint_cap);
    cosmetic_skin
  }
    
}