#[test_only]
module battle_pass::battle_pass_test{

  use sui::object::ID;
  use sui::test_scenario::{Self, Scenario};
  use sui::transfer;
  
  use nft_protocol::mint_cap::MintCap;

  use battle_pass::battle_pass::{BattlePass, Self, UpgradeTicket, EUpgradeNotPossible};

  const EIncorrectLevel: u64 = 0;
  const EIncorrectXP: u64 = 1;
  const EObjectShouldHaveNotBeenFound: u64 = 2;

  #[test]
  fun test_flow(){

    let admin = @0x1;
    let user = @0x2;

    // module is initialized by admin
    let scenario_val = test_scenario::begin(admin);
    let scenario = &mut scenario_val;
    battle_pass::init_test(test_scenario::ctx(scenario));

    // next transaction by admin to create a battle pass and transfer it to user
    test_scenario::next_tx(scenario, admin);
    let battle_pass = mint_default(admin, scenario);
    // keep the id of the battle pass to create update ticket later
    let battle_pass_id = battle_pass::id(&battle_pass);
    transfer::public_transfer(battle_pass, user);

    // next transaction by admin to create an update ticket for the user's battle pass and transfer it to the user
    test_scenario::next_tx(scenario, admin);
    // `new_xp` = 600, `new_level` = 1
    let upgrade_ticket = create_upgrade_ticket(admin, battle_pass_id,600, 1, scenario);
    transfer::public_transfer(upgrade_ticket, user);

    // next transaction by user to upgrade their battle pass
    test_scenario::next_tx(scenario, user);
    upgrade_battle_pass(user, scenario);

    // next transaction by user to make sure that the Battle Pass is upgraded properly
    test_scenario::next_tx(scenario, user);
    ensure_battle_pass_level_xp_as_intended(600, 1, user, scenario);

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
    let battle_pass_1 = mint_default(admin, scenario);
    // keep the id of the battle pass to create upgrade ticket later
    let battle_pass_1_id = battle_pass::id(&battle_pass_1);
    transfer::public_transfer(battle_pass_1, user1);

    // next transaction by admin to create an upgrade ticket for battle pass of user1
    test_scenario::next_tx(scenario, admin);
    let upgrade_ticket = create_upgrade_ticket(admin, battle_pass_1_id, 1, 500, scenario);
    transfer::public_transfer(upgrade_ticket, user1);

    // next transaction by admin to create a battle pass for user2
    test_scenario::next_tx(scenario, admin);
    let battle_pass_2 = mint_default(admin, scenario);
    transfer::public_transfer(battle_pass_2, user2);

    // next transaction by user1 that sends their upgrade ticket to user2
    test_scenario::next_tx(scenario, user1);
    let upgrade_ticket = test_scenario::take_from_address<UpgradeTicket>(scenario, user1);
    transfer::public_transfer(upgrade_ticket, user2);

    // next transaction by user2 that tries to upgrade their battle pass with the ticket of user1
    test_scenario::next_tx(scenario, user2);
    upgrade_battle_pass(user2, scenario);

    test_scenario::end(scenario_val);
  }

  // === helpers ===

  // mint a battle pass with level = 1 and xp = 0
  fun mint_default(admin: address, scenario: &mut Scenario): BattlePass{
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    let battle_pass = battle_pass::mint_default(&mint_cap, b"dummy.com", test_scenario::ctx(scenario));
    test_scenario::return_to_address(admin, mint_cap);
    battle_pass
  }

  // create an upgrade ticket
  fun create_upgrade_ticket(admin: address, battle_pass_id: ID, new_xp: u64, new_level: u64, scenario: &mut Scenario): UpgradeTicket{
    let mint_cap = test_scenario::take_from_address<MintCap<BattlePass>>(scenario, admin);
    let upgrade_ticket = battle_pass::create_upgrade_ticket(&mint_cap, battle_pass_id, new_xp, new_level, test_scenario::ctx(scenario));
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
  fun ensure_battle_pass_level_xp_as_intended(intended_xp: u64, intended_level: u64, user: address, scenario: &mut Scenario){
    let battle_pass = test_scenario::take_from_address<BattlePass>(scenario, user);
    assert!(battle_pass::level(&battle_pass) == intended_level, EIncorrectLevel);
    assert!(battle_pass::xp(&battle_pass) == intended_xp, EIncorrectXP);
    test_scenario::return_to_address(user, battle_pass);
  }
  
}