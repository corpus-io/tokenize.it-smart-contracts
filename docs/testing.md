# Testing

## Executing tests

Most tests run locally, but some require a mainnet fork. Therefore, simply running `forge test` will likely fail (because it does not fork mainnet). Use these commands instead:

- `forge test --no-match-test Mainnet` for local tests only (they are included in the CI/CD pipeline, too)
- `forge test --match-test Mainnet --fork-url <rpc-url>` for mainnet tests only
- `forge test --fork-url <rpc-url>` to run all tests

If you don't have a ethereum node to use for the `<rpc-url>`, you can use infura. After free sign up, the url will have this structure, where `<api-key>` is replaced by your secret:
`https://mainnet.infura.io/v3/<api-key>`

More information can be found here:

- https://mirror.xyz/susheen.eth/bRCzT2QLdNINMVk8251udkfjHW_T9ascCQ1DV9hURz0
- https://www.paradigm.xyz/2021/12/introducing-the-foundry-ethereum-development-toolbox#you-should-be-able-to-run-your-tests-against-a-live-networks-state

## Measuring coverage

Run `forge coverage` to measure coverage. Unfortunately, forge measures coverage of contracts in test/resources, too, which spoils the total results.
Run `yarn coverage` in order to generate a comprehensive report of coverage that allows for in-depth analysis. Open [the report](../coverage/index.html) in your browser to dig through the results.

Even though the report does not show 100% coverage, the code is covered 100%. Check the next section for details.

## Coverage issues

It appears forge makes some mistakes when calculating coverage.

### Constructors

Constructor coverage is not included in the reports. This is particularly sad because PrivateOffer has a constructor ONLY, and no other code. There are plenty tests that cover correct execution, even though it is not mentioned in the report.

### Allegedly uncovered branches

Forge claims this if statement in PublicFundraising.sol and Token.sol has an uncovered branch:

```solidity
if (fee != 0) {...}
```

Both branches (fee>0 and fee == 0) are covered with explicit tests though.

### Uncovered lines

The line `return ERC2771Context._msgData();` in PublicFundraising.sol and Token.sol is actually not covered by tests. It is not used in the contracts either, but has to be included to specify inheritance.
