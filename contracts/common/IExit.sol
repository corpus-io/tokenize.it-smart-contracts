// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IExit {
    function claim(address _recipient, uint256 _minPayout) external;
    function currency() external view returns (IERC20);

    /// @notice Exit currency units per 10**referenceCurrency.decimals() reference currency units.
    ///         Returns 0 if no rate is set for the given reference currency.
    function referenceToExitRate(IERC20 referenceCurrency) external view returns (uint256);
}
