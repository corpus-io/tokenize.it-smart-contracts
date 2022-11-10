# Price

The price definition used in PersonalInvite.sol and ContinuousFundraising.sol is not very intuitive. Therefore, it is explained here for reference whenever needed.

## Definitions

- bit: smallest subunit of token A is called A**bit**, in accordance with [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- tokenPrice: "amount of subunits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2\*10^6 )"
- token: will be abbreviated T for full tokens and Tbit for bits of the token

## Motivation

Math in this project wants to be exact. Rounding errors are not acceptable when it comes to investing. This becomes difficult when the token sold (T) and the currency used for payment (e.g. USDC) differ on decimal definition:

- T has 18 decimals, so one bit
- USDC has 6 decimals
  So if price was defined as 1 USDC/T and the investor wanted to buy 1Tbit, they would have to pay 10^-18 USDC, which would be rounded to 0 USDC because 1 USDCbit = 10^-6 USDC. They would get a fraction of a token for free. That can not happen.

## Solution

In order to make sure price can be expressed exactly with integers, the definition was chosen as:

```solidity
price = PaymentTokenBits/Token = PaymentTokenBits/TokenBits * Token.decimals()
```

With this, the payment amount is calculated from the token amount as:

```solidity
paymentAmount = (_tokenAmount * tokenPrice) / (10**token.decimals())
```

After enforcing that this integer division does not yield a remainder:

```solidity
(_amount * tokenPrice) % (10**token.decimals()) == 0
```

## Example

- [currency] = USDC
- USDC has 6 decimals (https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48)
- so 2.7 USDC = 2.7 \* 10\*\*6 USDCbit = 2600000 USDCbit
- assume 3 token (which is 3 \* 10\*\*18 token bits) should be sold for 600 USDC
- so 1 token costs 200 USDC
- then tokenPrice is:
  ```solidity
  600 USDC / 3 T
   = 600 * 10**6 USDCbit / 3 T
   = 200 * 10**6 USDCbit/T
   = 2 * 10**8 USDCbit/T
  ```
  The unit is omitted, so the price will be 2\*10^8
- investor wants to buy 150 tokens
- they call ContinuousFundraising.buy(150 \* 10\*\*18)
- so \_amount is 150 \* 10\*\*18
- 150 \* 10^18 \* 2 \* 10^8 = 300 \* 10^26 = 3 \* 10^28
- calculate amount due in USDC bits: 3 \* 10^28/10^18 = 3 \* 10^10
- amount due in USDC: 3 \* 10^10 / 10^6 = 3 \* 10^4 = 30000 USDC
- 30000 USDC / (200 USDC/T) = 150T -> this worked well

## Enforcement

The check above is enforced with this requirement:

```solidity
require((_amount * tokenPrice) % (10**token.decimals()) == 0, "Amount * tokenprice needs to be a multiple of 10**token.decimals()");
```

with:

- `_amount`: quantity of payment currency in smallest subunit
- `tokenPrice`: amount of currency bits that has to be paid for one token
