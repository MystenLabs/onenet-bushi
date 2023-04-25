# Battle pass smart contract v1

Package name: `battle_pass`

## Overview
The `battle_pass` package provides the functionality to create Battle Pass objects and update them depending on the progress of the player.

The entity that will publish the package will receive a capability of type `MintCap<BattlePass>` that gives them the permission to:
- Create a Battle Pass NFT for a player.
- Give permission to the player to update the level, xp and xp to next level of their Battle Pass NFT.

## Battle Pass object & minting

### `BattlePass` object
Every player will own a `BattlePass` object.
The `BattlePass` object struct is defined as follows
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
A Battle Pass can be minted only by the address that published the package, see below.

<!-- ### `BattlePass` Display -->

### Minting a Battle Pass
In order to mint a Battle Pass, a capability `MintCap<BattlePass>` is required. This capability will be sent to the address that published the package automatically via the `init` function.
There are 2 functions available for minting.

#### Function `mint`
Function `mint` takes as input the minting capability and values for the fields of the `BattlePass` object (apart from `id` which is set automatically) and returns an object of type `BattlePass`. Using programmable transactions, the object can then be passed as input to another function (for example in a transfer function).

```
/// mint a battle pass NFT
public fun mint(
  mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level: u64, level_cap: u64, xp: u64, xp_to_next_level: u64, season: u64, ctx: &mut TxContext
  ): BattlePass
```

#### Function `mint_default`
Function `mint_default` returns a `BattlePass` object whose level is set to 1 and xp is set to 0. It requires as input only the minting capability and the url of the Battle Pass.
```
public fun mint_default(
  mint_cap: &MintCap<BattlePass>, description: String, url_bytes: vector<u8>, level_cap: u64, xp_to_next_level: u64, season: u64, ctx: &mut TxContext
  ): BattlePass
```

## Upgrading a Battle Pass
In order for the Battle Pass to be updated with the progress of the player, an object of type `UpdateTicket` should be mint by the entity that published the package and sent to the player. Then, the custodial wallet of the player can call the `update_battle_pass` function to update the status of their Battle Pass.

### `UpdateTicket` object
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

### Creating an Update Ticket
There are two functions that allow the creation of an `UpdateTicket` object and both require the `MintCap<BattlePass>` to ensure that only an authorized entity can create one.

#### Function `create_update_ticket`
Function `create_update_ticket` creates and returns an `UpdateTicket` object.
```
/// to create an update ticket the mint cap is needed
/// this means the entity that can mint a battle pass can also issue a ticket to update it
/// but the function can be altered so that the two are separate entities
public fun create_update_ticket(
  _: &MintCap<BattlePass>, battle_pass_id: ID, new_level: u64, new_xp: u64, new_xp_to_next_level: u64, ctx: &mut TxContext
  ): UpdateTicket
```

### Updating the Battle Pass
After an update ticket is created and sent to the Battle Pass owner, the Battle Pass owner should call the function `update_battle_pass` in order to update the `level` ,`xp` and `xp_to_next_level` fields of their Battle Pass, giving as input the update ticket and a mutable reference of their Battle Pass.
The `update_battle_pass` function aborts if the `id` field of the Battle Pass does not match the `battle_pass_id` field of the update ticket and thus preventing the update of a player's Battle Pass with the progress of another player.
Furthermore, after the update is completed the update ticket is destroyed inside the function, in order to prevent re-using it in the future and also for storage optimization.
 ```
/// a battle pass holder will call this function to update the battle pass
/// aborts if update_ticket.battle_pass_id != id of Battle Pass
public fun update_battle_pass(
  battle_pass: &mut BattlePass, update_ticket: UpdateTicket, _: &mut TxContext
  )
  ```
## OriginByte NFT standards
- In the `init` function a `Collection<BattlePass>` is created (and thus an event is emitted).
- In the mint functions we require a `MintCap<BattlePass>` and emit a `mint_event` when a Battle Pass is minted.