module bushi::item {

  use std::option;
  use std::string::{utf8, String};
  use std::vector;

  use sui::display::{Self, Display};
  use sui::kiosk::Kiosk;
  use sui::object::{Self, ID, UID};
  use sui::package;
  use sui::sui::SUI;
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};

  // --- OB imports ---

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
  const EItemNotInGame: u64 = 3;
  const EDFKeysAndValuesNumberMismatch: u64 = 4;

  /// royalty cut consts
  const COLLECTION_ROYALTY: u16 = 3_00; // this is 3%

  const ONENET_ROYALTY_CUT: u16 = 100_00; // 95_00 is 95%

  /// wallet addresses to deposit royalties
  /// TODO: fix/determine royalties
  const ONENET_ROYALTY_ADDRESS: address = @0x4f9dbfc5ee4a994987e810fa451cba0688f61d747ac98d091dbbadee50337c3b;

  /// one-time-witness for publisher
  struct ITEM has drop {}

  struct Witness has drop {}

  /// item struct
  struct Item has key, store {
    id: UID,
    name: String,
    description: String,
    image_url: String,
    level: u64,
    level_cap: u64,
    game_asset_id: String,
    stat_names: vector<String>,
    stat_values: vector<String>,
    in_game: bool,
  }

  /// ticket to allow mutation of the fields of the the item when item is in-game
  /// should be created and be used after the item is transferred to the custodial wallet of the player
  struct UnlockUpdatesTicket has key, store {
    id: UID,
    item_id: ID,
  }

  fun init(otw: ITEM, ctx: &mut TxContext){

    // initialize collection and mint cap
    let (collection, mint_cap) = collection::create_with_mint_cap<ITEM, Item>(&otw, option::none(), ctx);

    // claim publisher
    let publisher = package::claim(otw, ctx);

    // create display object
    let display = display::new<Item>(&publisher, ctx);
    // set display fields
    set_display_fields(&mut display);

    // --- transfer policy & royalties ---

    // create a transfer policy (with no policy actions)
    let (transfer_policy, transfer_policy_cap) = transfer_request::init_policy<Item>(&publisher, ctx);

    // register the policy to use allowlists
    transfer_allowlist::enforce(&mut transfer_policy, &transfer_policy_cap);

    // register the transfer policy to use royalty enforcements
    royalty_strategy_bps::enforce(&mut transfer_policy, &transfer_policy_cap);

    // set royalty cuts
    let shares = vector[ONENET_ROYALTY_CUT];
    let royalty_addresses = vector[ONENET_ROYALTY_ADDRESS];
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
    let (withdraw_policy, withdraw_policy_cap) = withdraw_request::init_policy<Item>(&publisher, ctx);

    // items should be withdrawn to kiosks
    // register the withdraw policy to require a transfer ticket to withdraw from a kiosk
    transfer_token::enforce(&mut withdraw_policy, &withdraw_policy_cap);

    // --- Secondary Market setup ---

    // set up orderbook for secondary market trading
    let orderbook = orderbook::new<Item, SUI>(
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

  /// mint a item
  /// by default in_game = false
  public fun mint(mint_cap: &MintCap<Item>, name: String, description: String, image_url: String, level: u64, level_cap: u64, game_asset_id: String, stat_names: vector<String>, stat_values: vector<String>, in_game: bool, ctx: &mut TxContext): Item {

    // make sure the level is not greater than the level cap
    assert!(level <= level_cap, ELevelGreaterThanLevelCap);

    let item = Item {
      id: object::new(ctx),
      name,
      description,
      image_url,
      level,
      level_cap,
      game_asset_id,
      stat_names,
      stat_values,
      in_game,
    };

    // emit a mint event
      mint_event::emit_mint(
      witness::from_witness(Witness {}),
      mint_cap::collection_id(mint_cap),
      &item
    );

    item
  }

  // === Unlock updates ticket ====

  /// create an UnlockUpdatesTicket
  /// @param item_id: the id of the item this ticket is issued for
  public fun create_unlock_updates_ticket(
    _: &MintCap<Item>, item_id: ID, ctx: &mut TxContext
    ): UnlockUpdatesTicket {

    UnlockUpdatesTicket {
      id: object::new(ctx),
      item_id
    }
  }

  // === Unlock updates ===

  /// the user's custodial wallet will call this function to unlock updates for their item
  /// aborts if the unlock_updates_ticket is not issued for this item
  public fun unlock_updates(item: &mut Item, unlock_updates_ticket: UnlockUpdatesTicket){

      // make sure unlock_updates_ticket is for this item
      assert!(unlock_updates_ticket.item_id == object::uid_to_inner(&item.id), EWrongToken);
      
      // set in_game to true
      item.in_game = true;

      // delete unlock_updates_ticket
      let UnlockUpdatesTicket { id: in_game_token_id, item_id: _ } = unlock_updates_ticket;
      object::delete(in_game_token_id);
  }

  // === Update item level ===

  /// update item level
  /// aborts when in_game is false (item is not in-game)
  /// or when the new_level > level_cap
  public fun update(item: &mut Item, new_level: u64){
    // make sure the item is in-game
    assert!(item.in_game, ECannotUpdate);

    // make sure the new level is not greater than the level cap
    assert!(new_level <= item.level_cap, ELevelGreaterThanLevelCap);

    item.level = new_level;
  }

  public fun update_stats(
    item: &mut Item,
    stat_names: vector<String>,
    stat_values: vector<String>,
  ) {

    assert!(in_game(item) == true, ECannotUpdate);

    let total = vector::length(&stat_names);

    assert!(total == vector::length(&stat_values), EDFKeysAndValuesNumberMismatch);

    // let mut_uid = item::cw_get_mut_uid(item);

    item.stat_names = stat_names;
    item.stat_values = stat_values;

    // let i = 0;
    // while (i < total){
    //   let name = *vector::borrow(&stat_names, i);
    //   let stat_key = StatKey { name };
    //   let new_value = *vector::borrow<String>(&stat_values, i);

    //   // if a df with this key already exists
    //   if (df::exists_<StatKey>(mut_uid, stat_key)) {
    //     let old_value = df::borrow_mut<StatKey, String>(mut_uid, stat_key );
    //     *old_value = new_value;
    //   } else if(add_stats) {
    //     df::add<StatKey, String>(mut_uid, stat_key, new_value);
    //   };
    //   i = i + 1;
    // }
  }

  // === exports ===

  /// export the item to a player's kiosk
  public fun export_to_kiosk(
    item: Item, player_kiosk: &mut Kiosk, ctx: &mut TxContext
    ) {
    // check if OB kiosk
    ob_kiosk::assert_is_ob_kiosk(player_kiosk);

    // set in_game to false
    item.in_game = false;

    // deposit the item into the kiosk.
    ob_kiosk::deposit(player_kiosk, item, ctx);
  }

  /// lock updates
  // this can be called by the player's custodial wallet before transferring - if the export_to_kiosk function is not called
  // if it is not in-game, this function will do nothing 
  public fun lock_updates(
    item: &mut Item
    ) {

    // set in_game to false
    item.in_game = false;

  }

  // === private-helpers ===

  fun set_display_fields(display: &mut Display<Item>){

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

    display::add_multiple<Item>(display, fields, values);
  }

  /// Player calls this function from their external wallet.
  /// Needs a TransferToken in order to withdraw a item from their kiosk.
  public fun import_item_to_cw(
    transfer_token: TransferToken<Item>,
    player_kiosk: &mut Kiosk, 
    item_id: ID, 
    withdraw_policy: &Policy<WithNft<Item, WITHDRAW_REQ>>, 
    ctx: &mut TxContext
  ) {
    let (item, withdraw_request) = ob_kiosk::withdraw_nft_signed<Item>(player_kiosk, item_id, ctx);

    // Transfers NFT to the custodial wallet address
    transfer_token::confirm(item, transfer_token, withdraw_request::inner_mut(&mut withdraw_request));
    withdraw_request::confirm<Item>(withdraw_request, withdraw_policy);

  }

  public fun burn(item: Item) {
    let Item {
      id,
      name: _,
      description: _,
      image_url: _,
      level: _,
      level_cap: _,
      game_asset_id: _,
      stat_names: _,
      stat_values: _,
      in_game: _,
    } = item;

    object::delete(id);
  }

  // === Accesors ===

  public fun admin_get_mut_uid(
    _: &MintCap<Item>,
    item: &mut Item
  ): &mut UID {
    &mut item.id
  }

  /// get a mutable reference of UID of item
  /// only if item is in-game
  /// (aborts otherwise)
  public fun cw_get_mut_uid(
    item: &mut Item,
  ): &mut UID {

    assert!(item.in_game == true, EItemNotInGame);

    &mut item.id
  }

  public fun get_immut_uid(
    item: &Item
  ): &UID {
    &item.id
  }

  public fun in_game(
    item: &Item,
  ): bool {
    item.in_game
  }

  #[test_only]
  public fun init_test(ctx: &mut TxContext){
      let otw = ITEM {};
      init(otw, ctx);
  }

  #[test_only]
  public fun id(item: &Item): ID {
    object::uid_to_inner(&item.id)
  }

  #[test_only]
  public fun name(item: &Item): String {
    item.name
  }

  #[test_only]
  public fun description(item: &Item): String {
    item.description
  }

  #[test_only]
  public fun image_url(item: &Item): String {
    item.image_url
  }

  #[test_only]
  public fun level(item: &Item): u64 {
    item.level
  }

  #[test_only]
  public fun level_cap(item: &Item): u64 {
    item.level_cap
  }

  #[test_only]
  public fun stat_names(item: &Item): vector<String> {
    item.stat_names
  }

  #[test_only]
  public fun stat_values(item: &Item): vector<String> {
    item.stat_values
  }
}