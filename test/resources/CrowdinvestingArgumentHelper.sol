// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../../lib/forge-std/src/Test.sol";
import "../../contracts/Crowdinvesting.sol";

function cloneCrowdinvestingInitializerArguments(
    CrowdinvestingInitializerArguments memory arguments
) pure returns (CrowdinvestingInitializerArguments memory) {
    return
        CrowdinvestingInitializerArguments(
            arguments.owner,
            arguments.currencyReceiver,
            arguments.minAmountPerBuyer,
            arguments.maxAmountPerBuyer,
            arguments.tokenPrice,
            arguments.priceMin,
            arguments.priceMax,
            arguments.maxAmountOfTokenToBeSold,
            arguments.currency,
            arguments.token,
            arguments.lastBuyDate,
            arguments.priceOracle,
            arguments.tokenHolder
        );
}
