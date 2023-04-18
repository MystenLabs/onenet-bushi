module battle_pass::battle_pass{

  use std::string::{Self, String};

  use sui::object::{Self, ID, UID};
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::url::{Self, Url};

  const XP_TO_NEXT_LEVEL: u64 = 1000;
  const LEVEL_CAP: u64 = 70;

  /// Battle pass struct
  struct BattePass has key, store{
    id: UID,
    name: String,
    description: String,
    url: Url,
    level: u64,
    level_cap: u64,
    xp: u64,
    xp_to_next_level: u64,
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
    // experience that will be added to the battle pass
    experience: u64,
  }

  /// init function
  fun init(ctx: &mut TxContext){

    // create Mint Capability
    let mint_cap = MintCap { id: object::new(ctx) };

    // transfer mint cap to address that published the module
    transfer::transfer(mint_cap, tx_context::sender(ctx))
  }

  /// mint a battle pass NFT that has level and xp set to 0
  public fun mint_default(_: &MintCap, name_bytes: vector<u8>, description_bytes: vector<u8>, url_bytes: vector<u8>, ctx: &mut TxContext): BattePass{
    BattePass { 
      id: object::new(ctx), 
      name: string::utf8(name_bytes),
      description: string::utf8(description_bytes),
      url: url::new_unsafe_from_bytes(url_bytes),
      level: 0,
      level_cap: LEVEL_CAP,
      xp: 0,
      xp_to_next_level: XP_TO_NEXT_LEVEL,
    }

  }

  /// call the mint_default and then transfer the NFT to a specific address
  public fun mint_default_and_transfer(mint_cap: &MintCap, name_bytes: vector<u8>, description_bytes: vector<u8>, url_bytes: vector<u8>, recipient: address, ctx: &mut TxContext) {
    let battle_pass = mint_default(mint_cap, name_bytes, description_bytes, url_bytes, ctx);
    transfer::transfer(battle_pass, recipient)
  }

  /// to create an upgrade ticket the mint cap is needed
  /// this means the entity that can mint battle passes can also issue a ticket to upgrade them
  /// but the function can be altered so that the two are separate entities
  public fun create_upgrade_ticket(_: &MintCap, battle_pass_id: ID, experience: u64, ctx: &mut TxContext): UpgradeTicket {
    UpgradeTicket { id: object::new(ctx), battle_pass_id, experience }
  }

  /// call the `create_upgrade_ticket` and send the ticket to a specific address
  public fun create_upgrade_ticket_and_transfer(mint_cap: &MintCap, battle_pass_id: ID, experience: u64, recipient: address, ctx: &mut TxContext){
    let upgrade_ticket = create_upgrade_ticket(mint_cap, battle_pass_id, experience, ctx);
    transfer::transfer(upgrade_ticket, recipient)
  }

}