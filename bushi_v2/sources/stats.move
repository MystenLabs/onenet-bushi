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

}