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

    struct GameAssetId has copy, drop, store {}

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
        
        let mut_id = cosmetic_skin::cosmetic_skin_uid_mut(&mut cosmetic_skin);

        df::add<GameAssetId, String>(mut_id, GameAssetId {}, game_asset_id);

        let i = 0;
        while(i < total_names){
            let name = *vector::borrow(&stat_names, i);
            let value = *vector::borrow(&stat_values, i);
            df::add<StatKey, String>(mut_id, StatKey { name}, value);
            i = i + 1;
        };

        cosmetic_skin
    }

}