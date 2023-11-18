# Upgradeability

## Motivation

We intend to make our protocols mostly feature complete, so upgrading is not a common occurrence. While most contracts can be replaced by new ones by simply deploying the new contract and using the new address, the token contract is a special case. Its address is fixed in legal contracts, users are aware of it, exchanges might use it. Being able to upgrade the token contract while keeping the address would therefore be an considerable advantage.

Upgrading comes with security implications. Through upgrades, the mechanics of contracts can be changed in any way. In case of the token contract, we consider this acceptable, because the token's default admin has very powerful privileges anyway. They can burn anyones token at any time for example. Accountability is ensured by the fact that every transaction is public on the blockchain. If the admin abuses their power, they can be held accountable in a court of law for example. The same is true for upgrades. Yes, it is possible to upgrade to a contract that freezes all assets and grants the right to move all tokens to the admin only. But this would be a very obvious attack and the admin would be held accountable for it.

## Implementation

We chose the UUPS Proxy pattern for upgradeability. This pattern is described in [EIP-1822](https://eips.ethereum.org/EIPS/eip-1822). It is a simple pattern that allows to upgrade a contract while keeping the address. The pattern is implemented in [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/4.x/api/proxy).

### Storage Layout

Note that we are using Openzepplin Contracts v4.9, which, contrary to v5, uses a linear storage layout. This means any contract we inherit from takes up storage slots BEFORE our token contract itself.

During an upgrade of the token contract, the storage layout of the old and new versions have to be compatible, which in most cases means equal. In order to still be able to add an inheritance, a storage gap has been added before the first state variable of the token contract. The width of this gap has been chosen to force the first state variable (`allowList`) to reside at slot 1000.

Any changes have to be made in a way that ensures this layout is preserved. Some checks for this have been added to the test suite (search for `test*Storage`).
