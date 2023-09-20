module bushi::cosmetic_skin {

  use std::option;
  use std::string::{utf8, String};
  use std::vector;

  use sui::display::{Self, Display};
  use sui::dynamic_field as df;
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
  const EDFKeysAndValuesNumberMismatch: u64 = 3;
  const EDynamicFieldDoesNotExist: u64 = 4;

  /// royalty cut consts
  const COLLECTION_ROYALTY: u16 = 3_00; // this is 3%

  const ONENET_ROYALTY_CUT: u16 = 95_00; // 95_00 is 95%
  const CLUTCHY_ROYALTY_CUT: u16 = 5_00;

  /// wallet addresses to deposit royalties
  /// TODO: fix/determine royalties
  const ONENET_ROYALTY_ADDRESS: address = @0x4f9dbfc5ee4a994987e810fa451cba0688f61d747ac98d091dbbadee50337c3b;
  const CLUTCHY_ROYALTY_ADDRESS: address = @0x61028a4c388514000a7de787c3f7b8ec1eb88d1bd2dbc0d3dfab37078e39630f;

  /// one-time-witness for publisher
  struct COSMETIC_SKIN has drop {}

  struct Witness has drop {}

  /// cosmetic skin struct
  struct CosmeticSkin has key, store {
    id: UID,
    name: String,
    description: String,
    image_url: String,
    level: u64,
    level_cap: u64,
    in_game: bool,
  }

  /// ticket to allow mutation of the fields of the the cosmetic skin when cosmetic skin is in-game
  /// should be created and be used after the cosmetic skin is transferred to the custodial wallet of the player
  struct UnlockUpdatesTicket has key, store {
    id: UID,
    cosmetic_skin_id: ID,
  }

  // dynamic field key for game asset id
  struct GameAssetIDKey has store, copy, drop {}

  struct StatKey has store, copy, drop { name: String }

  fun init(otw: COSMETIC_SKIN, ctx: &mut TxContext){

    // initialize collection and mint cap
    let (collection, mint_cap) = collection::create_with_mint_cap<COSMETIC_SKIN, CosmeticSkin>(&otw, option::none(), ctx);

    // claim publisher
    let publisher = package::claim(otw, ctx);

    // create display object
    let display = display::new<CosmeticSkin>(&publisher, ctx);
    // set display fields
    set_display_fields(&mut display);

    // --- transfer policy & royalties ---

    // create a transfer policy (with no policy actions)
    let (transfer_policy, transfer_policy_cap) = transfer_request::init_policy<CosmeticSkin>(&publisher, ctx);

    // register the policy to use allowlists
    transfer_allowlist::enforce(&mut transfer_policy, &transfer_policy_cap);

    // register the transfer policy to use royalty enforcements
    royalty_strategy_bps::enforce(&mut transfer_policy, &transfer_policy_cap);

    // set royalty cuts
    let shares = vector[ONENET_ROYALTY_CUT, CLUTCHY_ROYALTY_CUT];
    let royalty_addresses = vector[ONENET_ROYALTY_ADDRESS, CLUTCHY_ROYALTY_ADDRESS];
    // take a delegated witness from the publisher
    let delegated_witness = witness::from_publisher(&publisher);
    // TODO: determine royalties
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
    let (withdraw_policy, withdraw_policy_cap) = withdraw_request::init_policy<CosmeticSkin>(&publisher, ctx);

    // cosmetic skins should be withdrawn to kiosks
    // register the withdraw policy to require a transfer ticket to withdraw from a kiosk
    transfer_token::enforce(&mut withdraw_policy, &withdraw_policy_cap);

    // --- Secondary Market setup ---

    // set up orderbook for secondary market trading
    let orderbook = orderbook::new<CosmeticSkin, SUI>(
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

  /// mint a cosmetic skin
  /// by default in_game = false
  public fun mint(mint_cap: &MintCap<CosmeticSkin>, name: String, description: String, image_url: String, level: u64, level_cap: u64, ctx: &mut TxContext): CosmeticSkin {

    // make sure the level is not greater than the level cap
    assert!(level <= level_cap, ELevelGreaterThanLevelCap);

    let cosmetic_skin = CosmeticSkin {
      id: object::new(ctx),
      name,
      description,
      image_url,
      level,
      level_cap,
      in_game: false,
    };

    // emit a mint event
      mint_event::emit_mint(
      witness::from_witness(Witness {}),
      mint_cap::collection_id(mint_cap),
      &cosmetic_skin
    );

    cosmetic_skin
  }

  /// mint to launchpad
  // this is for Clutchy integration
  public fun mint_to_launchpad(
    mint_cap: &MintCap<CosmeticSkin>, name: String, description: String, image_url: String, level: u64, level_cap: u64, warehouse: &mut Warehouse<CosmeticSkin>, ctx: &mut TxContext
    ) {

      let cosmetic_skin = mint(mint_cap, name, description, image_url, level, level_cap, ctx);
      // deposit to warehouse
      warehouse::deposit_nft(warehouse, cosmetic_skin);
  }

  /// mint with stats/dynamic fields
  public fun mint_with_dfs(
    mint_cap: &MintCap<CosmeticSkin>,
    name: String,
    description: String,
    image_url: String,
    level: u64,
    level_cap: u64,
    // game_asset_id will be added as a df as well since it is not a field of the already existing Cosmetic Skin struct
    game_asset_id: String,
    stat_names: vector<String>,
    stat_values: vector<String>,
    ctx: &mut TxContext
  ): CosmeticSkin {
    
    let total = vector::length(&stat_names);
    assert!((total == vector::length(&stat_values)), EDFKeysAndValuesNumberMismatch);

    // mint the cosmetic skin
    let cosmetic_skin = mint(
      mint_cap,
      name,
      description,
      image_url,
      level,
      level_cap,
      ctx,
    );

    // add game_asset_id as a dynamic field
    df::add<GameAssetIDKey, String>(&mut cosmetic_skin.id, GameAssetIDKey { }, game_asset_id);

    // add the stats as dynamic fields
    let i = 0;
    while (i < total) {
      let name = *vector::borrow(&stat_names, i);
      let value = *vector::borrow(&stat_values, i);
      df::add<StatKey, String>(&mut cosmetic_skin.id, StatKey { name }, value);
      i = i + 1;
    };

    cosmetic_skin
  }

  // === Unlock updates ticket ====

  /// create an UnlockUpdatesTicket
  /// @param cosmetic_skin_id: the id of the cosmetic skin this ticket is issued for
  public fun create_unlock_updates_ticket(
    _: &MintCap<CosmeticSkin>, cosmetic_skin_id: ID, ctx: &mut TxContext
    ): UnlockUpdatesTicket {

    UnlockUpdatesTicket {
      id: object::new(ctx),
      cosmetic_skin_id
    }
  }

  // === Unlock updates ===

  /// the user's custodial wallet will call this function to unlock updates for their cosmetic skin
  /// aborts if the unlock_updates_ticket is not issued for this cosmetic skin
  public fun unlock_updates(cosmetic_skin: &mut CosmeticSkin, unlock_updates_ticket: UnlockUpdatesTicket){

      // make sure unlock_updates_ticket is for this cosmetic skin
      assert!(unlock_updates_ticket.cosmetic_skin_id == object::uid_to_inner(&cosmetic_skin.id), EWrongToken);
      
      // set in_game to true
      cosmetic_skin.in_game = true;

      // delete unlock_updates_ticket
      let UnlockUpdatesTicket { id: in_game_token_id, cosmetic_skin_id: _ } = unlock_updates_ticket;
      object::delete(in_game_token_id);
  }

  // === Update cosmetic skin level ===

  /// update cosmetic skin level
  /// aborts when in_game is false (cosmetic skin is not in-game)
  /// or when the new_level > level_cap
  public fun update(cosmetic_skin: &mut CosmeticSkin, new_level: u64){
    // make sure the cosmetic skin is in-game
    assert!(cosmetic_skin.in_game, ECannotUpdate);

    // make sure the new level is not greater than the level cap
    assert!(new_level <= cosmetic_skin.level_cap, ELevelGreaterThanLevelCap);

    cosmetic_skin.level = new_level;
  }

  // update dynamic fields of stats only if in_game = true
  // for each field name, if it does not exist, we add a field with this name
  // aborts if in_game = false
  // or stats_names and stats_values have different length
  public fun update_or_add_stats(
    cosmetic_skin: &mut CosmeticSkin,
    stat_names: vector<String>,
    // TODO: determine if below should be u64 or String
    stat_values: vector<String>,
  ) {

    assert!(cosmetic_skin.in_game == true, ECannotUpdate);

    let total = vector::length(&stat_names);

    assert!(total == vector::length(&stat_values), EDFKeysAndValuesNumberMismatch);

    let i = 0;
    while (i < total){
      let name = *vector::borrow(&stat_names, i);
      let stat_key = StatKey { name };
      let new_value = *vector::borrow<String>(&stat_values, i);
      // if a df with this key already exists
      if (df::exists_<StatKey>(&cosmetic_skin.id, stat_key)) {
        let old_value = df::borrow_mut<StatKey, String>(&mut cosmetic_skin.id, stat_key );
        *old_value = new_value;
      } else {
        df::add<StatKey, String>(&mut cosmetic_skin.id, stat_key, new_value);
      };
      i = i + 1;
    }
  }

  // remove some of the stats
  // aborts if the stats we want to remove do not exist
  public fun remove_stats(
    cosmetic_skin: &mut CosmeticSkin,
    stat_names: vector<String>,
  ) {

    assert!(cosmetic_skin.in_game == true, ECannotUpdate);

    let total = vector::length(&stat_names);
    let i = 0;
    while (i < total) {
      let name = *vector::borrow<String>(&stat_names, i);
      let stat_key = StatKey { name };
      // if dynamic field with key `key` does not exist, throw an error
      assert!(df::exists_<StatKey>(&cosmetic_skin.id, stat_key), EDynamicFieldDoesNotExist);
      df::remove<StatKey, u64>(&mut cosmetic_skin.id, stat_key);
      i = i + 1;
    };
  }

  /// Update or add to a Cosmetic Skin a game asset ID
  public fun update_or_add_game_asset_id(
    cosmetic_skin: &mut CosmeticSkin,
    new_game_asset_id: String,
  ) {

    // make sure Cosmetic Skin is in-game
    assert!((cosmetic_skin.in_game == true), ECannotUpdate);

    let game_asset_id_key = GameAssetIDKey {};
    // check if cosmetic skin has a game asset id, if yes update, if not add
    if (df::exists_<GameAssetIDKey>(&cosmetic_skin.id, game_asset_id_key)) {
      // update the game asset id
      let old_game_asset_id = df::borrow_mut<GameAssetIDKey, String>( &mut cosmetic_skin.id, game_asset_id_key);
      *old_game_asset_id = new_game_asset_id;
    } else {
      df::add<GameAssetIDKey, String>(&mut cosmetic_skin.id, game_asset_id_key, new_game_asset_id);
    };
  }

  // remove game_asset_id
  // aborts if the cosmetic skin does not have that field
  public fun remove_game_asset_id(
    cosmetic_skin: &mut CosmeticSkin,
  ) {

    // make sure Cosmetic Skin is in-game
    assert!((cosmetic_skin.in_game == true), ECannotUpdate);

    let game_asset_id_key = GameAssetIDKey {};

    // check that cosmetic skin has that field
    assert!(df::exists_<GameAssetIDKey>(&cosmetic_skin.id, game_asset_id_key), EDynamicFieldDoesNotExist);
    // remove the field
    df::remove<GameAssetIDKey, String>(&mut cosmetic_skin.id, game_asset_id_key);
  }

  // returns game asset id of cosmetic skin
  // aborts if game asset id df does not exist
  public fun get_game_asset_id(
    cosmetic_skin: &CosmeticSkin,
  ): String {
    
    let game_asset_id_key = GameAssetIDKey {};

    assert!(df::exists_(&cosmetic_skin.id, game_asset_id_key), EDynamicFieldDoesNotExist);

    *df::borrow<GameAssetIDKey, String>(&cosmetic_skin.id, game_asset_id_key)
  }

  // returns value of stat of cosmetic skin
  // aborts if stat does not exist
  public fun get_stat_value(
    cosmetic_skin: &CosmeticSkin,
    stat_name: String,
  ): String {

    let stat_key = StatKey { name: stat_name };

    // make sure stat exists
    assert!(df::exists_<StatKey>(&cosmetic_skin.id, stat_key), EDynamicFieldDoesNotExist);

    *df::borrow<StatKey, String>(&cosmetic_skin.id, stat_key)
  }

  // === exports ===

  /// export the cosmetic skin to a player's kiosk
  public fun export_to_kiosk(
    cosmetic_skin: CosmeticSkin, player_kiosk: &mut Kiosk, ctx: &mut TxContext
    ) {
    // check if OB kiosk
    ob_kiosk::assert_is_ob_kiosk(player_kiosk);

    // set in_game to false
    cosmetic_skin.in_game = false;

    // deposit the cosmetic skin into the kiosk.
    ob_kiosk::deposit(player_kiosk, cosmetic_skin, ctx);
  }

  /// lock updates
  // this can be called by the player's custodial wallet before transferring - if the export_to_kiosk function is not called
  // if it is not in-game, this function will do nothing 
  public fun lock_updates(
    cosmetic_skin: &mut CosmeticSkin
    ) {

    // set in_game to false
    cosmetic_skin.in_game = false;

  }

  // === private-helpers ===

  fun set_display_fields(display: &mut Display<CosmeticSkin>){

    let fields = vector[
      utf8(b"name"),
      utf8(b"description"),
      utf8(b"image_url"),
      utf8(b"level"),
      utf8(b"level_cap"),
    ];
    
    let values = vector[
      utf8(b"{name}"),
      utf8(b"{description}"),
      utf8(b"{image_url}"),
      utf8(b"{level}"),
      utf8(b"{level_cap}"),
    ];

    display::add_multiple<CosmeticSkin>(display, fields, values);
  }

  /// Player calls this function from their external wallet.
  /// Needs a TransferToken in order to withdraw a Cosmetic Skin from their kiosk.
  public fun import_cosmetic_skin_to_cw(
    transfer_token: TransferToken<CosmeticSkin>,
    player_kiosk: &mut Kiosk, 
    cosmeticSkin_id: ID, 
    withdraw_policy: &Policy<WithNft<CosmeticSkin, WITHDRAW_REQ>>, 
    ctx: &mut TxContext
  ) {
    let (cosmeticSkin, withdraw_request) = ob_kiosk::withdraw_nft_signed<CosmeticSkin>(player_kiosk, cosmeticSkin_id, ctx);

    // Transfers NFT to the custodial wallet address
    transfer_token::confirm(cosmeticSkin, transfer_token, withdraw_request::inner_mut(&mut withdraw_request));
    withdraw_request::confirm<CosmeticSkin>(withdraw_request, withdraw_policy);

  }

  #[test_only]
  public fun init_test(ctx: &mut TxContext){
      let otw = COSMETIC_SKIN {};
      init(otw, ctx);
  }

  #[test_only]
  public fun id(cosmetic_skin: &CosmeticSkin): ID {
    object::uid_to_inner(&cosmetic_skin.id)
  }

  #[test_only]
  public fun name(cosmetic_skin: &CosmeticSkin): String {
    cosmetic_skin.name
  }

  #[test_only]
  public fun description(cosmetic_skin: &CosmeticSkin): String {
    cosmetic_skin.description
  }

  #[test_only]
  public fun image_url(cosmetic_skin: &CosmeticSkin): String {
    cosmetic_skin.image_url
  }

  #[test_only]
  public fun level(cosmetic_skin: &CosmeticSkin): u64 {
    cosmetic_skin.level
  }

  #[test_only]
  public fun level_cap(cosmetic_skin: &CosmeticSkin): u64 {
    cosmetic_skin.level_cap
  }

  #[test_only]
  public fun in_game(cosmetic_skin: &CosmeticSkin): bool {
    cosmetic_skin.in_game
  }
}