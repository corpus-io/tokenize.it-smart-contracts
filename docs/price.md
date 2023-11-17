# Price

The price definition used in PrivateOffer.sol and Crowdinvesting.sol is not very intuitive. Therefore, it is explained here for reference whenever needed.

## Terms used

- bit: smallest subunit of token A is called A**bit**, in accordance with [openzeppelin](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- tokenPrice: "amount of subunits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2\*10^6 )"
- token: will be abbreviated T for full tokens and Tbit for bits of the token

## Definition

In order to make sure price can be expressed exactly with integers, the definition was chosen as:

```solidity
price = PaymentTokenBits/Token = PaymentTokenBits/TokenBits * 10**Token.decimals()
```

With this, the payment amount could be calculated from the token amount as:

```solidity
paymentAmount = (_tokenAmount * tokenPrice) / (10**token.decimals())
```

Since this is done using integer math, it rounds down by default. For example:

- T has 18 decimals, so one bit
- USDC has 6 decimals
  So if price was defined as 1 USDC/T and the investor wanted to buy 1Tbit, they would have to pay 10^-18 USDC, which would be rounded to 0 USDC because 1 USDCbit = 10^-6 USDC. They would get a fraction of a token for free.

Giving away equity without payment is not acceptable. Therefore, the calculation is done rounding up to the next integer, using openzeppelin's ceilDiv function:

```solidity
paymentAmount = Math.ceilDiv(_tokenAmount * tokenPrice,  10**token.decimals())
```

The error introduced by rounding is less than or equal to one currency bit. For USDT, this would result in a maximum error of 0.000001 USD. They are negligible for all practical purposes.

## Example (with rounding error=0)

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
- they call Crowdinvesting.buy(150 \* 10\*\*18)
- so \_amount is 150 \* 10\*\*18
- 150 \* 10^18 \* 2 \* 10^8 = 300 \* 10^26 = 3 \* 10^28
- calculate amount due in USDC bits: 3 \* 10^28/10^18 = 3 \* 10^10
- amount due in USDC: 3 \* 10^10 / 10^6 = 3 \* 10^4 = 30000 USDC
- 30000 USDC / (200 USDC/T) = 150T -> this worked well

## Comparing prices

While the rounding error introduced in the paymentAmount is negligible, edge cases can result in seemingly large deviations in the actual price paid per token.
Take the following example:

- priceNominal = 1 currencyBits/token
- tokenAmount = 1 tokenBit
- this results in paymentAmount = 1 currencyBit
- so the pricePaid is 1 currencyBit/tokenBit
- with token.decimals() = 18, this results in: **pricePaid = priceNominal \* 10\*\*18**

Keep in mind that this seemingly HUGE difference in price still results in a paymentAmount difference of only 1 currencyBit. Or, as was just explained, is the result thereof.

The buyer can do all of these calculations beforehand, and just decide to buy the maximum amount of tokens possible for the currency they have to spend anyway. This is not enforced by the smart contracts though. It can be implemented in a frontend.
