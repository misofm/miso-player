// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: FSL-1.1-ALv2

/// A listener's on-chain root. Each address has at most one `Player`, derived
/// from the `PlayerRegistry` by owner, and it can never change hands, so
/// history attached to it can't be sold. Owner-written data attaches as
/// extensions through `uid_mut`. Anything with its own funds or public writes
/// should be a separate object derived from `uid_mut` instead, because the UID
/// also controls every object and fund held at the player's address.
module miso_player::player;

// === Imports ===

use sui::balance::{Self, Balance};
use sui::derived_object;
use sui::event::emit;
use sui::transfer::Receiving;

// === Structs ===

/// `key` only, so only this module can transfer it, and it does so once, in
/// `new`. Being address-owned, only its owner can pass it to a function.
public struct Player has key {
    id: UID,
}

public struct PlayerRegistry has key {
    id: UID,
}

public struct PlayerKey(address) has copy, drop, store;

// === Events ===

public struct PlayerCreatedEvent has copy, drop {
    player_id: ID,
    owner: address,
}

// === Public Functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(PlayerRegistry { id: object::new(ctx) });
}

/// A second `new` from the same address aborts in `derived_object`. There is
/// no way to destroy a player: a derived ID can't be claimed again, so a
/// deleted player could never be replaced.
public fun new(registry: &mut PlayerRegistry, ctx: &mut TxContext) {
    let owner = ctx.sender();
    let player = Player { id: derived_object::claim(&mut registry.id, PlayerKey(owner)) };
    emit(PlayerCreatedEvent { player_id: object::id(&player), owner });
    transfer::transfer(player, owner);
}

public fun uid_mut(self: &mut Player): &mut UID {
    &mut self.id
}

/// Takes an object sent to the player's address, such as a Record.
public fun receive<Item: key + store>(self: &mut Player, item: Receiving<Item>): Item {
    transfer::public_receive(&mut self.id, item)
}

/// Takes funds sent to the player's address with `balance::send_funds`.
public fun withdraw_funds<Currency>(self: &mut Player, amount: u64): Balance<Currency> {
    balance::redeem_funds(balance::withdraw_funds_from_object(&mut self.id, amount))
}

// === View Functions ===

public fun uid(self: &Player): &UID {
    &self.id
}

public fun derive_address(registry: &PlayerRegistry, owner: address): address {
    derived_object::derive_address(registry.id.to_inner(), PlayerKey(owner))
}

// === Test Functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun player_created_event_fields(event: &PlayerCreatedEvent): (ID, address) {
    (event.player_id, event.owner)
}
