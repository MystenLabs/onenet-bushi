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


  /// errors
  const EWrongToken: u64 = 0;
  const ECannotUpdate: u64 = 1;
  const ELevelGreaterOrEqualThanLevelCap: u64 = 2;

  /// royalty cut consts
  // TODO: specify the exact values
  // onenet should take 2% royalty
  const COLLECTION_ROYALTY: u16 = 3_00; // this is 3%

  const ONENET_ROYALTY_CUT: u16 = 95_00; // 95_00 is 95%
  const CLUTCHY_ROYALTY_CUT: u16 = 5_00;

  /// wallet addresses to deposit royalties
  // the below values are dummy
  // TODO: add addresses here
  const ONENET_ROYALTY_ADDRESS: address = @0x1;
  const CLUTCHY_ROYALTY_ADDRESS: address = @0x2;

  /// consts for mint_default
  const DEFAULT_INIT_LEVEL: u64 = 1;
  const DEFAULT_INIT_XP: u64 = 0;

  /// One-time-witness
  struct BATTLE_PASS has drop {}

  /// Witness struct for Witness-Protected actions
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
    in_game: bool,
  }

  /// token to allow mutation of the fields of the the battle pass when battle pass is in-game
  /// should be created and be used after the battle pass is transferred to the custodial wallet of the player
  struct InGameToken has key, store {
    id: UID,
    battle_pass_id: ID,
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
  /// by default, in_game = false
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
        in_game: false,
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
  // we can specify and change default values
  public fun mint_default(
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level_cap: u64, xp_to_next_level: u64, season: u64, ctx: &mut TxContext
    ): BattlePass{

      mint(mint_cap, description, url_bytes, DEFAULT_INIT_LEVEL, level_cap, DEFAULT_INIT_XP, xp_to_next_level, season, ctx)
  }

  /// mint to launchpad
  // this is for Clutchy integration
  public fun mint_to_launchpad(
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, ctx: &mut TxContext
    ){

      let battle_pass = mint(mint_cap, description, url_bytes, level, level_cap, xp, xp_to_next_level, season, ctx);
      // deposit to warehouse
      warehouse::deposit_nft(warehouse, battle_pass);
  }

  /// mint to launchpad with default values
  public fun mint_default_to_launchpad(
    mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level_cap: u64, xp_to_next_level: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, ctx: &mut TxContext
    ){

      let battle_pass = mint_default(mint_cap, description, url_bytes, level_cap, xp_to_next_level, season, ctx);
      // deposit to warehouse
      warehouse::deposit_nft(warehouse, battle_pass);
  }

  // === In-game token ====

  /// create an InGameToken
  /// @param battle_pass_id: the id of the battle pass this token is for
  public fun create_in_game_token(
    _: &MintCap<BattlePass>, battle_pass_id: ID, ctx: &mut TxContext
    ): InGameToken {

    InGameToken {
      id: object::new(ctx),
      battle_pass_id,
    }
  }

// === Unlock updates ===

  /// the user's custodial wallet will call this function to unlock updates for their battle pass
  public fun unlock_updates(battle_pass: &mut BattlePass, in_game_token: InGameToken){

      // make sure in_game_token is for this battle pass
      assert!(in_game_token.battle_pass_id == object::uid_to_inner(&battle_pass.id), EWrongToken);
      
      // set in_game to true
      battle_pass.in_game = true;

      // delete in_game_token
      let InGameToken { id: in_game_token_id, battle_pass_id: _ } = in_game_token;
      object::delete(in_game_token_id);
  }

  // === Update battle pass ===

  /// update battle pass level, xp, xp_to_next_level
  /// aborts when in_game is false (battle pass is not in-game)
  /// or when new_level > level_cap
  public fun update(battle_pass: &mut BattlePass, new_level: u64, new_xp: u64, new_xp_to_next_level: u64){
    // make sure the battle_pass is in-game
    assert!(battle_pass.in_game, ECannotUpdate);

    // make sure new_level is not greater than level_cap
    assert!(new_level <= battle_pass.level_cap, ELevelGreaterOrEqualThanLevelCap);

    battle_pass.level = new_level;
    battle_pass.xp = new_xp;
    battle_pass.xp_to_next_level = new_xp_to_next_level;
  }


  // === exports ===

  /// export the battle pass to a player's kiosk
  public fun export_to_kiosk(
    battle_pass: BattlePass, player_kiosk: &mut Kiosk, ctx: &mut TxContext
    ){
    // check if OB kiosk
    ob_kiosk::assert_is_ob_kiosk(player_kiosk);

    // set in_game to false
    battle_pass.in_game = false;

    // deposit the battle pass into the kiosk.
    ob_kiosk::deposit(player_kiosk, battle_pass, ctx);
  }

  /// lock in-game updates
  // this can be called by the player's custodial wallet before transferring - if the export_to_kiosk function is not called
  // if it is not in-game, this function will do nothing 
  public fun lock_updates(
    battle_pass: &mut BattlePass
    ) {

    // set in_game to false
    battle_pass.in_game = false;

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

  #[test_only]
  public fun in_game(battle_pass: &BattlePass): bool {
    battle_pass.in_game
  }

}