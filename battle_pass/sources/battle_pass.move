module battle_pass::battle_pass{

  use std::string::{Self, String};

  use sui::object::{Self, ID, UID};
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::url::{Self, Url};

  // errors
  const EUpgradeNotPossible: u64 = 0;

  // constants
  const XP_TO_NEXT_LEVEL: u64 = 1000;
  const LEVEL_CAP: u64 = 70;

  /// Battle pass struct
  struct BattlePass has key, store{
    id: UID,
    name: String,
    description: String,
    url: Url,
    level: u64,
    level_cap: u64,
    xp: u64,
    xp_to_next_level: u64,
  }

  /// Mint capability
  /// has `store` ability so it can be transferred
  struct MintCap has key, store {
    id: UID,
  }

  /// Upgrade ticket
  struct UpgradeTicket has key, store {
    id: UID,
    // ID of the battle pass that this ticket can upgrade
    battle_pass_id: ID,
    // experience that will be added to the battle pass
    xp_added: u64,
  }

  /// init function
  fun init(ctx: &mut TxContext){

    // create Mint Capability
    let mint_cap = MintCap { id: object::new(ctx) };

    // transfer mint cap to address that published the module
    transfer::transfer(mint_cap, tx_context::sender(ctx))
  }

  /// mint a battle pass NFT
  public fun mint(_: &MintCap, name_bytes: vector<u8>, description_bytes: vector<u8>, url_bytes: vector<u8>, level: u64, xp: u64, ctx: &mut TxContext): BattlePass{
    BattlePass { 
      id: object::new(ctx), 
      name: string::utf8(name_bytes),
      description: string::utf8(description_bytes),
      url: url::new_unsafe_from_bytes(url_bytes),
      level,
      level_cap: LEVEL_CAP,
      xp,
      xp_to_next_level: XP_TO_NEXT_LEVEL,
    }
  }

  /// mint a battle pass NFT that has level set to 1 and xp set to 0
  public fun mint_default(mint_cap: &MintCap, name_bytes: vector<u8>, description_bytes: vector<u8>, url_bytes: vector<u8>, ctx: &mut TxContext): BattlePass{
    mint(mint_cap, name_bytes, description_bytes, url_bytes, 1, 0, ctx)
  }

  /// mint a battle pass with level set to 1 and xp set to 0 and then transfer it to a specific address
  public fun mint_default_and_transfer(mint_cap: &MintCap, name_bytes: vector<u8>, description_bytes: vector<u8>, url_bytes: vector<u8>, recipient: address, ctx: &mut TxContext) {
    let battle_pass = mint_default(mint_cap, name_bytes, description_bytes, url_bytes, ctx);
    transfer::transfer(battle_pass, recipient)
  }

  // mint a battle pass and transfer it to a specific address
  public fun mint_and_transfer(mint_cap: &MintCap, name_bytes: vector<u8>, description_bytes: vector<u8>, url_bytes: vector<u8>, level: u64, xp: u64, recipient: address, ctx: &mut TxContext){
      let battle_pass = mint(mint_cap, name_bytes, description_bytes, url_bytes, level, xp, ctx);
      transfer::transfer(battle_pass, recipient)
  }

  /// to create an upgrade ticket the mint cap is needed
  /// this means the entity that can mint a battle passe can also issue a ticket to upgrade it
  /// but the function can be altered so that the two are separate entities
  public fun create_upgrade_ticket(_: &MintCap, battle_pass_id: ID, xp_added: u64, ctx: &mut TxContext): UpgradeTicket {
    UpgradeTicket { id: object::new(ctx), battle_pass_id, xp_added }
  }

  /// call the `create_upgrade_ticket` and send the ticket to a specific address
  public fun create_upgrade_ticket_and_transfer(mint_cap: &MintCap, battle_pass_id: ID, xp_added: u64, recipient: address, ctx: &mut TxContext){
    let upgrade_ticket = create_upgrade_ticket(mint_cap, battle_pass_id, xp_added, ctx);
    transfer::transfer(upgrade_ticket, recipient)
  }

  /// a battle pass holder will call this function to upgrade the battle pass
  /// every time a level is incremented, xp is set to 0
  public fun upgrade_battle_pass(battle_pass: &mut BattlePass, upgrade_ticket: UpgradeTicket, _: &mut TxContext){

    // make sure that upgrade ticket is for this battle pass
    let battle_pass_id = object::uid_to_inner(&battle_pass.id);
    assert!(battle_pass_id == upgrade_ticket.battle_pass_id, EUpgradeNotPossible);

    // if already in max level delete upgrade ticket and return
    // we could also abort here
    if (battle_pass.level == battle_pass.level_cap) {
      // delete the upgrade ticket so that it cannot be re-used
      let UpgradeTicket { id: upgrade_ticket_id, battle_pass_id: _, xp_added: _ } = upgrade_ticket;
      object::delete(upgrade_ticket_id);
      return
    };

    // if enough xp to get to next level increment level and set xp to 0
    if ( battle_pass.xp + upgrade_ticket.xp_added >= battle_pass.xp_to_next_level ) {
      battle_pass.level = battle_pass.level + 1;
      battle_pass.xp = 0;
    } 
    // if not enough xp to next level increment the xp of battle pass
    else {
      battle_pass.xp = battle_pass.xp + upgrade_ticket.xp_added;
    };

    // delete the upgrade ticket so that it cannot be re-used
    let UpgradeTicket { id: upgrade_ticket_id, battle_pass_id: _, xp_added: _ } = upgrade_ticket;
    object::delete(upgrade_ticket_id)
  }

  // === Test only ===

  #[test_only]
  public fun init_test(ctx: &mut TxContext){
    init(ctx);
  }

  #[test_only]
  public fun id(battle_pass: &BattlePass): ID {
    object::uid_to_inner(&battle_pass.id)
  }

  #[test_only]
  public fun level(battle_pass: &BattlePass): u64 {
    battle_pass.level
  }

  #[test_only]
  public fun xp(battle_pass: &BattlePass): u64 {
    battle_pass.xp
  }

}