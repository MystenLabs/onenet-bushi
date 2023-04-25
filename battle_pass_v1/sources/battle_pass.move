module battle_pass::battle_pass{

  use std::string::{String, utf8};
  use std::option;

  use sui::display::{Self, Display};
  use sui::object::{Self, ID, UID};
  use sui::package;
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::url::{Self, Url};

  use nft_protocol::collection;
  use nft_protocol::mint_cap::{Self, MintCap};
  use nft_protocol::mint_event;
  use nft_protocol::witness;

  // errors
  const EUpgradeNotPossible: u64 = 0;

  // consts
  const DEFAULT_INIT_LEVEL: u64 = 1;
  const DEFAULT_INIT_XP: u64 = 0;

  /// One-time-witness
  struct BATTLE_PASS has drop {}

  // Witness struct for Witness-Protected actions
  struct Witness has drop {}

  /// Battle pass struct
  struct BattlePass has key, store{
    id: UID,
    description: String,
    // image url
    url: Url,
    level: u64,
    level_cap: u64,
    xp: u64,
    xp_to_next_level: u64,
  }

  /// Upgrade ticket
  // note: does not include "new_level_cap" field
  // meaning level_cap cannot be updated via this ticket
  // but this field can be added if needed
  struct UpgradeTicket has key, store {
    id: UID,
    // ID of the battle pass that this ticket can upgrade
    battle_pass_id: ID,
    // new level of battle pass
    new_level: u64,
    // new xp of battle pass
    new_xp: u64,
    // new xp to next level of battle pass
    new_xp_to_next_level: u64,
  }

  /// init function
  fun init(otw: BATTLE_PASS, ctx: &mut TxContext){

    // initialize a collection for BattlePass type
    let (collection, mint_cap) = collection::create_with_mint_cap<BATTLE_PASS, BattlePass>(&otw, option::none(), ctx);

    // claim `publisher` object
    let publisher = package::claim(otw, ctx);

    // --- display ---

    // create a display object
    let display = display::new<BattlePass>(&publisher, ctx);
    // set display
    // TODO: determine display standards
    set_display_fields(&mut display);

    // --- transfers to address that published the module ---
    let publisher_address = tx_context::sender(ctx);
    transfer::public_transfer(mint_cap, publisher_address);
    transfer::public_transfer(publisher, publisher_address);
    transfer::public_transfer(display, publisher_address);

    // --- shared objects ---
    transfer::public_share_object(collection);
  }

  // === Mint functions ====

  /// mint a battle pass NFT
  public fun mint(
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, ctx: &mut TxContext
    ): BattlePass{
      let battle_pass = BattlePass { 
        id: object::new(ctx),
        description, 
        url: url::new_unsafe_from_bytes(url_bytes),
        level,
        level_cap,
        xp,
        xp_to_next_level,
      };

      // emit a mint event

    mint_event::emit_mint(
      witness::from_witness(Witness {}),
      mint_cap::collection_id(mint_cap),
      &battle_pass
    );

    battle_pass
  }

  /// mint a battle pass NFT that has level = 1, xp = 0
  /// we can specify and change default values
  public fun mint_default(
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level_cap: u64, xp_to_next_level: u64, ctx: &mut TxContext
    ): BattlePass{
      mint(mint_cap, description, url_bytes, DEFAULT_INIT_LEVEL, level_cap, DEFAULT_INIT_XP, xp_to_next_level, ctx)
  }

  // === Upgrade ticket ====

  /// to create an upgrade ticket the mint cap is needed
  /// this means the entity that can mint a battle pass can also issue a ticket to upgrade it
  /// but the function can be altered so that the two are separate entities
  public fun create_upgrade_ticket(
    _: &MintCap<BattlePass>, battle_pass_id: ID, new_level: u64, new_xp: u64, new_xp_to_next_level: u64, ctx: &mut TxContext
    ): UpgradeTicket {
      UpgradeTicket { id: object::new(ctx), battle_pass_id, new_level, new_xp, new_xp_to_next_level }
  }

  // === Upgrade battle pass ===

  /// a battle pass holder will call this function to upgrade the battle pass
  /// aborts if upgrade_ticket.battle_pass_id != id of Battle Pass
  /// Warning: if upgrade_ticket.new_level >= battle_pass.level_cap, function will not abort
  /// We can add a check
  public fun upgrade_battle_pass(
    battle_pass: &mut BattlePass, upgrade_ticket: UpgradeTicket, _: &mut TxContext
    ){
      // make sure that upgrade ticket is for this battle pass
      let battle_pass_id = object::uid_to_inner(&battle_pass.id);
      assert!(battle_pass_id == upgrade_ticket.battle_pass_id, EUpgradeNotPossible);

      battle_pass.level = upgrade_ticket.new_level;
      battle_pass.xp = upgrade_ticket.new_xp;
      battle_pass.xp_to_next_level = upgrade_ticket.new_xp_to_next_level;


      // delete the upgrade ticket so that it cannot be re-used
      let UpgradeTicket { id: upgrade_ticket_id, battle_pass_id: _, new_level: _, new_xp: _, new_xp_to_next_level: _}  = upgrade_ticket;
      object::delete(upgrade_ticket_id)
  }

  // === helpers ===

  fun set_display_fields(display: &mut Display<BattlePass>) {
    let fields = vector[
      utf8(b"name"),
      utf8(b"description"),
      utf8(b"url"),
      utf8(b"level"),
      utf8(b"level_cap"),
      utf8(b"xp"),
      utf8(b"xp_to_next_level"),
    ];
    let values = vector[
      utf8(b"Battle Pass"),
      utf8(b"{description}"),
      // url can also be something like `utf8(b"bushi.com/{url})"` or `utf8(b"ipfs/{url})` to save on space
      utf8(b"{url}"),
      utf8(b"{level}"),
      utf8(b"{level_cap}"),
      utf8(b"{xp}"),
      utf8(b"{xp_to_next_level}"),
    ];
    display::add_multiple<BattlePass>(display, fields, values);
  }

  // === test only ===
  #[test_only]
  public fun init_test(ctx: &mut TxContext){
    init(BATTLE_PASS {}, ctx);
  }

  #[test_only]
  public fun id(battle_pass: &BattlePass): ID {
    object::uid_to_inner(&battle_pass.id)
  }

  #[test_only]
  public fun description(battle_pass: &BattlePass): String {
    battle_pass.description
  }

  #[test_only]
  public fun level(battle_pass: &BattlePass): u64 {
    battle_pass.level
  }

  #[test_only]
  public fun level_cap(battle_pass: &BattlePass): u64 {
    battle_pass.level_cap
  }

  #[test_only]
  public fun xp(battle_pass: &BattlePass): u64 {
    battle_pass.xp
  }

  #[test_only]
  public fun xp_to_next_level(battle_pass: &BattlePass): u64 {
    battle_pass.xp_to_next_level
  }

}