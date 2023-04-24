# Battle pass smart contract v1

Package name: `battle_pass`

The `battle_pass` package provides the functionality to create Battle Pass objects and update them depending on the progress of the player.

The entity that will publish the package will receive a capability of type `MintCap<BattlePass>` that gives them the permission to:
- Create a Battle Pass NFT for a player.
- Give permission to update the current level and xp of the Battle Pass NFT of a player.

## Battle Pass object & minting

### `BattlePass` object
Every player will own a `BattlePass` object.
The `BattlePass` object struct is defined as follows
```
struct BattlePass has key, store{
  id: UID,
  url: Url,
  level: u64,
  xp: u64,
}
```
where `id` is the id of the object (unique per battle pass object instance), `url` is a url with the image of the battle pass, `level` is the current level and `xp` is the current xp.
A Battle Pass can be minted only by the address that published the package, see below.

### `BattlePass` Display

### Minting a Battle Pass
In order to mint a Battle Pass, a capability `MintCap<BattlePass>` is required. This capability will be sent to the address that published the package automatically via the `init` function.
There are 4 functions available for minting.

#### Function `mint`
Function `mint` takes as input the minting capability, the url with the image of the battle pass, the level and the xp the battle pass will have initially, and returns an object of type `BattlePass`. Using programmable transactions, the object can then be passed as input to another function (for example transferred to an address).

```
/// mint a battle pass NFT
public fun mint(
    mint_cap: &MintCap<BattlePass>, url_bytes: vector<u8>, level: u64, xp: u64, ctx: &mut TxContext
    ): BattlePass
```
#### Function `mint_default`
Function `mint_default` returns a `BattlePass` object whose level is set to 1 and xp is set to 0. It requires as input only the minting capability and the url of the Battle Pass.
```
/// mint a battle pass NFT that has level set to 1 and xp set to 0
public fun mint_default(
    mint_cap: &MintCap<BattlePass>, url_bytes: vector<u8>, ctx: &mut TxContext
    ): BattlePass
```

#### Function `mint_and_transfer`
Function `mint_and_transfer` creates a `BattlePass` object by calling `mint` and transfers it to a given address.
```
// mint a battle pass and transfer it to a specific address
public fun mint_and_transfer(
  mint_cap: &MintCap<BattlePass>, url_bytes: vector<u8>, level: u64, xp: u64, recipient: address, ctx: &mut TxContext
  )
```

#### Function `mint_default_and_transfer`
Function `mint_default_and_transfer` creates a `BattlePass` object by calling the `mint_default` function and transfers it to a given address.
```
/// mint a battle pass with level set to 1 and xp set to 0 and then transfer it to a specific address
public fun mint_default_and_transfer(
  mint_cap: &MintCap<BattlePass>, url_bytes: vector<u8>, recipient: address, ctx: &mut TxContext
  )
```

## Upgrading a Battle Pass
In order for the Battle Pass to be upgraded with the progress of the player, an object of type `UpgradeTicket` should be mint by the entity that published the package and sent to the player. Then, the custodial wallet of the player can call the `upgrade_battle_pass` function to update the status of their Battle Pass.

### `UpgradeTicket` object
The `UpgradeTicket` object is defined as follows
```
struct UpgradeTicket has key, store {
  id: UID,
  // ID of the battle pass that this ticket can upgrade
  battle_pass_id: ID,
  // new xp of battle pass
  new_xp: u64,
  // new level of battle pass
  new_level: u64,
  }
``` 
where `id` is the id of the `UpgradeTicket` object (unique per ticket), `battle_pass_id` is the id of the battle pass that this ticket is issued for, `new_xp` and `new_level` are the new xp and level of the Battle Pass, respectively.

### Creating an Upgrade Ticket
There are two functions that allow the creation of an `UpgradeTicket` object and both require the `MintCap<BattlePass>` to ensure that only an authorized entity can create one.

#### Function `create_upgrade_ticket`
Function `create_upgrade_ticket` creates and returns an `UpgradeTicket` object.
```
/// to create an upgrade ticket the mint cap is needed
/// this means the entity that can mint a battle pass can also issue a ticket to upgrade it
/// but the function can be altered so that the two are separate entities
public fun create_upgrade_ticket(
  _: &MintCap<BattlePass>, battle_pass_id: ID, new_xp: u64, new_level: u64, ctx: &mut TxContext
  ): UpgradeTicket 
```

#### Function `create_upgrade_ticket_and_transfer`
Function `create_upgrade_ticket_and_transfer` creates an `UpgradeTicket` object by calling the `create_upgrade_ticket` function and transfers it to an address.
```
/// call the `create_upgrade_ticket` and send the ticket to a specific address
public fun create_upgrade_ticket_and_transfer(
  mint_cap: &MintCap<BattlePass>, battle_pass_id: ID, new_xp: u64, new_level: u64, recipient: address, ctx: &mut TxContext
  )
  ```

### Upgrading the Battle Pass
After an upgrade ticket is created and sent to the Battle Pass owner, the Battle Pass owner should call the function `upgrade_battle_pass` in order to update the `level` and `xp` fields of their Battle Pass, giving as input the upgrade ticket and a mutable reference of their Battle Pass.
 The `upgrade_battle_pass` function aborts if the `id` field of the Battle Pass does not match the `battle_pass_id` field of the upgrade ticket and thus preventing the upgrade of a player's Battle Pass with the progress of another player.
 Furthermore, after the upgrade is completed the upgrade ticket is destroyed inside the function, in order to prevent re-using it in the future and also for storage optimization.
 ```
/// a battle pass holder will call this function to upgrade the battle pass
/// aborts if upgrade_ticket.battle_pass_id != id of Battle Pass
public fun upgrade_battle_pass(
  battle_pass: &mut BattlePass, upgrade_ticket: UpgradeTicket, _: &mut TxContext
  )
  ```
## OriginByte NFT standards
- create `BattlePass` collection (an event is emitted)
- use `MintCap<BattlePass>` and emit a mint event when minting