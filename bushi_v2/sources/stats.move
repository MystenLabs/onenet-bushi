module bushi::stats{
    // Standard library imports
    use std::vector;
    use std::string::{String};
    // Sui library imports
    use sui::tx_context::{TxContext};
    
    // cosmetic_skin module imports
    use bushi::cosmetic_skin::{CosmeticSkin, Self};
    use nft_protocol::mint_cap::MintCap;

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
        cosmetic_skin
    }

}