// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../lib/forge-std/src/Test.sol";

contract ERC20Helper is Test {
    using stdStorage for StdStorage;
    /** 
        @notice sets the balance of who to amount. This is only possible in a test environment.
        taken from here: https://mirror.xyz/brocke.eth/PnX7oAcU4LJCxcoICiaDhq_MUUu9euaM8Y5r465Rd2U
    */
    function writeERC20Balance(
        address who,
        address _token,
        uint256 amount
    ) public {
        stdstore
            .target(_token)
            .sig(IERC20(_token).balanceOf.selector)
            .with_key(who)
            .checked_write(amount);
    }
}
