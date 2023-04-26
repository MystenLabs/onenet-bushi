module bushi::battle_pass{

  use std::string::utf8;

  use sui::display::{Self, Display};
  use sui::object::{Self, ID, UID};
  use sui::package;
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::url::{Self, Url};

  // errors
  const EUpgradeNotPossible: u64 = 0;

  // constants
  const BASE_XP_TO_NEXT_LEVEL: u64 = 1000;
  const LEVEL_CAP: u64 = 70;

  /// Battle pass struct
  struct BattlePass has key, store{
    id: UID,
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

  /// One-time-witness for display
  struct BATTLE_PASS has drop {}

  /// Upgrade ticket
  struct UpgradeTicket has key, store {
    id: UID,
    // ID of the battle pass that this ticket can upgrade
    battle_pass_id: ID,
    // experience that will be added to the battle pass
    xp_added: u64,
  }

  /// init function
  fun init(otw: BATTLE_PASS, ctx: &mut TxContext){

    let publisher_address = tx_context::sender(ctx);

    // claim `publisher` object
    let publisher = package::claim(otw, ctx);
    // create a display object
    let display = display::new<BattlePass>(&publisher, ctx);
    // set display
    // TODO: determine display standards
    set_display_fields(&mut display);
    // transfer display to publisher_address
    transfer::public_transfer(display, publisher_address);
    // transfer publisher object to publisher_address
    transfer::public_transfer(publisher, publisher_address);

    // create Mint Capability
    let mint_cap = MintCap { id: object::new(ctx) };
    // transfer mint cap to address that published the module
    transfer::transfer(mint_cap, publisher_address)
  }

  // === Mint functions ====

  /// mint a battle pass NFT
  public fun mint(
    _: &MintCap, url_bytes: vector<u8>, level: u64, xp: u64, ctx: &mut TxContext
    ): BattlePass{
      BattlePass { 
        id: object::new(ctx), 
        url: url::new_unsafe_from_bytes(url_bytes),
        level,
        level_cap: LEVEL_CAP,
        xp,
        xp_to_next_level: (level + 1) * BASE_XP_TO_NEXT_LEVEL,
      }
  }

  /// mint a battle pass NFT that has level set to 1 and xp set to 0
  public fun mint_default(
    mint_cap: &MintCap, url_bytes: vector<u8>, ctx: &mut TxContext
    ): BattlePass{
      mint(mint_cap, url_bytes, 1, 0, ctx)
  }

  // mint a battle pass and transfer it to a specific address
  public fun mint_and_transfer(
    mint_cap: &MintCap, url_bytes: vector<u8>, level: u64, xp: u64, recipient: address, ctx: &mut TxContext
    ){
      let battle_pass = mint(mint_cap, url_bytes, level, xp, ctx);
      transfer::transfer(battle_pass, recipient)
  }

  /// mint a battle pass with level set to 1 and xp set to 0 and then transfer it to a specific address
  public fun mint_default_and_transfer(
    mint_cap: &MintCap, url_bytes: vector<u8>, recipient: address, ctx: &mut TxContext
    ) {
      let battle_pass = mint_default(mint_cap, url_bytes, ctx);
      transfer::transfer(battle_pass, recipient)
  }

  // === Upgrade ticket ====

  /// to create an upgrade ticket the mint cap is needed
  /// this means the entity that can mint a battle pass can also issue a ticket to upgrade it
  /// but the function can be altered so that the two are separate entities
  public fun create_upgrade_ticket(
    _: &MintCap, battle_pass_id: ID, xp_added: u64, ctx: &mut TxContext
    ): UpgradeTicket {
      UpgradeTicket { id: object::new(ctx), battle_pass_id, xp_added }
  }

  /// call the `create_upgrade_ticket` and send the ticket to a specific address
  public fun create_upgrade_ticket_and_transfer(
    mint_cap: &MintCap, battle_pass_id: ID, xp_added: u64, recipient: address, ctx: &mut TxContext
    ){
      let upgrade_ticket = create_upgrade_ticket(mint_cap, battle_pass_id, xp_added, ctx);
      transfer::transfer(upgrade_ticket, recipient)
  }

  // === Upgrade battle pass ===

  /// a battle pass holder will call this function to upgrade the battle pass
  /// every time the level is increased, excess xp carries over to next level
  public fun upgrade_battle_pass(
    battle_pass: &mut BattlePass, upgrade_ticket: UpgradeTicket, _: &mut TxContext
    ){
      // make sure that upgrade ticket is for this battle pass
      let battle_pass_id = object::uid_to_inner(&battle_pass.id);
      assert!(battle_pass_id == upgrade_ticket.battle_pass_id, EUpgradeNotPossible);

      // if already in max level delete upgrade ticket and return
      // we could also abort here
      if (battle_pass.level == battle_pass.level_cap) {
        // delete the upgrade ticket so that it cannot be re-used
        delete_upgrade_ticket(upgrade_ticket);
        return
      };

      let remaining_xp = battle_pass.xp + upgrade_ticket.xp_added;
      while ( remaining_xp >= battle_pass.xp_to_next_level ){
        // increment the level
        battle_pass.level = battle_pass.level + 1;
        // substract the xp used to get to next level
        remaining_xp = remaining_xp - battle_pass.xp_to_next_level;
        // update the xp needed to get to next level
        battle_pass.xp_to_next_level = battle_pass.xp_to_next_level + BASE_XP_TO_NEXT_LEVEL;
        // if reached level 70, set remaining xp to 0
        if (battle_pass.level == 70 ) {
          remaining_xp = 0;
        }
      };
      // update battle pass xp to remaining xp
      battle_pass.xp = remaining_xp;

      // delete the upgrade ticket so that it cannot be re-used
      delete_upgrade_ticket(upgrade_ticket);
  }

  // === helpers ===

  fun set_display_fields(display: &mut Display<BattlePass>) {
    let fields = vector[
      utf8(b"name"),
      utf8(b"description"),
      utf8(b"url"),
    ];
    // url can also be something like `utf8(b"bushi.com/{url})"`
    let values = vector[
      utf8(b"Battle Pass"),
      utf8(b"Play Bushi to earn in-game assets by using this battle pass"),
      utf8(b"{url}"),
    ];
    display::add_multiple<BattlePass>(display, fields, values);
  }

  fun delete_upgrade_ticket(upgrade_ticket: UpgradeTicket) {
    let UpgradeTicket { id: upgrade_ticket_id, battle_pass_id: _, xp_added: _ } = upgrade_ticket;
    object::delete(upgrade_ticket_id)
  }

  // === Test only ===

  #[test_only]
  public fun init_test(ctx: &mut TxContext){
    init(BATTLE_PASS {}, ctx);
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