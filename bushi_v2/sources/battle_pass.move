module bushi::battle_pass{

  use std::string::{String, utf8};
  use std::option;

  use sui::display::{Self, Display};
  use sui::kiosk::Kiosk;
  use sui::object::{Self, ID, UID};
  use sui::package;
  use sui::sui::SUI;
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};

  // --- OB imports ---

  use ob_launchpad::warehouse::{Self, Warehouse};

  use nft_protocol::collection;
  use nft_protocol::mint_cap::{Self, MintCap};
  use nft_protocol::mint_event;
  use nft_protocol::royalty;
  use nft_protocol::royalty_strategy_bps;
  use nft_protocol::transfer_allowlist;
  use nft_protocol::transfer_token::{Self, TransferToken};

  use ob_kiosk::ob_kiosk;

  use ob_permissions::witness;

  use ob_request::transfer_request;
  use ob_request::withdraw_request;
  use ob_request::request::{Policy, WithNft};
  use ob_request::withdraw_request::{WITHDRAW_REQ};


 

  use ob_utils::utils;

  use liquidity_layer_v1::orderbook;
  

  /// errors
  const EWrongToken: u64 = 0;
  const ECannotUpdate: u64 = 1;
  const ELevelGreaterThanLevelCap: u64 = 2;

  /// royalty cut consts
  // TODO: specify the exact values
  // onenet should take 2% royalty
  const COLLECTION_ROYALTY: u16 = 3_00; // this is 3%

  const ONENET_ROYALTY_CUT: u16 = 95_00; // 95_00 is 95%
  const CLUTCHY_ROYALTY_CUT: u16 = 5_00;

  /// wallet addresses to deposit royalties
  // the below values are dummy
  // TODO: add addresses here
  const ONENET_ROYALTY_ADDRESS: address = @0x4f9dbfc5ee4a994987e810fa451cba0688f61d747ac98d091dbbadee50337c3b;
  const CLUTCHY_ROYALTY_ADDRESS: address = @0x61028a4c388514000a7de787c3f7b8ec1eb88d1bd2dbc0d3dfab37078e39630f;

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
    image_url: String,
    level: u64,
    level_cap: u64,
    xp: u64,
    xp_to_next_level: u64,
    rarity: u64,
    season: u64,
    in_game: bool,
  }

  /// ticket to allow mutation of the fields of the the battle pass when battle pass is in-game
  /// should be created and be used after the battle pass is transferred to the custodial wallet of the player
  struct UnlockUpdatesTicket has key, store {
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
    // register the withdraw policy to require a transfer ticket to withdraw from a kiosk
    transfer_token::enforce(&mut withdraw_policy, &withdraw_policy_cap);

    // --- Secondary Market setup ---

    // set up rderbook for secondary market trading
    let orderbook = orderbook::new<BattlePass, SUI>(
        delegated_witness, &transfer_policy, orderbook::no_protection(), ctx,
    );
    orderbook::share(orderbook);

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
    mint_cap: &MintCap<BattlePass>, description: String, image_url: String, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, rarity: u64, season: u64, in_game: bool, ctx: &mut TxContext
    ): BattlePass{

    // make sure the level is not greater than the level cap
    assert!(level <= level_cap, ELevelGreaterThanLevelCap);

      let battle_pass = BattlePass { 
        id: object::new(ctx),
        description, 
        image_url,
        level,
        level_cap,
        xp,
        xp_to_next_level,
        rarity,
        season,
        in_game,
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
    mint_cap: &MintCap<BattlePass>, description: String, image_url: String, level_cap: u64, xp_to_next_level: u64, rarity: u64, season: u64, in_game: bool, ctx: &mut TxContext
    ): BattlePass{

      mint(mint_cap, description, image_url, DEFAULT_INIT_LEVEL, level_cap, DEFAULT_INIT_XP, xp_to_next_level, rarity, season, in_game, ctx)
  }

  /// mint to launchpad
  // this is for Clutchy integration
  public fun mint_to_launchpad(
    mint_cap: &MintCap<BattlePass>, description: String, image_url: String, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, rarity: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, ctx: &mut TxContext
    ){

      let battle_pass = mint(mint_cap, description, image_url, level, level_cap, xp, xp_to_next_level, rarity, season, false, ctx);
      // deposit to warehouse
      warehouse::deposit_nft(warehouse, battle_pass);
  }

  /// mint to launchpad with default values
  public fun mint_default_to_launchpad(
    mint_cap: &MintCap<BattlePass>, description: String, image_url: String, level_cap: u64, xp_to_next_level: u64, rarity: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, ctx: &mut TxContext
    ){

      let battle_pass = mint_default(mint_cap, description, image_url, level_cap, xp_to_next_level, rarity, season, false, ctx);
      // deposit to warehouse
      warehouse::deposit_nft(warehouse, battle_pass);
  }

  // === Unlock updates ticket ====

  /// create an UnlockUpdatesTicket
  /// @param battle_pass_id: the id of the battle pass this ticket is issued for
  public fun create_unlock_updates_ticket(
    _: &MintCap<BattlePass>, battle_pass_id: ID, ctx: &mut TxContext
    ): UnlockUpdatesTicket {

    UnlockUpdatesTicket {
      id: object::new(ctx),
      battle_pass_id,
    }
  }

  // === Unlock updates ===

  /// the user's custodial wallet will call this function to unlock updates for their battle pass
  /// aborts if the unlock_updates_ticket is not issued for this battle pass
  public fun unlock_updates(battle_pass: &mut BattlePass, unlock_updates_ticket: UnlockUpdatesTicket){

      // make sure unlock_updates_ticket is for this battle pass
      assert!(unlock_updates_ticket.battle_pass_id == object::uid_to_inner(&battle_pass.id), EWrongToken);
      
      // set in_game to true
      battle_pass.in_game = true;

      // delete unlock_updates_ticket
      let UnlockUpdatesTicket { id: in_game_token_id, battle_pass_id: _ } = unlock_updates_ticket;
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
    assert!(new_level <= battle_pass.level_cap, ELevelGreaterThanLevelCap);

    battle_pass.level = new_level;
    battle_pass.xp = new_xp;
    battle_pass.xp_to_next_level = new_xp_to_next_level;
  }

  // === Dynamic field features ===

  public entry fun init_borrow_policy(
    publisher: &sui::package::Publisher,
    ctx: &mut sui::tx_context::TxContext,
  ) {
    let (borrow_policy, borrow_policy_cap) =
        ob_request::borrow_request::init_policy<BattlePass>(publisher, ctx);

    sui::transfer::public_share_object(borrow_policy);
    sui::transfer::public_transfer(borrow_policy_cap, sui::tx_context::sender(ctx));
  }

  public fun set_image_url(
    _delegated_witness: ob_permissions::witness::Witness<BattlePass>,
    nft: &mut BattlePass,
    image_url: String,
  ) {
    nft.image_url = image_url;
  }

  public entry fun set_image_url_in_kiosk(
    publisher: &sui::package::Publisher,
    kiosk: &mut sui::kiosk::Kiosk,
    nft_id: sui::object::ID,
    image_url: String,
    policy: &ob_request::request::Policy<ob_request::request::WithNft<BattlePass, ob_request::borrow_request::BORROW_REQ>>,
    ctx: &mut sui::tx_context::TxContext,
  ) {
    let delegated_witness = ob_permissions::witness::from_publisher(publisher);
    let borrow = ob_kiosk::ob_kiosk::borrow_nft_mut<BattlePass>(kiosk, nft_id, std::option::none(), ctx);

    let nft: &mut BattlePass = ob_request::borrow_request::borrow_nft_ref_mut(delegated_witness, &mut borrow);
    set_image_url(delegated_witness, nft, image_url);

    ob_kiosk::ob_kiosk::return_nft<Witness, BattlePass>(kiosk, borrow, policy);
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

  /// lock updates
  // this should be called by the player's custodial wallet before transferring
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
      utf8(b"image_url"),
      utf8(b"level"),
      utf8(b"level_cap"),
      utf8(b"xp"),
      utf8(b"xp_to_next_level"),
      utf8(b"rarity"),
      utf8(b"season"),
    ];
    let values = vector[
      utf8(b"Battle Pass"),
      utf8(b"{description}"),
      // img_url can also be something like `utf8(b"bushi.com/{img_url})"` or `utf8(b"ipfs/{img_url})` to save on space
      utf8(b"{image_url}"),
      utf8(b"{level}"),
      utf8(b"{level_cap}"),
      utf8(b"{xp}"),
      utf8(b"{xp_to_next_level}"),
      utf8(b"{rarity}"),
      utf8(b"{season}"),
    ];
    display::add_multiple<BattlePass>(display, fields, values);
  }

  /// Player calls this function from their external wallet.
  /// Needs a TransferToken in order to withdraw a Battlepass from their kiosk.
  public fun import_battlepass_to_cw(
    transfer_token: TransferToken<BattlePass>,
    player_kiosk: &mut Kiosk, 
    battlepass_id: ID, 
    withdraw_policy: &Policy<WithNft<BattlePass, WITHDRAW_REQ>>, 
    ctx: &mut TxContext
  ) {
    let (battlepass, withdraw_request) = ob_kiosk::withdraw_nft_signed<BattlePass>(player_kiosk, battlepass_id, ctx);
    
    // Transfers NFT to the custodial wallet address
    transfer_token::confirm(battlepass, transfer_token, withdraw_request::inner_mut(&mut withdraw_request));
    withdraw_request::confirm<BattlePass>(withdraw_request, withdraw_policy);

  }

  public fun burn(battle_pass: BattlePass) {
    let BattlePass {
      id,
      description: _,
      image_url: _,
      level: _,
      level_cap: _,
      xp: _,
      xp_to_next_level: _,
      rarity: _,
      season: _,
      in_game: _,
    } = battle_pass;

    object::delete(id);
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
  public fun image_url(battle_pass: &BattlePass): String {
    battle_pass.image_url
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
  public fun rarity(battle_pass: &BattlePass): u64 {
    battle_pass.rarity
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