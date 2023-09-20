module bushi::stats{

  // === Sui and std imports ===

  use std::option;
  use std::string::String;
  use std::vector;

  use sui::dynamic_field as df;
  use sui::object::{Self, UID};
  use sui::package;
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};

  // === OB imports ===

  use nft_protocol::collection;
  use nft_protocol::mint_cap::{MintCap};

  // === error codes ===
  const EDFKeysAndValuesNumberMismatch: u64 = 0;
  const EStatsNotInGame: u64 = 1;

  // one-time witness
  struct STATS has drop {}

  struct Stats has key, store{
    id: UID,
    name: String, 
    description: String,
    image_url: String,
    level: u64,
    level_cap: u64,
    // id associated with backend
    item_id: String,
    in_game: bool,
  }

  fun init(otw: STATS, ctx: &mut TxContext){

    // initialize collection and mint cap
    let (collection, mint_cap) = collection::create_with_mint_cap<STATS, Stats>(&otw, option::none(), ctx);
    
    // claim package publisher and TODO: create display
    let publisher = package::claim(otw, ctx);

    // --- transfers to address that published the module ---
    let publisher_address = tx_context::sender(ctx);
    transfer::public_transfer(mint_cap, publisher_address);
    transfer::public_transfer(publisher, publisher_address);


    // --- shared objects ---
    transfer::public_share_object(collection);

  }

  // if no dynamic fields, pass an empty vector. We can add and remove dynamic fields later, in (TODO) function
  fun mint(
    _cap: &MintCap<Stats>,
    name: String,
    description: String,
    image_url: String,
    level: u64,
    level_cap: u64,
    item_id: String,
    in_game: bool,
    dynamic_field_keys: vector<String>,
    // TODO: determine if dynamic field values should be u64 or String
    dynamic_field_values: vector<u64>,
    ctx: &mut TxContext,
  ): Stats {

    // make sure that key and value vectors have the same length
    assert!(vector::length(&dynamic_field_keys) == vector::length(&dynamic_field_values), EDFKeysAndValuesNumberMismatch);

    // create the Stats object
    let stats = Stats {
      id: object::new(ctx),
      name,
      description,
      image_url,
      level,
      level_cap,
      item_id,
      in_game,
    };

    // add the dynamic fields
    let df_number = vector::length(&dynamic_field_keys);
    let i = 0;
    while (i < df_number) {
      let key = *vector::borrow(&dynamic_field_keys, i);
      let value = *vector::borrow(&dynamic_field_values, i);
      df::add<String, u64>(&mut stats.id, key, value);
      i = i + 1;
    };

    // return the Stats NFT
    stats
  }

  // update the Stats object attributes: image_url and level
  // this is possible only if `in_game` is true
  public fun update_stats_attributes(
    stats: &mut Stats,
    new_image_url: String,
    new_level: u64,
  ) {

    assert!(stats.in_game == true, EStatsNotInGame);

    stats.image_url = new_image_url;
    stats.level = new_level;
  }

  // update dynamic fields of stats only if in_game = true
  // for each field name, if it does not exist, we add a field with this name
  public fun update_or_add_stat_dfs(
    stats: &mut Stats,
    dynamic_field_keys: vector<String>,
    // TODO: determine if below should be u64 or String
    dynamic_field_values: vector<u64>,
  ) {

    assert!(stats.in_game == true, EStatsNotInGame);

    let total = vector::length(&dynamic_field_keys);

    assert!(total == vector::length(&dynamic_field_values), EDFKeysAndValuesNumberMismatch);

    let i = 0;
    while (i < total){
      let key = *vector::borrow(&dynamic_field_keys, i);
      let new_value = *vector::borrow<u64>(&dynamic_field_values, i);
      // if a df with this key already exists
      if (df::exists_<String>(&stats.id, key)) {
        let old_value = df::borrow_mut<String, u64>(&mut stats.id, key);
        *old_value = new_value;
      } else {
        df::add<String, u64>(&mut stats.id, key, new_value);
      };
      i = i + 1;
    }
  }



  // TODO:
  // update or add the Stats object dynamic fields

  // this is possible only if `in_game` is true

  // TODO: remove dynamic fields

  // TODO: function to alter game_id of a Stat

}