# `bushi` smart contracts package

The `bushi` smart contracts package contains two modules, `battle_pass` and `cosmetic_skins`.
- The `battle_pass` module, which provides the functionality to create battle pass objects and update them depending on the progress of the player.
- The `cosmetic_skins` module, which provides the functionality to create cosmetic skins and update their level.

## The `battle_pass` module
### Overview
The `battle_pass` module provides the functionality to create battle pass objects and update them depending on the progress of the player.

The entity that will publish the package will receive a capability of type `MintCap<BattlePass>` that gives them the permission to:
- Mint battle pass NFTs.
- Give permission to the player to update the level, xp and xp to next level of their battle pass NFT.

In order for a player's progress in the battle pass to be recorded on-chain:
- The entity owning the `MintCap<BattlePass>` should create an `UpdateTicket` object that contains the updated values for the level, xp and xp to next level for that player, and it should transfer the `UpgradeTicket` object to the player.
- The player's custodial wallet will then call the `update_battle_pass` function in order for their battle pass level, xp, and xp to next level to be updated with the new values.
### `BattlePass` object & minting

#### The `BattlePass` object
<!-- Every player will own a `BattlePass` object. -->
The `BattlePass` object struct is defined as follows.
```
/// Battle pass struct
struct BattlePass has key, store{
  id: UID,
  description: String,
  // image url
  url: Url,
  level: u64,
  level_cap: u64,
  xp: u64,
  xp_to_next_level: u64,
  season: u64,
}
```
A battle pass can be minted only by the address that published the package, see below.

<!-- ### `BattlePass` Display -->

#### Minting a Battle Pass
In order to mint a battle pass, a capability `MintCap<BattlePass>` is required. This capability will be sent to the address that published the package automatically via the `init` function.
There are 2 functions available for minting.

##### Function `mint`
Function `mint` takes as input the minting capability and values for the fields of the `BattlePass` object (apart from `id` which is set automatically) and returns an object of type `BattlePass`. Using programmable transactions, the object can then be passed as input to another function (for example in a transfer function).

```
/// mint a battle pass NFT
public fun mint(
  mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, season: u64, ctx: &mut TxContext
  ): BattlePass
```

##### Function `mint_default`
Function `mint_default` returns a `BattlePass` object whose level is set to 1 and xp is set to 0. It requires as input only the minting capability and the url of the battle pass.
```
public fun mint_default(
  mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level_cap: u64, xp_to_next_level: u64, season: u64, ctx: &mut TxContext
  ): BattlePass
```

### Updating a Battle Pass
In order for the battle pass to be updated with the progress of the player, an object of type `UpdateTicket` should be mint by the entity that published the package and sent to the player. Then, the player can call the `update_battle_pass` function to update the status of their battle pass.

#### The `UpdateTicket` object
The `UpdateTicket` object is defined as follows
```
/// Update ticket struct
struct UpdateTicket has key, store {
  id: UID,
  // ID of the battle pass that this ticket can update
  battle_pass_id: ID,
  // new level of battle pass
  new_level: u64,
  // new xp of battle pass
  new_xp: u64,
  // new xp to next level of battle pass
  new_xp_to_next_level: u64,
}
``` 
where 
- `id` is the id of the `UpdateTicket` object (unique per ticket)
- `battle_pass_id` is the id of the battle pass that this ticket is issued for
- `new_xp`, `new_level` and `new_xp_to_next_level` are the values the `xp`, `level` and `xp_to_next_level` fields of the battle pass resp. that it should have after the update.

#### Creating an Update Ticket
The function `create_update_ticket` allows the creation of an `UpdateTicket` object, and requires the `MintCap<BattlePass>` to ensure that only an authorized entity can create one.

##### Function `create_update_ticket`
Function `create_update_ticket` creates and returns an `UpdateTicket` object.
```
/// to create an update ticket the mint cap is needed
/// this means the entity that can mint a battle pass can also issue a ticket to update it
/// but the function can be altered so that the two are separate entities
public fun create_update_ticket(
  _: &MintCap<BattlePass>, battle_pass_id: ID, new_level: u64, new_xp: u64, new_xp_to_next_level: u64, ctx: &mut TxContext
  ): UpdateTicket
```

#### Updating the Battle Pass
After an update ticket is created and sent to the battle pass owner, the battle pass owner should call the function `update_battle_pass` in order to update the `level` ,`xp` and `xp_to_next_level` fields of their battle pass, giving as input the update ticket and a mutable reference of their battle pass.
The `update_battle_pass` function aborts if the `id` field of the battle pass does not match the `battle_pass_id` field of the update ticket and thus preventing the update of a player's battle pass with the progress of another player.
Furthermore, after the update is completed the update ticket is destroyed inside the function, in order to prevent re-using it in the future and also for storage optimization.
 ```
/// a battle pass holder will call this function to update the battle pass
/// aborts if update_ticket.battle_pass_id != id of battle pass
public fun update_battle_pass(
  battle_pass: &mut BattlePass, update_ticket: UpdateTicket
  )
  ```

### Tests
The module `battle_pass_test` contains tests for the `battle_pass` module. The tests performed are the following.
- `fun test_mint_default()`, which tests that the `mint_default` function sets fields of the battle pass it creates as intended
- `fun test_mint()`, which tests that the `mint` function sets the fields of the battle pass it creates as intended
- `fun test_update()`, which tests whether after minting a battle pass and issuing an update ticket the fields of the battle pass are updated as intended, and that the update ticket is destroyed after the function has finished executing.
- `fun test_update_with_wrong_ticket()`, which has `#[expected_failure(abort_code = EUpdateNotPossible)]` and tests that the `update_battle_pass` aborts when is given as input a battle pass and an update ticket that is not created for that battle pass.

### OriginByte NFT standards
- In the `init` function a `Collection<BattlePass>` is created (and thus an event is emitted).
- In the mint functions we require a `MintCap<BattlePass>` and emit a `mint_event` when a battle pass is minted.

## The `cosmetic_skins` module
The `cosmetic_skins` module provides the functionality to create cosmetic skins and update their level.
Similarly to the `battle_pass` module, the entity that will publish the package will receive a capability of type `MintCap<CosmeticSkin>` that is necessary in order to mint cosmetic skins and give permission to users to update them.

In order for the level of a cosmetic skin of a player to be updated:
- The entity that holds the `MintCap<BattlePass>` capability should issue an `UpdateTicket` object and transfer it to the player.
- The player will then call the `update_cosmetic_skin` function to update the level of their cosmetic skin.

### `CosmeticSkin` object & minting

#### The `CosmeticSkin` object
The `CosmeticSkin` object is defined as follows.
```
// cosmetic skin struct
struct CosmeticSkin has key, store {
  id: UID,
  name: String,
  description: String,
  img_url: Url,
  level: u64,
  level_cap: u64,
}
```

#### Minting a Cosmetic Skin
In order to mint a cosmetic skin, a capability of type `MintCap<CosmeticSkin>` is required, which will be sent automatically to the entity that published the package. This ensures that only an authorized entity can mint a cosmetic skin.
##### Function `mint`
Function `mint` is defined as follows.
```
public fun mint(mint_cap: &MintCap<CosmeticSkin>, name: String, description: String, img_url_bytes: vector<u8>, level: u64, level_cap: u64, ctx: &mut TxContext): CosmeticSkin
```
The function returns an object of type `CosmeticSkin` that will be handled using programmable transactions.

### Updating a Cosmetic Skin
The proccess of updating a cosmetic skin is similar to that of updating a battle pass.
- The entity possessing the `MintCap<UpdateTicket>` will create an update ticket for the cosmetic skin using the `create_update_ticket` function.
- The player owning the cosmetic skin object will call the `update_cosmetic_skin` function to update their cosmetic skin.

#### The `UpdateTicket` object
The `UpdateTicket` object is defined as follows.
```
// update ticket to update the cosmetic skin
struct UpdateTicket has key, store {
  id: UID,
  cosmetic_skin_id: ID,
  new_level: u64,
}
```
where
- `id` is unique per cosmetic skin and set automatically
- `cosmetic_skin_id` is the `ID` of the cosmetic skin the update ticket corresponds to
- `new_level` is the level the cosmetic skin should have after the update.

#### Function `create_update_ticket`
The function `create_update_ticket` is defined as follows.
```
// create a cosmetic skin update ticket
public fun create_update_ticket(_: &MintCap<CosmeticSkin>, cosmetic_skin_id: ID, new_level: u64, ctx: &mut TxContext): UpdateTicket
```
In order to call this function, the capability `MintCap<UpdateTicket>` is needed, to ensure that only an authorized entity can give the permission to a player to update their cosmetic skin.
The function returns an update ticket that should be handled using programmable transactions (for example transferred to the player whose cosmetic skin can be updated).

#### Function `update_cosmetic_skin`
The function `update_cosmetic_skin` takes as input a mutable reference to a cosmetic skin and an update ticket for that cosmetic skin and updates the level field of the cosmetic skin. Once called, the update ticket is destroyed inside the function to ensure that the update ticket cannot be re-used.
```
// the user will call this function to update their cosmetic skin
public fun update_cosmetic_skin(cosmetic_skin: &mut CosmeticSkin, update_ticket: UpdateTicket)
```

### Tests
The module `cosmetic_skins_test` contains tests for the `cosmetic_skins` module. The tests performed are the following.
- `fun test_mint()`, which tests that the `mint` function sets the fields of the cosmetic skin it has created as intended
- `fun test_update()`, which tests that after minting a cosmetic skin and issuing an update ticket the cosmetic skin is updated as intended, and that the update ticket is destroyed after the function has finished executing.
- `fun test_update_with_wrong_ticket()`, which has `#[expected_failure(abort_code = EUpdateNotPossible)]` and tests that the `update_cosmetic_skin` aborts when is given as input a cosmetic skin and an update ticket that is not created for that cosmetic skin.

### OriginByte NFT standards
Similarly to the `BattlePass` object:
- In the `init` function a `Collection<CosmeticSkin>` is created (and thus an event is emitted).
- In the mint functions a `MintCap<CosmeticSkin>` is required and a `mint_event` is emitted when a cosmetic skin is minted.