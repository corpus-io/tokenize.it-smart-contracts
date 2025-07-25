## Token.sol

The [token contract](../contracts/Token.sol) is based on the OpenZeppelin ERC20 contract using the AccessControl extension. It also implements meta transactions following [EIP-2771](https://eips.ethereum.org/EIPS/eip-2771) and [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612).
Beyond being an ERC20 token, it has fine grained access control to:

- define who can grant and revoke roles
- define who can set requirements which a user has to meet in order to transact
- define burning rights (only company admin)
- define who is allowed to transfer the token
- define who is allowed to pause the contract
- define minting rights (through increaseMintingAllowance and decreaseMintingAllowance functions)

Also, this is the only contract in this repository that is deployed using an ERC1967-proxy. This means that it can be upgraded. Since this token is legally bound to the company, we want to make sure that we can offer our customers options if a security issue arises or regulation enforces changes.

### Minting

Minting is very central to the usage of this contract. The MintAllower role (see [access control](https://docs.openzeppelin.com/contracts/4.x/access-control)) can give an address a minting allowance. For example the admin (or CEO) of the company might need a minting allowance to create new shares. Each investment or vesting contract also needs a minting allowance in order to function.
The allowances are stored in the map `mintingAllowance`.
Addresses with the MintAllower role can mint tokens regardless of their own allowance (since they can change it at any time, enforcing the minting allowance would be pointless).

### Requirements

We expect that the companies issuing a token through tokenize.it need control about who can transact with the token for compliance reasons.
There are two ways to control who can transact with the token:

1. The `TransfererRoleAdmin` can give the `Transferer`-role to individual addresses
2. We as tokenize.it will maintain a list of addresses with fine-grained properties. The `Requirement`-role can then choose which requirements are necessary to transfer the tokens. In case they set requirements to 0, everyone can freely use the token.

## Investments

Please read the [supported currencies](../README.md#supported-currencies) section first.
Remember that extra tokens will be minted to cover [fees](fees.md), and fees will also be deducted from the payment, unless the fee is set to 0.

There are 2 investment contracts:

### 1. Private offer (PrivateOffer.sol)

This is an investment invite allowing to buy newly issued or existing tokens at a fixed price. The contract is deployed as clone, and the investment is executed during deployment. [Read this](./using_the_contracts.md#personal-invites) for more information.

Lockup periods can be realized through the combination of [PrivateOffer.sol](../contracts/PrivateOffer.sol) and [Vesting.sol](../contracts/Vesting.sol) through the [PrivateOfferFactory.sol](../contracts/factories/PrivateOfferFactory.sol).

#### Security considerations on the PrivateOffer contract

The founder sets these parameters, each of which affect the address of the contract:

```
    /// address receiving the payment in currency.
    address currencyReceiver;
    /// address holding the tokens. If 0, the token will be minted.
    address tokenHolder;
    /// minimum amount of tokens to be bought.
    uint256 minTokenAmount;
    /// maximum amount of tokens to be bought.
    uint256 maxTokenAmount;
    /// price company and investor agreed on, see docs/price.md.
    uint256 tokenPrice;
    /// timestamp after which the invitation is no longer valid.
    uint256 expiration;
    /// currency used for payment
    IERC20 currency;
    /// token to be bought
    Token token;
```

The founder then grants an allowance or minting allowance to the resulting address. They can be sure the parameters above are not tempered with, because that would change the address of the contract and thus render the allowance useless and execution impossible.

The investor is at liberty to choose these parameters:

```
    /// address holding the currency. Must have given sufficient allowance to this contract.
    address currencyPayer;
    /// address receiving the tokens. Must have sufficient attributes in AllowList to be able to receive tokens or the TRANSFERER role.
    address tokenReceiver;
    /// amount of tokens to buy
    uint256 tokenAmount;
```

These, however, do not affect the address of the contract. This means that the investor grants an allowance to the contract's address **without having an on-chain assurance that the tokens will be delivered to their address**.
Imagine this scenario:

1. the founder extends the PrivateOffer and grants the allowance
2. the investor is happy with the terms and grant their allowance
3. an attacker observes the allowance on-chain
4. assuming the attacker has access to the PrivateOffer's parameters, they can deploy the PO providing their own address as tokenReceiver
5. this way, the attacker gets the tokens while the investor pays the price

To prevent this, it is crucial to keep the parameters private. In addition to the parameters mentioned above, which might be guessable from the context, a random salt is used to make guessing impossible. These values must be communicated to the investor in a secure way and never shared with anyone else.

### 2. Crowdinvesting (Crowdinvesting.sol)

This contract allows everyone who has the `Transferer`-role on the `token` contract or who is certified by the allow-list to meet the requirements set in the `token` contract to buy tokens at an offered price. The number of tokens that can be sold in this way can be limited to `maxAmountOfTokenToBeSold`, which is the maximal amount of token to be sold in this fundraising round.

Furthermore, this contract can be paused by the owner to change the parameters. After any parameter change, a delay of 1 hour is enforced before the contract can be unpaused again. This is to prevent frontrunning attacks.

## Employee participation

In case there is no vesting, tokens can directly be issued through minting as described when setting up a new company.

For vesting the [Vesting.sol](../contracts/Vesting.sol) contract is used.

To issue new tokens, the contract needs to be given a minting allowance of maximum amount of tokens to be vested in the company token contract by calling `increaseMintingAllowance(contractAddress, amount)` from an address which has the MintAllower role. To distribute existing tokens, those tokens need to be transferred to the vesting contract.

## Factories

All of the contracts in this repository are deployed using factory contracts. This has two reasons:

1. Deterministic addresses. We can tell our customers which address their contract will have before it is deployed. This is important for the customer to be able to prepare their legal documents, which often require the address of the contract. Then, once the legal work is done (which can take days or even weeks), we can deploy the contract to the address we told them.
2. Gas efficiency. Instead of deploying full contracts, we deploy clones or proxies when possible. This saves a lot of gas, especially when deploying many contracts.
