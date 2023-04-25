#[test_only]
module battle_pass::battle_pass_test{
  use std::string::{String, utf8};

  use sui::object::ID;
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;
  use sui::url::{Self, Url};
  
  use nft_protocol::mint_cap::MintCap;

  use battle_pass::battle_pass::{BattlePass, Self, UpgradeTicket, EUpgradeNotPossible};

  // errors
  const EIncorrectDescription: u64 = 0;
  const EIncorrectUrl: u64 = 1;
  const EIncorrectLevel: u64 = 2;
  const EIncorrectLevelCap: u64 = 3;
  const EIncorrectXP: u64 = 4;
  const EIncorrectXPToNextLevel: u64 = 5;
  const EObjectShouldHaveNotBeenFound: u64 = 6;

  // const addresses
  const ADMIN: address = @0x1;
  const USER: address = @0x1;
  const USER_1: address = @0x2;
  const USER_2: address = @0x3;

  #[test]
  fun test_mint_default(){

    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass and transfer it to user
    test_scenario::next_tx(scenario, ADMIN);
    // admin mints a battle pass with level = 1, xp = 0
    let battle_pass = mint_default(ADMIN, utf8(b"Play Bushi to earn in-game assets using this battle pass"), b"dummy.com", 70, 1000, scenario);
    transfer::public_transfer(battle_pass, USER);

    // next transaction by user to ensure battle pass fields are correct
    test_scenario::next_tx(scenario, USER);
    // make sure that:
    // 1. description is "Play Bushi to earn in-game assets using this battle pass"
    // 2. url is "dummy.com"
    // 3. level = 1
    // 4. level_cap = 70
    // 5. xp = 0
    // 6. xp_to_next_level = 1000
    ensure_correct_battle_pass_fields(USER, utf8(b"Play Bushi to earn in-game assets using this battle pass"), url::new_unsafe_from_bytes(b"dummy.com"), 1, 70, 0, 1000, scenario);

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
    let battle_pass = mint(ADMIN, utf8(b"Play Bushi to earn in-game assets using this battle pass"), b"dummy.com", 2, 150, 500, 2000, scenario);
    transfer::public_transfer(battle_pass, USER);

    // next transaction by user to ensure battle pass fields are correct
    test_scenario::next_tx(scenario, USER);
    // make sure that:
    // 1. description is "Play Bushi to earn in-game assets using this battle pass"
    // 2. url is "dummy.com"
    // 3. level = 2
    // 4. level_cap = 150
    // 5. xp = 500
    // 6. xp_to_next_level = 2000
    ensure_correct_battle_pass_fields(USER, utf8(b"Play Bushi to earn in-game assets using this battle pass"), url::new_unsafe_from_bytes(b"dummy.com"), 2, 150, 500, 2000, scenario);

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
    let battle_pass = mint_default_with_fixed_description_url(ADMIN, scenario);
    // keep the id of the battle pass to create update ticket later
    let battle_pass_id = battle_pass::id(&battle_pass);
    transfer::public_transfer(battle_pass, USER);

    // next transaction by admin to create an update ticket for the user's battle pass and transfer it to the USER
    test_scenario::next_tx(scenario, ADMIN);
    // `new_level` = 2, new_xp = 300, new_xp_to_next_level = 2000
    let upgrade_ticket = create_upgrade_ticket(ADMIN, battle_pass_id, 2, 300, 2000, scenario);
    transfer::public_transfer(upgrade_ticket, USER);

    // next transaction by user to upgrade their battle pass
    test_scenario::next_tx(scenario, USER);
    upgrade_battle_pass(USER, scenario);

    // next transaction by user to make sure that the Battle Pass is upgraded properly
    test_scenario::next_tx(scenario, USER);
    ensure_battle_pass_updated_properly(2, 300, 2000, USER, scenario);

    test_scenario::end(scenario_val);
  }

  #[test]
  #[expected_failure(abort_code = EUpgradeNotPossible)]
  fun test_upgrade_with_wrong_ticket() {

    // module is initialized by admin
    let scenario_val = test_scenario::begin(ADMIN);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass and send in to user1
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass_1 = mint_default_with_fixed_description_url(ADMIN, scenario);
    // keep the id of the battle pass to create upgrade ticket later
    let battle_pass_1_id = battle_pass::id(&battle_pass_1);
    transfer::public_transfer(battle_pass_1, USER_1);

    // next transaction by admin to create an upgrade ticket for battle pass of user1
    test_scenario::next_tx(scenario, ADMIN);
    // new_level = 1, new_xp = 400, new_xp_to_next_level: 600
    let upgrade_ticket = create_upgrade_ticket(ADMIN, battle_pass_1_id, 1, 400, 1000, scenario);
    transfer::public_transfer(upgrade_ticket, USER_1);

    // next transaction by admin to create a battle pass for user2
    test_scenario::next_tx(scenario, ADMIN);
    let battle_pass_2 = mint_default_with_fixed_description_url(ADMIN, scenario);
    transfer::public_transfer(battle_pass_2, USER_2);

    // next transaction by user1 that sends their upgrade ticket to user2
    test_scenario::next_tx(scenario, USER_1);
    let upgrade_ticket = test_scenario::take_from_address<UpgradeTicket>(scenario, USER_1);
    transfer::public_transfer(upgrade_ticket, USER_2);

    // next transaction by user2 that tries to upgrade their battle pass with the ticket of user1
    test_scenario::next_tx(scenario, USER_2);
    upgrade_battle_pass(USER_2, scenario);

    test_scenario::end(scenario_val);
  }

  // === helpers ===

  // mint a battle pass with level = 1, xp = 0 and fixed description and url
  fun mint_default_with_fixed_description_url(admin: address, scenario: &mut Scenario): BattlePass{
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    let battle_pass = battle_pass::mint_default(&mint_cap, utf8(b"Play Bushi to earn in-game assets using this battle pass"), b"dummy.com", 70, 1000, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
    battle_pass
  }

  // mint a battle pass with level = 1, xp = 0 (default)
  fun mint_default(admin: address, description: String, url_bytes: vector<u8>, level_cap: u64, xp_to_next_level: u64, scenario: &mut Scenario): BattlePass{
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    let battle_pass = battle_pass::mint_default(&mint_cap, description, url_bytes, level_cap, xp_to_next_level, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
    battle_pass
  }

  fun mint(admin: address, description: String, url_bytes: vector<u8>, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, scenario: &mut Scenario): BattlePass{
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    let battle_pass = battle_pass::mint(&mint_cap, description, url_bytes, level, level_cap, xp, xp_to_next_level, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
    battle_pass
  }

  // ensure battle pass fields are correct
  fun ensure_correct_battle_pass_fields(user: address, intended_description: String, intended_url: Url, intended_level: u64, intended_level_cap: u64, intended_xp: u64, intended_xp_to_next_level: u64, scenario: &mut Scenario){
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
    assert!(battle_pass::description(&battle_pass) == intended_description, EIncorrectDescription);
    assert!(battle_pass::url(&battle_pass) == intended_url, EIncorrectUrl);
    assert!(battle_pass::level(&battle_pass) == intended_level, EIncorrectLevel);
    assert!(battle_pass::level_cap(&battle_pass) == intended_level_cap, EIncorrectLevelCap);
    assert!(battle_pass::xp(&battle_pass) == intended_xp, EIncorrectXP);
    assert!(battle_pass::xp_to_next_level(&battle_pass) == intended_xp_to_next_level, EIncorrectXPToNextLevel);
    test_scenario::return_to_address(user, battle_pass);
  }

  // create an upgrade ticket
  fun create_upgrade_ticket(admin: address, battle_pass_id: ID, new_level: u64, new_xp: u64, new_xp_to_next_level: u64, scenario: &mut Scenario): UpgradeTicket{
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    let upgrade_ticket = battle_pass::create_upgrade_ticket(&mint_cap, battle_pass_id, new_level, new_xp, new_xp_to_next_level, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
    upgrade_ticket
  }

  /// upgrade the last battle pass user has received using the last ticket they have received
  fun upgrade_battle_pass(user: address, scenario: &mut Scenario){
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
    let upgrade_ticket = test_scenario::take_from_address<UpgradeTicket>(scenario, user);
    battle_pass::upgrade_battle_pass(&mut battle_pass, upgrade_ticket, test_scenario::ctx(scenario));
    test_scenario::return_to_address(user, battle_pass);
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