# Players

1. **tokenize.it** or **platform**: A platform that enables company shares to be created and traded on an evm-compatible chain
2. **company** or **founder**: A company that wants to emit shares, and in most cases receive capital in return
3. **investor**: An entity that wants to receive shares of a company and is willing to pay for doing so
4. (**employee**: A person that works for the company and may receive shares as part of their compensation. Emitting these shares can be done through 3rd party contracts, but is not the current focus of this project.)

Let's assume that there will be one (1) platform, many (x) companies and many (y) investors. This leads to the following number of deployments for each contract:
| contract | number of deployments | admin | reason |
|----|----|----|---|
| AllowList | 1 | platform | used by all companies |
| FeeSettings | 1 | platform | used by all companies |
| Token | x | company | represents a specific companies shares |
| ContinuousFundraising | x | company | most companies will want raise funds from all eligible investors |
| PersonalInvite | >x | --- | most companies will extend special investment offers to specific investors, or receive these from investors |

# Example work flow

## Platform deployment

Tokenize.it deploys AllowList and FeeSettings contracts once. Also, a web app will be provided. This app will not be described in depth here.

## Company deployment

Using the platform, the company, in this example the company's founder, signs up using a wallet. After finishing necessary settings and verifications off-chain, the platform deploys a Token contract on the founder's behalf. The founder's address is set as admin in the constructor. This means that the founder is immediately in control of the contract, even though it was deployed by the platform.

Which addresses are able to receive or send the tokens can be limited through the requirements, which are checked against AllowList.

When tokens are minted, [fees are charged](fees.md).

## Fundraising

When investments are processed, [fees are charged](fees.md).

### Open fundraising

The founder can offer shares at a certain price to the public. If they want to do so, the platform deploys a ContinuousFundraising contract and transfers ownership to the founder.

Afterwards, the founder grants a token minting allowance to the ContinuousFundraising contract, enabling it to mint shares.

In order to buy tokens, investors must grant an allowance in payment currency and execute the deal() function. This will transfer the payment to the receiver selected by the founder and mint tokens to the investor.

The fundraising can be stopped or paused by the founder. When it is paused, conditions like price or minimum amount can be updated.

All transactions can be performed without founders or investors having to pay ethereum transaction fees (see [Transaction fees](#transaction-fees)).

### Closed fundraising

Founders and investors can agree on specific terms for an investment, e.g. a special price or a special currency to pay with (the platform will support WETH, WBTC, EUROC and USDC at the beginning). This investment is executed during deployment of the PersonalInvite contract.

Founder and investor have to agree on the deal in 3 ways before the contract can be deployed:

- terms of investment -> needed to calculate the contract's address (will be deployed using CREATE2)
- founder grants token minting allowance to contract's address
- investor grants payment allowance to contract's address

Once these steps have been taken completed, the platform executes the deal by deploying the contract. Again, all ethereum transaction fees are paid by the platform.

# Services

## Transaction fees

The platform will pay all ethereum transaction fees for deployments and other transactions performed through it's web app. This is made possible through the use of meta transactions (EIP-2771) and trustless deployment procedures.

Note that the, independent of ethereum transaction fees, the platform charges fees for token minting and investments!

## Investor and company pool

Companies will profit from a pool of verified investors provided by the platform, and investors will profit from companies being available for investment.

## Liquidity

Tokens (=shares) being transferable between investors makes shares a liquid asset.
