// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MoneriumInterfacePersonalInvite {
    constructor(address _investment, uint256 _amount) {
        IERC20(0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f).approve(
            address(_investment),
            _amount
        );
    }
}
