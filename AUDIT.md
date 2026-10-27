# Security Audit — `miso_player`

Audited at `01c4158fb9a8143bb472e9dd59dc004472d9ce38` (2026-10-21) and updated on 2026-10-27 for `462eef2`, which removed `receive` and `withdraw_funds`. Package `miso_player`, module `miso_player::player`; framework dependency `sui::derived_object` and `sui::transfer` at `719fb2960ccfbf9f4d33041f8ea5146d30671696`.

## What it does

A shared `PlayerRegistry` from which each address derives exactly one non-transferable `Player { id }` (`sources/player.move:13`, `:36`). Features attach through `uid_mut` (`:43`), and the module exposes nothing else for them. Objects sent to the player and funds sent with `balance::send_funds` come out only through extensions using `uid_mut`, with `transfer::public_receive` and `balance::withdraw_funds_from_object`. See [README](./README.md).

## Trust model

- **Anyone** can call `new` once per sender address; the player goes to `ctx.sender()`. Anyone can compute a player's address with `derive_address` (`:53`) and send it objects or funds.
- **Player owner**: the only party that can pass `&mut Player` to a function, and therefore the only one who can extend it or have an extension take out what it holds. There is no admin cap and no privileged role.
- **Any module the owner hands `&mut Player` to** has, through `uid_mut`, the same custody as the owner: it can `balance::withdraw_funds_from_object` every currency, `transfer::public_receive` every `key + store` object, `transfer::receive` its own non-`store` objects, and add or claim under the player's UID. Verified by a probe test from a sibling module.
- **Nobody** can transfer, wrap, delete or re-create a `Player`, claim a derived player ID for another address, or claim derived objects under the registry: `Player` has `key` only, `transfer::transfer` on it is restricted to this module (verifier `ESC02009`, probed), `PlayerKey` is constructible only here (probed), and `registry.id` is never exposed.

## Findings

**MP-1 · Low · Accepted** — `uid_mut` (`sources/player.move:43`) grants full custody of the player's holdings to any callee, not just the ability to attach dynamic fields. A malicious or buggy extension that the owner calls with `&mut Player` can drain `send_funds` balances and receive owned objects in the same transaction; the module cannot distinguish extension writes from withdrawals. Since `462eef2` this is also the only way holdings leave the player: receiving and withdrawing are themselves extensions. The README documents this and requires value-holding extensions to live in derived objects. A mitigation if desired later is a narrower `extend(&mut Player): &mut UID` gated by a per-extension witness.

**MP-2 · Info · Accepted** — Every `new` mutates the single shared `PlayerRegistry` (`derived_object::claim` adds a `Claimed` dynamic field), so player creation serializes through one shared object. Inherent to the derived-object pattern.

**MP-3 · Info · Accepted** — A lost owner key strands the player and everything at its address forever; the derived ID can never be re-claimed and there is no recovery path. Stated in the README ("No destroy").

## Checked, no finding

- **One player per address.** `derived_object::claim(&mut registry.id, PlayerKey(owner))` (`:38`) aborts `EObjectAlreadyExists` on repeat (test `second_player_for_address_aborts`); `derive_address` uses the same parent ID and key (test `new_sends_derived_player_to_sender`).
- **Owner binding.** `owner = ctx.sender()` (`:37`); in a sponsored transaction the sender, not the sponsor, is bound.
- **Non-transferability.** `Player` has no `store`: no `public_transfer`, no wrapping, no dynamic-field storage; the only transfer is `:40`.
- **Holdings through `uid_mut`.** `transfer::public_receive(player.uid_mut(), ticket)` takes out a `key + store` object sent to the player, and `balance::withdraw_funds_from_object(player.uid_mut(), amount)` with `redeem_funds` takes out funds (tests `objects_sent_to_player_come_out_through_uid_mut`, `funds_sent_to_player_come_out_through_uid_mut`). Non-`store` objects need their defining module. The framework reserves withdrawals against the player's accumulator balance natively, so nothing can be withdrawn twice in one transaction. `enable_object_funds_withdraw` is on: mainnet protocol 138 and testnet protocol 139 (GraphQL `protocolConfigs`, 2026-10-21).
- **Extension namespace.** Dynamic-field and derived-object keys are typed, so extensions cannot forge each other's keys; `derived_object`'s `Claimed` marker type is private to the framework and cannot be removed.
- **Events.** `PlayerCreatedEvent { player_id, owner }` (`:39`) suffices to index every player; `init` emits nothing (test `init_shares_registry_without_event`). Objects and funds that extensions take out are visible from transaction effects.
- **Abort codes.** The module defines none; its only reachable abort comes from `derived_object` (duplicate player).
- **Limits.** `new` emits one event and one dynamic field; well within the 1,024 command/event caps.

## Operational requirements

- Owners should only pass `&mut Player` to packages they trust with everything the player holds (MP-1); tooling should warn when a transaction combines a third-party extension call with a player argument.
- Record the `PlayerRegistry` ID from the publish transaction's effects; there is no event for it.

## Verification

- `sui move test --coverage`: 7/7 passed; `sui move coverage summary`: 100.00% for `miso_player::player` (2026-10-27, at `462eef2`). The funds test withdraws amount 0 only; unit tests cannot settle accumulator funds, so the non-zero path is covered by the framework and should be checked on localnet.
- `sui move build -e mainnet` and `sui move build -e testnet`: both succeed with framework `719fb2960ccfbf9f4d33041f8ea5146d30671696` (Move.lock).
- Throwaway probes (not committed): sibling module withdraws funds, receives a `Coin<SUI>` and a non-`store` object through `uid_mut`; `transfer::transfer(Player)` and `PlayerKey(..)` outside the module fail to compile.
