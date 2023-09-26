module bushi::stats{

    // Standard library imports
    use std::vector;
    use std::string::{String};
    
    // Sui library imports
    use sui::tx_context::{TxContext};
    use sui::dynamic_field as df;
    
    // cosmetic_skin module imports
    use bushi::cosmetic_skin::{CosmeticSkin, Self};

    // nft_protocol module imports for Origin Byte
    use nft_protocol::mint_cap::MintCap;

    // Error codes
    const ESizeOfNamesAndValuesMismatch: u64 = 0;
    const ECannotUpdate: u64 = 1;
    const EDFKeysAndValuesSizeMismatch: u64 = 2;

    // GameAssetId field to be added as a dynamic field in a cosmetic skin
    struct GameAssetId has copy, drop, store {}

    // StatKey field to be added as a dynamic field in a cosmetic skin
    struct StatKey has copy, drop, store { name: String }

    public fun mint_with_dfs (
        mint_cap: &MintCap<CosmeticSkin>,
        name: String,
        description: String,
        image_url: String,
        level: u64,
        level_cap: u64,
        game_asset_id: String,
        stat_names: vector<String>,
        stat_values: vector<String>,
        ctx: &mut TxContext
    ): CosmeticSkin {

        let total_names = vector::length(&stat_names);
        assert!((total_names == vector::length(&stat_values)), ESizeOfNamesAndValuesMismatch);

        let cosmetic_skin = cosmetic_skin::mint(
            mint_cap,
            name,
            description,
            image_url,
            level,
            level_cap,
            ctx
        );
        
        let mut_uid = cosmetic_skin::admin_get_mut_uid(mint_cap, &mut cosmetic_skin);

        df::add<GameAssetId, String>(mut_uid, GameAssetId {}, game_asset_id);

        let i = 0;
        while(i < total_names){
            let name = *vector::borrow(&stat_names, i);
            let value = *vector::borrow(&stat_values, i);
            df::add<StatKey, String>(mut_uid, StatKey { name}, value);
            i = i + 1;
        };

        cosmetic_skin
    }

    public fun update_or_add_stats(
        cosmetic_skin: &mut CosmeticSkin,
        stat_names: vector<String>,
        stat_values: vector<String>,
    ) {
        assert!(cosmetic_skin::in_game(cosmetic_skin) == true, ECannotUpdate);

        let total = vector::length(&stat_names);

        // Check if the size of the vectors match
        assert!(total == vector::length(&stat_values), EDFKeysAndValuesSizeMismatch);

        let mut_uid = cosmetic_skin::cw_get_mut_uid(cosmetic_skin);

        let i = 0;
        while (i < total){
            let name = *vector::borrow(&stat_names, i);
            let stat_key = StatKey { name };
            let new_value = *vector::borrow<String>(&stat_values, i);
            // if a df with this key already exists
            if (df::exists_<StatKey>(mut_uid, stat_key)) {
                let old_value = df::borrow_mut<StatKey, String>(mut_uid, stat_key );
                *old_value = new_value;
            } else {
                df::add<StatKey, String>(mut_uid, stat_key, new_value);
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

        assert!(cosmetic_skin::in_game(cosmetic_skin) == true, ECannotUpdate);

        let mut_uid = cosmetic_skin::cw_get_mut_uid(cosmetic_skin);

        let total = vector::length(&stat_names);
        let i = 0;
        while (i < total) {
            let name = *vector::borrow<String>(&stat_names, i);
            let stat_key = StatKey { name };
            // if dynamic field with key `key` does not exist, throw an error
            assert!(df::exists_<StatKey>(mut_uid, stat_key), EDynamicFieldDoesNotExist);
            df::remove<StatKey, u64>(mut_uid, stat_key);
            i = i + 1;
        };
  }

    /// Update or add to a Cosmetic Skin a game asset ID
    public fun update_or_add_game_asset_id(
        cosmetic_skin: &mut CosmeticSkin,
        new_game_asset_id: String,
    ) {
        // make sure Cosmetic Skin is in-game
        assert!((cosmetic_skin::in_game(cosmetic_skin) == true), ECannotUpdate);

        let mut_uid = cosmetic_skin::cw_get_mut_uid(cosmetic_skin);

        let game_asset_id_key = GameAssetIDKey {};
        // check if cosmetic skin has a game asset id, if yes update, if not add
        if (df::exists_<GameAssetIDKey>(mut_uid, game_asset_id_key)) {
        // update the game asset id
        let old_game_asset_id = df::borrow_mut<GameAssetIDKey, String>(mut_uid, game_asset_id_key);
        *old_game_asset_id = new_game_asset_id;
        } else {
        df::add<GameAssetIDKey, String>(mut_uid, game_asset_id_key, new_game_asset_id);
        };
  }

    // remove game_asset_id
    // aborts if the cosmetic skin does not have that field
    public fun remove_game_asset_id(
        cosmetic_skin: &mut CosmeticSkin,
    ) {

        // make sure Cosmetic Skin is in-game
        assert!((cosmetic_skin::in_game(cosmetic_skin) == true), ECannotUpdate);

        let game_asset_id_key = GameAssetIDKey {};

        let mut_uid = cosmetic_skin::cw_get_mut_uid(cosmetic_skin);

        // check that cosmetic skin has that field
        assert!(df::exists_<GameAssetIDKey>(mut_uid, game_asset_id_key), EDynamicFieldDoesNotExist);
        // remove the field
        df::remove<GameAssetIDKey, String>(mut_uid, game_asset_id_key);
    }

    // returns game asset id of cosmetic skin
    // aborts if game asset id df does not exist
    public fun get_game_asset_id(
        cosmetic_skin: &CosmeticSkin,
    ): String {
        
        let game_asset_id_key = GameAssetIDKey {};

        let immut_uid = cosmetic_skin::get_immut_uid(cosmetic_skin);

        assert!(df::exists_(immut_uid, game_asset_id_key), EDynamicFieldDoesNotExist);

        *df::borrow<GameAssetIDKey, String>(immut_uid, game_asset_id_key)
  }

    // returns value of stat of cosmetic skin
    // aborts if stat does not exist
    public fun get_stat_value(
        cosmetic_skin: &CosmeticSkin,
        stat_name: String,
    ): String {

        let stat_key = StatKey { name: stat_name };

        let immut_uid = cosmetic_skin::get_immut_uid(cosmetic_skin);

        // make sure stat exists
        assert!(df::exists_<StatKey>(immut_uid, stat_key), EDynamicFieldDoesNotExist);

        *df::borrow<StatKey, String>(immut_uid, stat_key)
  }

}