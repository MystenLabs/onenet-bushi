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

  /// One-time-witness for display
  struct BATTLE_PASS has drop {}

  /// Battle pass struct
  struct BattlePass has key, store{
    id: UID,
    url: Url,
    level: u64,
    xp: u64,
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
    // new xp of battle pass
    new_xp: u64,
    // new level of battle pass
    new_level: u64,
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
        xp,
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
    _: &MintCap, battle_pass_id: ID, new_xp: u64, new_level: u64, ctx: &mut TxContext
    ): UpgradeTicket {
      UpgradeTicket { id: object::new(ctx), battle_pass_id, new_xp, new_level }
  }

  /// call the `create_upgrade_ticket` and send the ticket to a specific address
  public fun create_upgrade_ticket_and_transfer(
    mint_cap: &MintCap, battle_pass_id: ID, new_xp: u64, new_level: u64, recipient: address, ctx: &mut TxContext
    ){
      let upgrade_ticket = create_upgrade_ticket(mint_cap, battle_pass_id, new_xp, new_level, ctx);
      transfer::transfer(upgrade_ticket, recipient)
  }

  // === Upgrade battle pass ===

  /// a battle pass holder will call this function to upgrade the battle pass
  public fun upgrade_battle_pass(
    battle_pass: &mut BattlePass, upgrade_ticket: UpgradeTicket, _: &mut TxContext
    ){
      // make sure that upgrade ticket is for this battle pass
      let battle_pass_id = object::uid_to_inner(&battle_pass.id);
      assert!(battle_pass_id == upgrade_ticket.battle_pass_id, EUpgradeNotPossible);

      battle_pass.xp = upgrade_ticket.new_xp;
      battle_pass.level = upgrade_ticket.new_level;

      // delete the upgrade ticket so that it cannot be re-used
      let UpgradeTicket { id: upgrade_ticket_id, battle_pass_id: _, new_xp: _ , new_level: _}  = upgrade_ticket;
      object::delete(upgrade_ticket_id)
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
      utf8(b"Play Bushi to earn in-game assets by using this battle pass."),
      utf8(b"{url}"),
    ];
    display::add_multiple<BattlePass>(display, fields, values);
  }
}