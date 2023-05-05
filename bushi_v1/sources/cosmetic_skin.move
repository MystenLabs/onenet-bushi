module bushi::cosmetic_skin {

  use std::option;
  use std::string::{utf8, String};

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

  // error for when update of cosmetic skin not possible
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

  // one-time-witness for publisher
  struct COSMETIC_SKIN has drop {}

  struct Witness has drop {}

  // cosmetic skin struct
  struct CosmeticSkin has key, store {
    id: UID,
    name: String,
    description: String,
    img_url: Url,
    level: u64,
    level_cap: u64,
  }

  // update ticket to update the cosmetic skin
  struct UpdateTicket has key, store {
    id: UID,
    cosmetic_skin_id: ID,
    new_level: u64,
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

  // mint a cosmetic skin
  public fun mint(mint_cap: &MintCap<CosmeticSkin>, name: String, description: String, img_url_bytes: vector<u8>, level: u64, level_cap: u64, ctx: &mut TxContext): CosmeticSkin {

    let cosmetic_skin = CosmeticSkin {
      id: object::new(ctx),
      name,
      description,
      img_url: url::new_unsafe_from_bytes(img_url_bytes),
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

  // mint to launchpad
  // this is for Clutchy integration
  public fun mint_to_launchpad(
    mint_cap: &MintCap<CosmeticSkin>, name: String, description: String, img_url_bytes: vector<u8>, level: u64, level_cap: u64, warehouse: &mut Warehouse<CosmeticSkin>, ctx: &mut TxContext
    ) {

      let cosmetic_skin = mint(mint_cap, name, description, img_url_bytes, level, level_cap, ctx);
      // deposit to warehouse
      warehouse::deposit_nft(warehouse, cosmetic_skin);
  }

  // create a cosmetic skin update ticket
  public fun create_update_ticket(
    _: &MintCap<CosmeticSkin>, cosmetic_skin_id: ID, new_level: u64, ctx: &mut TxContext
    ): UpdateTicket {

    UpdateTicket {
      id: object::new(ctx),
      cosmetic_skin_id,
      new_level,
    }
  }

  // the user will call this function to update their cosmetic skin
  public fun update_cosmetic_skin(cosmetic_skin: &mut CosmeticSkin, update_ticket: UpdateTicket){

      // make sure update ticket is for this cosmetic skin
      assert!(update_ticket.cosmetic_skin_id == object::uid_to_inner(&cosmetic_skin.id), EUpdateNotPossible);
      
      // update cosmetic skin level
      cosmetic_skin.level = update_ticket.new_level;

      // delete update ticket
      let UpdateTicket { id: update_ticket_id, cosmetic_skin_id: _, new_level: _ } = update_ticket;
      object::delete(update_ticket_id);
  }

  // === exports ===

  // export the cosmetic skin to a player's kiosk
  public fun export_to_kiosk(
    cosmetic_skin: CosmeticSkin, player_kiosk: &mut Kiosk, ctx: &mut TxContext
    ) {
    // check if OB kiosk
    ob_kiosk::assert_is_ob_kiosk(player_kiosk);

    // deposit the battle pass into the kiosk.
    ob_kiosk::deposit(player_kiosk, cosmetic_skin, ctx);
  }

  // === private-helpers ===

  fun set_display_fields(display: &mut Display<CosmeticSkin>){

    let fields = vector[
      utf8(b"name"),
      utf8(b"description"),
      utf8(b"img_url"),
      utf8(b"level"),
      utf8(b"level_cap"),
    ];
    
    let values = vector[
      utf8(b"{name}"),
      utf8(b"{description}"),
      utf8(b"{img_url}"),
      utf8(b"{level}"),
      utf8(b"{level_cap}"),
    ];

    display::add_multiple<CosmeticSkin>(display, fields, values);
  }

  #[test_only]
  public fun test_init(ctx: &mut TxContext){
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
  public fun img_url(cosmetic_skin: &CosmeticSkin): Url {
    cosmetic_skin.img_url
  }

  #[test_only]
  public fun level(cosmetic_skin: &CosmeticSkin): u64 {
    cosmetic_skin.level
  }

  #[test_only]
  public fun level_cap(cosmetic_skin: &CosmeticSkin): u64 {
    cosmetic_skin.level_cap
  }
}