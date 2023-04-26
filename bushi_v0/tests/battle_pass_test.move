#[test_only]

module bushi::battle_pass_test {
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;
  
  use bushi::battle_pass::{BattlePass, Self, MintCap, UpgradeTicket, EUpgradeNotPossible};

  const EIncorrectLevel: u64 = 0;
  const EIncorrectXP: u64 = 1;
  const EObjectShouldHaveNotBeenFound: u64 = 2;

  // test basic flow
  #[test]
  fun test_basic_flow(){
    
    let admin = @0x1;
    let user = @0x2;

    // module is initialized by admin
    let scenario_val = test_scenario::begin(admin);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a battle pass and send it to user
    test_scenario::next_tx(scenario, admin);
    mint_default_and_transfer(admin, user, scenario);

    // next transaction by admin to create an upgrade ticket
    test_scenario::next_tx(scenario, admin);
    create_upgrade_ticket_and_transfer(admin, user, 400, scenario);

    // next transaction by user to upgrade their battle pass
    test_scenario::next_tx(scenario, user);
    upgrade_battle_pass(user, scenario);

    // next transaction by user
    // here we make sure that:
    // 1. battle pass is upgraded properly
    // 2. upgrade ticket is burned properly
    test_scenario::next_tx(scenario, user);
    ensure_battle_pass_level_xp_as_intended(1, 400, user, scenario);
    assert!(!test_scenario::has_most_recent_for_address<UpgradeTicket>(user), EObjectShouldHaveNotBeenFound);

    // next transaction by admin to issue one more upgrade ticket
    test_scenario::next_tx(scenario, admin);
    create_upgrade_ticket_and_transfer(admin, user, 1700, scenario);

    // next transaction by user to upgraed again their battle pass
    test_scenario::next_tx(scenario, user);
    upgrade_battle_pass(user, scenario);

    // next transaction by user to make sure the battle pass is upgraded properly
    test_scenario::next_tx(scenario, user);
    ensure_battle_pass_level_xp_as_intended(2, 100, user, scenario);
    test_scenario::end(scenario_val);
  }

  #[test]
  fun test_upgrade_when_max_level() {

    let admin = @0x1;
    let user = @0x2;

    // module is initialized by admin
    let scenario_val = test_scenario::begin(admin);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to mint a battle pass with level 69 and xp 600
    test_scenario::next_tx(scenario, admin);
    mint_and_transfer(admin, user, 69, 70800, scenario);

    // next transaction by admin to issue an upgrade ticket for 500 xp
    test_scenario::next_tx(scenario, admin);
    create_upgrade_ticket_and_transfer(admin, user, 500, scenario);

    // next transaction by user to upgrade their battle pass
    test_scenario::next_tx(scenario, user);
    upgrade_battle_pass(user, scenario);

    // next transaction by user
    // to make sure that
    // 1. xp is 0
    // 2. level is 70
    test_scenario::next_tx(scenario, user);
    ensure_battle_pass_level_xp_as_intended(70, 0, user, scenario);

    // next transaction by admin to issue one more upgrade ticket
    test_scenario::next_tx(scenario, admin);
    create_upgrade_ticket_and_transfer(admin, user, 100, scenario);

    // next transaction by user to upgrade their battle pass
    test_scenario::next_tx(scenario, user);
    upgrade_battle_pass(user, scenario);

    // next transaction by user to make sure that battle pass is not upgraded
    // i.e.: level should remain 70 and the xp remain 0
    test_scenario::next_tx(scenario, user);
    ensure_battle_pass_level_xp_as_intended(70, 0, user, scenario);

    test_scenario::end(scenario_val);
  }

  #[test]
  #[expected_failure(abort_code = EUpgradeNotPossible)]
  fun test_upgrade_with_wrong_ticket() {

    let admin = @0x1;
    let user1 = @0x2;
    let user2 = @0x3;

    // module is initialized by admin
    let scenario_val = test_scenario::begin(admin);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass and send in to user1
    test_scenario::next_tx(scenario, admin);
    mint_default_and_transfer(admin, user1, scenario);

    // next transaction by admin to create an upgrade ticket for battle pass of user1
    test_scenario::next_tx(scenario, admin);
    create_upgrade_ticket_and_transfer(admin, user1, 500, scenario);

    // next transaction by admin to create a battle pass for user2
    test_scenario::next_tx(scenario, admin);
    mint_default_and_transfer(admin, user2, scenario);

    // next transaction by user1 that sends their upgrade ticket to user2
    test_scenario::next_tx(scenario, user1);
    let upgrade_ticket = test_scenario::take_from_address<UpgradeTicket>(scenario, user1);
    transfer::public_transfer(upgrade_ticket, user2);

    // next transaction by user2 that tries to upgrade their battle pass with the ticket of user1
    test_scenario::next_tx(scenario, user2);
    upgrade_battle_pass(user2, scenario);

    test_scenario::end(scenario_val);
  }

  fun mint_and_transfer(admin: address, recipient: address, level: u64, xp: u64, scenario: &mut Scenario){
    let mint_cap = test_scenario::take_from_address<MintCap>(scenario, admin);
    battle_pass::mint_and_transfer(&mint_cap,b"dummy.com", level, xp, recipient, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
  }

  fun mint_default_and_transfer(admin: address, recipient: address, scenario: &mut Scenario){
    let mint_cap = test_scenario::take_from_address<MintCap>(scenario, admin);
    battle_pass::mint_default_and_transfer(&mint_cap, b"dummy.com", recipient, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
  }

  fun create_upgrade_ticket_and_transfer(admin: address, recipient: address, xp_added: u64, scenario: &mut Scenario){
    let mint_cap = test_scenario::take_from_address<MintCap>(scenario, admin);
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, recipient);
    let battle_pass_id = battle_pass::id(&battle_pass);
    battle_pass::create_upgrade_ticket_and_transfer(&mint_cap, battle_pass_id, xp_added, recipient, test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
    test_scenario::return_to_address(recipient, battle_pass);
  }

  /// upgrade the last battle pass user has received using the last ticket they have received
  fun upgrade_battle_pass(user: address, scenario: &mut Scenario){
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
    let upgrade_ticket = test_scenario::take_from_address<UpgradeTicket>(scenario, user);
    battle_pass::upgrade_battle_pass(&mut battle_pass, upgrade_ticket, test_scenario::ctx(scenario));
    test_scenario::return_to_address(user, battle_pass);
  }

  /// ensures battle pass level and xp is as intended, aborts otherwise
  fun ensure_battle_pass_level_xp_as_intended(intended_level: u64, intended_xp: u64, user: address, scenario: &mut Scenario){
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
    assert!(battle_pass::level(&battle_pass) == intended_level, EIncorrectLevel);
    assert!(battle_pass::xp(&battle_pass) == intended_xp, EIncorrectXP);
    test_scenario::return_to_address(user, battle_pass);
  }
  
}
