// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

interface IPriceDynamic {
    function getPrice(uint256 basePrice) external view returns (uint256);
}
