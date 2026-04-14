# One-Time Syndicate Fee for CoinvestedPosition, along with single-tx PrivateOffer setup

## What was added

1. Lead investors can now charge the coinvestor a one-time fee at position opening time. The fee is expressed as a fraction of the investment amount (e.g. 2%), split among lead investors proportionally to their carry fractions.

2. A CoinvestedPosition can now be funded through a PrivateOffer in a single transaction: the clone is created, the fee is collected, and the tokens are deposited atomically.

## How it works

**Setup (off-chain):**

1. `CoinvestedPositionCloneFactory.predictCoinvestedPositionAndPrivateOfferAddress` takes all arguments and predicts the future CoinvestedPosition address.
2. `currencyPayer` and `tokenReceiver` in the `PrivateOfferArguments` are replaced with that address.
3. Using these updated arguments, the future PrivateOffer address is predicted.
4. Both addresses are returned.
5. The investor signals commitment by approving the future CoinvestedPosition address to spend currency (investment amount + one-time fee).
6. The founder signals commitment by granting a minting allowance to the future PrivateOffer address.

**Execution (single transaction, callable by anyone — e.g. the platform):**

7. `CoinvestedPositionCloneFactory.createCoinvestedPositionWithPrivateOffer` is called.
8. The CoinvestedPosition clone is created.
9. `coinvestedPositionClone.initializeWithPrivateOffer` is called, which:
   - Pulls investment + fee from the investor into the clone.
   - Calculates and distributes the one-time fee to lead investors.
   - Approves the predicted PrivateOffer address for the investment amount.
   - Deploys the PrivateOffer via `privateOfferFactory.deployPrivateOffer`, which transfers the investment to the founder and mints tokens into the clone.

**Note:** `CoinvestedPosition` now has two initializers; only one can be called per clone, enforced by OpenZeppelin's `initializer` modifier.

## Why we do it like this

The fee requires an approval from the investor. We want to limit the investor wallet interactions to a single approval that covers both the fee and the investment. The way to make this safe is to ensure every relevant parameter — fee fraction, lead investors, PrivateOffer terms — is encoded in the address the approval is granted to. The CoinvestedPosition clone address is derived deterministically from all of these parameters, so approving it is implicit consent to all terms. Any deviation produces a different address that the investor has not approved.

Instead of extending the already complex, tried and tested PrivateOfferFactory with this additional task (which might be possible, too), we use it as a foundation in this new environment.

**Alternatives that don't work:**

- _Approve the factory to handle currency_ — the factory address is fixed and shared; anyone could exploit an open approval.
- _Have the CoinvestedPosition owner call a separate funding function_ — requires a second wallet interaction from the investor, breaking the single-approval flow.

# Questions for the reviewer

1. Should the one-time fee also apply to positions funded outside of a PrivateOffer? If so, we can extend the default `initialize` to accept and collect it as well.
2. Does the fee have to be provided as relative information, e.g. 2%? With the current setup, it might be clearer as absolute amount. Which can of course be calculated offchain to match 2% of the investment amount or whatever.
