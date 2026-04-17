// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Stub IExit: claim() pays a fixed amount to _recipient, ignoring _minPayout.
/// Lets tests trigger the caller's own balance-diff check independently of Exit's.
contract FixedPayoutExit {
    IERC20 public currency;
    uint256 public payout;

    constructor(IERC20 _currency, uint256 _payout) {
        currency = _currency;
        payout = _payout;
    }

    function claim(address _recipient, uint256) external {
        if (payout > 0) currency.transfer(_recipient, payout);
    }

    function referenceToExitRate(IERC20) external pure returns (uint256) {
        return 0;
    }
}
