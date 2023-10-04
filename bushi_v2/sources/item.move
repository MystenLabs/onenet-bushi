module bushi::item {

    // Standard library imports
    use std::string::{utf8, String};
    use std::vector;
    
    // Sui imports
    use sui::display::{Self, Display};
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{TxContext};
    use sui::event::emit;

    use nft_protocol::mint_cap::{MintCap};

    // BattlePass Module dependency
    use bushi::battle_pass::BattlePass;

    /// Error reporting constants
    const EWrongToken: u64 = 0;
    const ECannotUpdate: u64 = 1;
    const ELevelGreaterThanLevelCap: u64 = 2;
    const EItemNotInGame: u64 = 3;
    const EKeysAndValuesNumberMismatch: u64 = 4;

    // Item AdminCap 
    // It is transferrable in case the owner needs to change addresses
    struct ItemAdminCap has key, store { 
        id: UID 
    }

    /// item struct
    struct Item has key, store {
        id: UID,
        name: String,
        description: String,
        image_url: String,
        level: u64,
        level_cap: u64,
        game_asset_ids: vector<String>,
        stat_names: vector<String>,
        stat_values: vector<String>,
        in_game: bool
    }

    /// ticket to allow mutation of the fields of the the item when item is in-game
    /// should be created and be used after the item is transferred to the custodial wallet of the player
    struct UnlockUpdatesTicket has key, store {
        id: UID,
        item_id: ID,
    }

    /// --- Item Stats Updated Event ---
    struct ItemStatsUpdated has copy, drop {
        id: ID,
        stat_names: vector<String>,
        stat_values: vector<String>,
    }


    // Mint an admin Item capability for authorizing Item actions  
    public fun mint_admin_cap_item(_: &MintCap<BattlePass>, ctx: &mut TxContext): ItemAdminCap{
        ItemAdminCap { id: object::new(ctx) }
    }

    /// mint a item
    /// by default in_game = false
    public fun mint(_: &mut ItemAdminCap, name: String, description: String, 
        image_url: String, level: u64, level_cap: u64, game_asset_ids: vector<String>, 
        stat_names: vector<String>, stat_values: vector<String>, in_game: bool, 
        ctx: &mut TxContext): Item
    {
        // make sure the level is not greater than the level cap
        assert!(level <= level_cap, ELevelGreaterThanLevelCap);

        let item = Item {
            id: object::new(ctx),
            name,
            description,
            image_url,
            level,
            level_cap,
            game_asset_ids,
            stat_names,
            stat_values,
            in_game,
        };

        item
    }

    // === Unlock updates ticket ====

    /// create an UnlockUpdatesTicket
    /// @param item_id: the id of the item this ticket is issued for
    public fun create_unlock_updates_ticket(_: &mut ItemAdminCap, item_id: ID, ctx: &mut TxContext): UnlockUpdatesTicket 
    {
        UnlockUpdatesTicket {
            id: object::new(ctx),
            item_id
        }
    }

    // === Unlock updates ===

    /// the user's custodial wallet will call this function to unlock updates for their item
    /// aborts if the unlock_updates_ticket is not issued for this item
    public fun unlock_updates(item: &mut Item, unlock_updates_ticket: UnlockUpdatesTicket)
    {
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
    public fun update(item: &mut Item, new_level: u64)
    {
        // make sure the item is in-game
        assert!(item.in_game, ECannotUpdate);
        // make sure the new level is not greater than the level cap
        assert!(new_level <= item.level_cap, ELevelGreaterThanLevelCap);
        item.level = new_level;
    }

    /// update game_asset_ids
    public fun update_game_asset_ids(item: &mut Item, game_asset_ids: vector<String>)
    {
        assert!(item.in_game == true, ECannotUpdate);
        item.game_asset_ids = game_asset_ids;
    }

    /// update item stats
    public fun update_stats(
        item: &mut Item,
        stat_names: vector<String>,
        stat_values: vector<String>) 
    {
        assert!(in_game(item) == true, ECannotUpdate);

        let total = vector::length(&stat_names);
        assert!(total == vector::length(&stat_values), EKeysAndValuesNumberMismatch);

        item.stat_names = stat_names;
        item.stat_values = stat_values;

         // Create and emit an ItemStatsUpdated event
        let item_stats_updated_event = ItemStatsUpdated {
            id: object::uid_to_inner(&item.id),
            stat_names: item.stat_names,
            stat_values: item.stat_values
        };
        // emit the event when the item stats are updated
        emit(item_stats_updated_event);

    }

    // === Exports ===

    /// lock updates
    // this can be called by the player's custodial wallet before transferring - if the export_to_kiosk function is not called
    // if it is not in-game, this function will do nothing 
    public fun lock_updates(item: &mut Item) 
    {
        // set in_game to false
        item.in_game = false;
    }

    // === private-helpers ===

    public fun set_display_fields(display: &mut Display<Item>){

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

    // Burn an item
    public fun burn(item: Item) 
    {
        let Item {
            id,
            name: _,
            description: _,
            image_url: _,
            level: _,
            level_cap: _,
            game_asset_ids: _,
            stat_names: _,
            stat_values: _,
            in_game: _,
        } = item;

        object::delete(id);
    }

    // === Accesors ===

    public fun admin_get_mut_uid(_: &mut ItemAdminCap, item: &mut Item): &mut UID 
    {
        &mut item.id
    }

    /// get a mutable reference of UID of item
    /// only if item is in-game
    /// (aborts otherwise)
    public fun cw_get_mut_uid(item: &mut Item,): &mut UID {
        assert!(item.in_game == true, EItemNotInGame);
        &mut item.id
    }

    public fun get_immut_uid(item: &Item): &UID {
        &item.id
    }

    public fun in_game(item: &Item,): bool {
        item.in_game
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