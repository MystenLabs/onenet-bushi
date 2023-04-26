module bushi::cosmetic_skin {

  use std::option;
  use std::string::{utf8, String};

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

  // error for when update of cosmetic skin not possible
  const EUpdateNotPossible: u64 = 0;

  // one-time-witness for publisher
  struct COSMETIC_SKIN has drop {}

  struct Witness has drop {}

  // cosmetic skin struct
  struct CosmeticSkin has key, store {
    id: UID,
    name: String,
    description: String,
    url: Url,
    level: u64,
    level_cap: u64,
  }

  // update ticket to update the cosmetic skin
  struct UpdateTicket has key, store {
    id: UID,
    cosmetic_skin_id: ID,
    new_name: String,
    new_description: String,
    new_url: Url,
    new_level: u64,
    new_level_cap: u64,
  }

  fun init(otw: COSMETIC_SKIN, ctx: &mut TxContext){

    // initialize collection and mint cap
    let (collection, mint_cap) = collection::create_with_mint_cap<COSMETIC_SKIN, CosmeticSkin>(&otw, option::none(), ctx);

    // claim publisher
    let publisher = package::claim(otw, ctx);

    // create display object
    let display = display::new<CosmeticSkin>(&publisher, ctx);
    // set display fields
    set_display_fields(&mut display);

    // --- transfers to address that published the module ---
    let publisher_address = tx_context::sender(ctx);
    transfer::public_transfer(mint_cap, publisher_address);
    transfer::public_transfer(publisher, publisher_address);
    transfer::public_transfer(display, publisher_address);

    // --- shared objects ---
    transfer::public_share_object(collection);
  }

  // mint a cosmetic skin
  public fun mint(mint_cap: &MintCap<CosmeticSkin>, name: String, description: String, url: vector<u8>, level: u64, level_cap: u64, ctx: &mut TxContext): CosmeticSkin {

    let cosmetic_skin = CosmeticSkin {
      id: object::new(ctx),
      name,
      description,
      url: url::new_unsafe_from_bytes(url),
      level,
      level_cap,
    };

    // emit a mint event
      mint_event::emit_mint(
      witness::from_witness(Witness {}),
      mint_cap::collection_id(mint_cap),
      &cosmetic_skin
    );

    cosmetic_skin
  }

  // create a cosmetic skin update ticket
  public fun create_update_ticket(_: &MintCap<CosmeticSkin>, cosmetic_skin_id: ID, new_name: String, new_description: String, new_url: vector<u8>, new_level: u64, new_level_cap: u64, ctx: &mut TxContext): UpdateTicket {

    let update_ticket = UpdateTicket {
      id: object::new(ctx),
      cosmetic_skin_id,
      new_name,
      new_description,
      new_url: url::new_unsafe_from_bytes(new_url),
      new_level,
      new_level_cap,
    };

    update_ticket
  }

  // user's custodial wallet will call this function to update their cosmetic skin
  fun update_cosmetic_skin(cosmetic_skin: &mut CosmeticSkin, update_ticket: UpdateTicket){

      // make sure update ticket is for this cosmetic skin
      assert!(update_ticket.cosmetic_skin_id == object::uid_to_inner(&cosmetic_skin.id), EUpdateNotPossible);
      
      // update cosmetic skin
      cosmetic_skin.name = update_ticket.new_name;
      cosmetic_skin.description = update_ticket.new_description;
      cosmetic_skin.url = update_ticket.new_url;
      cosmetic_skin.level = update_ticket.new_level;
      cosmetic_skin.level_cap = update_ticket.new_level_cap;

      // delete update ticket
      let UpdateTicket {id: update_ticket_id, cosmetic_skin_id: _, new_name: _, new_description: _, new_url: _, new_level: _, new_level_cap: _} = update_ticket;
      object::delete(update_ticket_id);
  }

  // === helpers ===

  fun set_display_fields(display: &mut Display<CosmeticSkin>){

    let fields = vector[
      utf8(b"name"),
      utf8(b"description"),
      utf8(b"url"),
      utf8(b"level"),
      utf8(b"level_cap"),
    ];
    
    let values = vector[
      utf8(b"{name}"),
      utf8(b"{description}"),
      utf8(b"{url}"),
      utf8(b"{level}"),
      utf8(b"{level_cap}"),
    ];

    display::add_multiple<CosmeticSkin>(display, fields, values);
  }
}