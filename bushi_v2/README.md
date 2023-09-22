# `bushi` smart contracts package

The `bushi` smart contracts package contains two modules, `battle_pass` and `cosmetic_skins`.
- The `battle_pass` module, which provides the functionality to create battle pass objects and update them depending on the progress of the player.
- The `cosmetic_skins` module, which provides the functionality to create cosmetic skins and update their level.

## The `battle_pass` module
### Overview
The `battle_pass` module provides the functionality to create battle pass objects and update them depending on the progress of the player.

The entity that will publish the package will receive a capability of type `MintCap<BattlePass>` that gives them the permission to:
- mint battle pass NFTs, and
- allow the owner of a battle pass to alter the value of its level, xp, and xp to next level.

Once a battle pass is transferred to a custodial wallet,
- the entity owning the `MintCap<BattlePass>` should create an `UnlockUpdatesTicket` object for that battle pass that will allow the level, xp and xp to next level fields of the battle pass to be updated, and it should transfer the `UnlockUpdatesTicket` object to address of the custodial wallet.
- The player's custodial wallet will then call the `unlock_updates` function to allow updates to the aforementioned battle pass fields. The `UnlockUpdatesTicket` is burned after calling the function, and thus preventing re-usage of the ticket.
### `BattlePass` object & minting

#### The `BattlePass` object
The `BattlePass` object struct is defined as follows.
```
//// Battle pass struct
struct BattlePass has key, store{
  id: UID,
  description: String,
  // image url
  img_url: String,
  level: u64,
  level_cap: u64,
  xp: u64,
  xp_to_next_level: u64,
  rarity: u64,
  season: u64,
  in_game: bool,
}
```
A battle pass can be minted only by the address that published the package, see below.

#### `BattlePass` Display

The display properties of the `BattlePass` object are set upon initalizing the module, and can be altered using the `publisher` object. The `Display<BattlePass>` fields are set as follows.
```
let fields = vector[
  utf8(b"name"),
  utf8(b"description"),
  utf8(b"img_url"),
  utf8(b"level"),
  utf8(b"level_cap"),
  utf8(b"xp"),
  utf8(b"xp_to_next_level"),
  utf8(b"rarity"),
  utf8(b"season"),
];
let values = vector[
  utf8(b"Battle Pass"),
  utf8(b"{description}"),
  // img_url can also be something like `utf8(b"bushi.com/{img_url})"` or `utf8(b"ipfs/{img_url})` to save on space
  utf8(b"{img_url}"),
  utf8(b"{level}"),
  utf8(b"{level_cap}"),
  utf8(b"{xp}"),
  utf8(b"{xp_to_next_level}"),
  utf8(b"{rarity}"),
  utf8(b"{season}"),
];
display::add_multiple<BattlePass>(display, fields, values);
```
Note that the `in_game` field of the `BattlePass` object is not included in display.

#### Minting a Battle Pass
In order to mint a battle pass, a capability `MintCap<BattlePass>` is required. This capability will be sent to the address that published the package automatically via the `init` function.

The following functions are available for minting.
In all those functions, the `in_game` field of the `BattlePass` is set to `false` by default.

##### Function `mint`
Function `mint` takes as input the minting capability and values for the fields of the `BattlePass` object (apart from `id` which is set automatically) and returns an object of type `BattlePass`. Using programmable transactions, the object can then be passed as input to another function (for example in a transfer function).

```
/// mint a battle pass NFT
/// by default, in_game = false
public fun mint(
  mint_cap: &MintCap<BattlePass>, description: String, img_url: String, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, rarity: u64, season: u64, ctx: &mut TxContext
  ): BattlePass
```

##### Function `mint_default`
Function `mint_default` returns an object of type `BattlePass` whose level is set to 1 and xp is set to 0.
```
public fun mint_default(
  mint_cap: &MintCap<BattlePass>, description: String, img_url: String, level_cap: u64, xp_to_next_level: u64, rarity: u64, season: u64, ctx: &mut TxContext
  ): BattlePass
```

### Allowing updates to a battle pass
Once a battle pass is transferred to a user's custodial wallet, the owner of `MintCap<BattlePass>` can create an `UnlockUpdatesTicket` and transfer it to the user's custodial wallet. Then the user's custodial wallet can call the `unlock_updates` function to set the `in_game` field of the `BattlePass` object to `true` and allow calling the `update_battle_pass` function.
#### The `UnlockUpdatesTicket` object
```
/// ticket to allow mutation of the fields of the the battle pass when battle pass is in-game
/// should be created and be used after the battle pass is transferred to the custodial wallet of the player
struct UnlockUpdatesTicket has key, store {
  id: UID,
  battle_pass_id: ID,
}
```

#### Creating an `UnlockUpdatesTicket`
The function `create_unlock_updates_ticket` creates and returns an `UnlockUpdatesTicket` object, and requires the `MintCap<BattlePass>` to ensure that only an authorized entity can create one. It also requires as input the id of the battle pass object the ticket is issued for.

##### Function `create_unlock_updates_ticket`
Function `create_unlock_updates_ticket` creates and returns an `UnlockUpdatesTicket` object.
```
/// create an UnlockUpdatesTicket
/// @param battle_pass_id: the id of the battle pass this ticket is for
public fun create_unlock_updates_ticket(
  _: &MintCap<BattlePass>, battle_pass_id: ID, ctx: &mut TxContext
  ): UnlockUpdatesTicket
```

##### Function `unlock_updates`
Function `unlock_updates` will be called by the user's custodial wallet and sets the `in_game` field of the battle pass to `true`.

The function aborts if the `unlock_updates_ticket` is not issued for the battle pass of the user.

The `unlock_updates_ticket` is burned inside the function in order to prevent re-usage of the ticket.

```
/// the user's custodial wallet will call this function to unlock updates for their battle pass
public fun unlock_updates(battle_pass: &mut BattlePass, unlock_updates_ticket: UnlockUpdatesTicket)
```

#### Updating the Battle Pass fields
After the `in_game` field of the battle pass is set to `true`, the custodial wallet of the player can call the function `update_battle_pass` in order to update the `level` ,`xp` and `xp_to_next_level` fields of their battle pass, giving as input a mutable reference of the battle pass.
The `update_battle_pass` function aborts if
- `battle_pass.in_game` is `false`, or
- `new_level` is greater or equal than `battle_pass.level_cap`
```
// update battle pass level, xp, xp_to_next_level
/// aborts when in_game is false (battle pass is not in-game)
/// or when new_level > level_cap
public fun update(battle_pass: &mut BattlePass, new_level: u64, new_xp: u64, new_xp_to_next_level: u64)
```

### Locking updates
Before a battle pass is exported to a non-custodial wallet or a kiosk, the custodial wallet of a player should call the `lock_updates` function to set the `in_game` field of the battle pass to `false`, in order to prevent the fields of the battle pass being altered after it is exported.

```
/// lock updates
// this should be called by the player's custodial wallet before transferring
public fun lock_updates(
  battle_pass: &mut BattlePass
  )
```

### OriginByte NFT standards support
- `init` function
  -  a `Collection<BattlePass>` is created (and thus an event is emitted)
  -  a `MintCap<BattlePass>` is created
  -  transfer policy & royalties:
     - create a transfer policy
     - register the transfer policy to use allowlists
     - register the transfer policy to use royalty enforcements
     - set royalty cuts
   - withdraw policy:
     - create a withdraw policy
     - register the withdraw policy to require a transfer ticket to withdraw from a kiosk
   - set up orderbook for secondary market trading
- In the mint functions we require a `MintCap<BattlePass>` and emit a `mint_event` when a battle pass is minted.
- functions `mint_to_launchpad` and `mint_default_to_launchpad`: mint a battle pass and deposit it to a warehouse
- function `export_to_kiosk` deposits a battle pass to a kiosk.

#### Function `mint_to_launchpad`
```
// mint to launchpad
// this is for Clutchy integration
public fun mint_to_launchpad(
  mint_cap: &MintCap<BattlePass>, description: String, img_url: String, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, rarity: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, ctx: &mut TxContext
  )
```


#### Function `mint_default_to_launchpad`
```
// mint to launchpad with default values
public fun mint_default_to_launchpad(
  mint_cap: &MintCap<BattlePass>, description: String, img_url: String, level_cap: u64, xp_to_next_level: u64, rarity: u64, season: u64, warehouse: &mut Warehouse<BattlePass>, ctx: &mut TxContext
  )
```

#### Function `export_to_kiosk`
```
// export the battle pass to a player's kiosk
public fun export_to_kiosk(
  battle_pass: BattlePass, player_kiosk: &mut Kiosk, ctx: &mut TxContext
  )
```
Note: function `export_to_kiosk` sets `in_game` to false before exporting.

### Tests
The module `battle_pass_test` contains tests for the `battle_pass` module. The tests included are the following.
- `test_mint_default`, which tests that the `mint_default` function sets fields of the battle pass it creates as intended
- `test_mint`, which tests that the `mint` function sets the fields of the battle pass it creates as intended
- `test_unlock_with_wrong_ticket` (has expected failure) tests whether we can unlock a battle pass with an unlock ticket that is not issued for that battle pass
- `test_update_when_locked` (has expected failure) tests whether we can update the level of a battle pass when `in_game` is `false.
- `test_update` tests whether a battle pass is updated as intended.
- `test_update_when_reached_level_cap` (has expected failure) tests whether we can update the level of a battle pass with a value greater than `level_cap`.
- `test_lock` tests whether we can update the level of a battle pass after `lock_updates` has been called.


## The `cosmetic_skins` module
The `cosmetic_skins` module provides the functionality to create cosmetic skins and update their level. The flow is similar to that of the `battle_pass` module.
Similarly to the `battle_pass` module, the entity that will publish the package will receive a capability of type `MintCap<CosmeticSkin>` that is necessary in order to mint cosmetic skins and allow the owner of the cosmetic skin to alter the value of its level.

### `CosmeticSkin` object & minting

#### The `CosmeticSkin` object
The `CosmeticSkin` object is defined as follows.
```
// cosmetic skin struct
struct CosmeticSkin has key, store {
  id: UID,
  name: String,
  description: String,
  img_url: String,
  level: u64,
  level_cap: u64,
  in_game: bool,
}
```

#### Minting a Cosmetic Skin
##### Function `mint`
```
/// mint a cosmetic skin
/// by default in_game = false
public fun mint(mint_cap: &MintCap<CosmeticSkin>, name: String, description: String, img_url: String, level: u64, level_cap: u64, ctx: &mut TxContext): CosmeticSkin
```

### Allowing updates to a cosmetic skin
##### Struct `UnlockUpdatesTicket`
```
/// ticket to allow mutation of the fields of the the cosmetic skin when cosmetic skin is in-game
/// should be created and be used after the cosmetic skin is transferred to the custodial wallet of the player
struct UnlockUpdatesTicket has key, store {
  id: UID,
  cosmetic_skin_id: ID,
}
```


##### Function `create_unlock_updates_ticket`
```
/// create an UnlockUpdatesTicket
/// @param cosmetic_skin_id: the id of the cosmetic skin this ticket is issued for
public fun create_unlock_updates_ticket(
  _: &MintCap<CosmeticSkin>, cosmetic_skin_id: ID, ctx: &mut TxContext
  ): UnlockUpdatesTicket 
```


##### Function `unlock_updates`
```
/// the user's custodial wallet will call this function to unlock updates for their cosmetic skin
/// aborts if the unlock_updates_ticket is not issued for this cosmetic skin
public fun unlock_updates(cosmetic_skin: &mut CosmeticSkin, unlock_updates_ticket: UnlockUpdatesTicket)
```


#### Updating the cosmetic skin level
##### Function `update`
```
/// update cosmetic skin level
/// aborts when in_game is false (cosmetic skin is not in-game)
/// or when the new_level > level_cap
public fun update_cosmetic_skin(cosmetic_skin: &mut CosmeticSkin, new_level: u64)
```

### Locking updates
##### Function `lock`
```
/// lock updates
// this should be called by the player's custodial wallet before transferring
public fun lock_updates
```

### OriginByte NFT standards
Similarly to the `BattlePass` object:
- `init` function
  -  a `Collection<BattlePass>` is created (and thus an event is emitted)
   -  a `MintCap<BattlePass>` is created
   -  transfer policy & royalties:
      - create a transfer policy
      - register the transfer policy to use allowlists
      - register the transfer policy to use royalty enforcements
      - set royalty cuts
    - withdraw policy:
      - create a withdraw policy
      - register the withdraw policy to require a transfer ticket to withdraw from a kiosk
    - set up orderbook for secondary market trading
- In the mint functions we require a `MintCap<BattlePass>` and emit a `mint_event` when a battle pass is minted.
- functions `mint_to_launchpad` mints a cosmetic skin and deposit it to a warehouse
- function `export_to_kiosk` deposits a cosmetic skin to a kiosk

#### Function `mint_to_launchpad`
``` 
// mint to launchpad
// this is for Clutchy integration
public fun mint_to_launchpad(
  mint_cap: &MintCap<CosmeticSkin>, name: String, description: String, img_url: String, level: u64, level_cap: u64, warehouse: &mut Warehouse<CosmeticSkin>, ctx: &mut TxContext
  )
```

#### Function `export_to_kiosk`
```
public fun export_to_kiosk(
    cosmetic_skin: CosmeticSkin, player_kiosk: &mut Kiosk, ctx: &mut TxContext
    )
```

### Tests
The module `cosmetic_skins_test` contains tests for the `cosmetic_skins` module. The tests included are the following.
- `test_unlock_with_wrong_ticket` (has expected failure) tests whether we can unlock a cosmetic skin with an unlock ticket that is not issued for that cosmetic skin
- `test_update_when_locked` (has expected failure) tests whether we can update the `level` of a cosmetic skin when in_game is `false`.
- `test_mint` and `test_update` test whether cosmetic skins are minted and updated with the intended values.
- `test_update_when_reached_level_cap` (has expected failure) tests whether we can update the `level` of a cosmetic skin with a value greater than `level_cap`.
- `test_lock` tests whether we can update the `level` of the cosmetic skin after `lock_updates` has been called.
