// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface MintableERC20 is IERC20Metadata {
    function mint(address, uint256) external returns (bool);
}