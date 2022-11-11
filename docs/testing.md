# Testing

Most tests run locally, but some require a mainnet fork. Therefore, simply running `forge test` will likely fail (because it does not fork mainnet). Use these commands instead:
* `forge test --no-match-test Mainnet` for local tests only (they are included in the CI/CD pipeline, too)
* `forge test --match-test Mainnet --fork-url <rpc-url>` for mainnet tests only
* `forge test --fork-url <rpc-url>` to run all tests

If you don't have a ethereum node to use for the `<rpc-url>`, you can use infura. After free sign up, the url will have this structure, where `<api-key>` is replaced by your secret:
`https://mainnet.infura.io/v3/<api-key>`

More information can be found here: 
* https://mirror.xyz/susheen.eth/bRCzT2QLdNINMVk8251udkfjHW_T9ascCQ1DV9hURz0
* https://www.paradigm.xyz/2021/12/introducing-the-foundry-ethereum-development-toolbox#you-should-be-able-to-run-your-tests-against-a-live-networks-state

