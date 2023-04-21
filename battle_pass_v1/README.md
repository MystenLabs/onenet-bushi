# Battle pass smart contract v1

Package name: `battle_pass`

The `battle_pass` package provides the functionality to create Battle Pass objects and update them depending on the progress of the player.

The entity that will publish the package will receive a capability that gives them the permission to:
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
There are 4 functions available for minting:

#### Function `mint`
Function `mint` takes as input the minting capability, the url with the image of the battle pass, the level and the xp the battle pass will have initially, and returns an object of type `BattlePass`. Using programmable transactions, the object then can be transferred to the desired address.

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
In order for the Battle Pass to be upgraded with the progress of the player, an object of type `UpogradeTicket` should be mint by the entity that published the package and sent to the player. Then, the custodial wallet of the player can call the `upgrade_battle_pass` function to update the status of their Battle Pass.

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

### Upgrading the Battle Pass





## OriginByte NFT standards
- create `BattlePass` collection (an event is emitted)
- use `MintCap<BattlePass>` and emit a mint event when minting
- 