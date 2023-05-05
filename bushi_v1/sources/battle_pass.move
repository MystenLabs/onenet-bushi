module bushi::battle_pass{

  use std::string::{String, utf8};
  use std::option;

  use sui::display::{Self, Display};
  use sui::kiosk::Kiosk;
  use sui::object::{Self, ID, UID};
  use sui::package;
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::url::{Self, Url};

  // --- OB imports ---

  use ob_launchpad::warehouse::{Self, Warehouse};

  use nft_protocol::collection;
  use nft_protocol::mint_cap::{Self, MintCap};
  use nft_protocol::mint_event;
  use nft_protocol::royalty;
  use nft_protocol::royalty_strategy_bps;
  use nft_protocol::transfer_allowlist;
  use nft_protocol::transfer_token;

  use ob_kiosk::ob_kiosk;

  use ob_permissions::witness;

  use ob_request::transfer_request;
  use ob_request::withdraw_request;

  use ob_utils::utils;


  // errors
  const EUpdateNotPossible: u64 = 0;

  // royalty cut consts
  // TODO: specify the exact values
  // onenet should take 2% royalty
  const COLLECTION_ROYALTY: u16 = 3_00; // this is 3%

  const ONENET_ROYALTY_CUT: u16 = 95_00; // 95_00 is 95%
  const CLUTCHY_ROYALTY_CUT: u16 = 5_00;

  // wallet addresses to deposit royalties
  // the below values are dummy
  // TODO: add addresses here
  const ONENET_ROYALTY_ADDRESS: address = @0x1;
  const CLUTCHY_ROYALTY_ADDRESS: address = @0x2;

  // consts for mint_default
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
    img_url: Url,
    level: u64,
    level_cap: u64,
    xp: u64,
    xp_to_next_level: u64,
    season: u64,
  }

  /// Update ticket struct
  struct UpdateTicket has key, store {
    id: UID,
    // ID of the battle pass that this ticket can update
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
    // set display fields
    set_display_fields(&mut display);

    // --- transfer policy & royalties ---

    // create a transfer policy (with no policy actions)
    let (transfer_policy, transfer_policy_cap) = transfer_request::init_policy<BattlePass>(&publisher, ctx);

    // register the policy to use allowlists
    transfer_allowlist::enforce(&mut transfer_policy, &transfer_policy_cap);

    // register the transfer policy to use royalty enforcements
    royalty_strategy_bps::enforce(&mut transfer_policy, &transfer_policy_cap);

    // set royalty cuts
    let shares = vector[ONENET_ROYALTY_CUT, CLUTCHY_ROYALTY_CUT];
    let royalty_addresses = vector[ONENET_ROYALTY_ADDRESS, CLUTCHY_ROYALTY_ADDRESS];
    // take a delegated witness from the publisher
    let delegated_witness = witness::from_publisher(&publisher);
    royalty_strategy_bps::create_domain_and_add_strategy(delegated_witness,
        &mut collection,
        royalty::from_shares(
            utils::from_vec_to_map(royalty_addresses, shares), ctx,
        ),
        COLLECTION_ROYALTY,
        ctx,
    );

    // --- withdraw policy ---

    // create a withdraw policy
    let (withdraw_policy, withdraw_policy_cap) = withdraw_request::init_policy<BattlePass>(&publisher, ctx);

    // battle passes should be withdrawn to kiosks
    // register the withdraw policy to require a transfer token to withdraw from a kiosk
    transfer_token::enforce(&mut withdraw_policy, &withdraw_policy_cap);

    // --- transfers to address that published the module ---
    let publisher_address = tx_context::sender(ctx);
    transfer::public_transfer(mint_cap, publisher_address);
    transfer::public_transfer(publisher, publisher_address);
    transfer::public_transfer(display, publisher_address);
    transfer::public_transfer(transfer_policy_cap, publisher_address);
    transfer::public_transfer(withdraw_policy_cap, publisher_address);

    // --- shared objects ---
    transfer::public_share_object(collection);
    transfer::public_share_object(transfer_policy);
    transfer::public_share_object(withdraw_policy);
  }

  // === Mint functions ====

  /// mint a battle pass NFT
  public fun mint(
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, season: u64, ctx: &mut TxContext
    ): BattlePass{
      let battle_pass = BattlePass { 
        id: object::new(ctx),
        description, 
        img_url: url::new_unsafe_from_bytes(url_bytes),
        level,
        level_cap,
        xp,
        xp_to_next_level,
        season,
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
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level_cap: u64, xp_to_next_level: u64, season: u64, ctx: &mut TxContext
    ): BattlePass{
      mint(mint_cap, description, url_bytes, DEFAULT_INIT_LEVEL, level_cap, DEFAULT_INIT_XP, xp_to_next_level, season, ctx)
  }

  // mint to launchpad
  // this is for Clutchy integration
  public fun mint_to_launchpad(
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, ctx: &mut TxContext
    ){
      let battle_pass = mint(mint_cap, description, url_bytes, level, level_cap, xp, xp_to_next_level, season, ctx);
      // deposit to warehouse
      warehouse::deposit_nft(warehouse, battle_pass);
  }

  // mint to launchpad with default values
  public fun mint_default_to_launchpad(
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level_cap: u64, xp_to_next_level: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, ctx: &mut TxContext
    ){
      let battle_pass = mint_default(mint_cap, description, url_bytes, level_cap, xp_to_next_level, season, ctx);
      // deposit to warehouse
      warehouse::deposit_nft(warehouse, battle_pass);
  }

  // === Update ticket ====

  /// to create an update ticket the mint cap is needed
  /// this means the entity that can mint a battle pass can also issue a ticket to update it
  /// but the function can be altered so that the two are separate entities
  public fun create_update_ticket(
    _: &MintCap<BattlePass>, battle_pass_id: ID, new_level: u64, new_xp: u64, new_xp_to_next_level: u64, ctx: &mut TxContext
    ): UpdateTicket {
      UpdateTicket { id: object::new(ctx), battle_pass_id, new_level, new_xp, new_xp_to_next_level }
  }

  // === Update battle pass ===

  /// a battle pass holder will call this function to update the battle pass
  /// aborts if update_ticket.battle_pass_id != id of Battle Pass
  public fun update_battle_pass(
    battle_pass: &mut BattlePass, update_ticket: UpdateTicket
    ){
      // make sure that update ticket is for this battle pass
      let battle_pass_id = object::uid_to_inner(&battle_pass.id);
      assert!(battle_pass_id == update_ticket.battle_pass_id, EUpdateNotPossible);

      battle_pass.level = update_ticket.new_level;
      battle_pass.xp = update_ticket.new_xp;
      battle_pass.xp_to_next_level = update_ticket.new_xp_to_next_level;


      // delete the update ticket so that it cannot be re-used
      let UpdateTicket { id: update_ticket_id, battle_pass_id: _, new_level: _, new_xp: _, new_xp_to_next_level: _}  = update_ticket;
      object::delete(update_ticket_id)
  }

  // === exports ===

  // export the battle pass to a player's kiosk
  public fun export_battle_pass_to_kiosk(
    battle_pass: BattlePass, player_kiosk: &mut Kiosk, ctx: &mut TxContext
    ) {
    // check if OB kiosk
    ob_kiosk::assert_is_ob_kiosk(player_kiosk);

    // deposit the battle pass into the kiosk.
    ob_kiosk::deposit(player_kiosk, battle_pass, ctx);
  }

  // === private-helpers ===

  fun set_display_fields(display: &mut Display<BattlePass>) {
    let fields = vector[
      utf8(b"name"),
      utf8(b"description"),
      utf8(b"img_url"),
      utf8(b"level"),
      utf8(b"level_cap"),
      utf8(b"xp"),
      utf8(b"xp_to_next_level"),
      utf8(b"season"),
    ];
    let values = vector[
      utf8(b"Battle Pass"),
      utf8(b"{description}"),
      // img_url can also be something like `utf8(b"bushi.com/{img_url})"` or `utf8(b"ipfs/{img_url})` to save on space
      utf8(b"{img_url}"),
      utf8(b"{level}"),
      utf8(b"{level_cap}"),
      utf8(b"{xp}"),
      utf8(b"{xp_to_next_level}"),
      utf8(b"{season}"),
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
  public fun img_url(battle_pass: &BattlePass): Url {
    battle_pass.img_url
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

  #[test_only]
  public fun season(battle_pass: &BattlePass): u64 {
    battle_pass.season
  }

}