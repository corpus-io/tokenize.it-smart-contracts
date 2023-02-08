// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "../../lib/forge-std/src/Test.sol";
import "../../contracts/Token.sol";
import "../../contracts/ContinuousFundraising.sol";

/*
    malicious currency to that tries to reenter a function a set number of times
*/
contract MaliciousPaymentToken is ERC20 {
    ContinuousFundraising public exploitTarget;
    uint256 public timesToReenter;
    uint256 public amountToReenterWith;
    uint256 public reentrancyCount;
    address public originalSender;
    uint256 public originalAmount;

    constructor(uint256 _initialSupply) ERC20("MaliciousPaymentToken", "MPT") {
        _mint(msg.sender, _initialSupply);
    }

    /**
    @notice set which contract to exploit
     */
    function setExploitTarget(
        address _exploitTarget,
        uint256 _timesToReenter,
        uint256 _amountToReenterWith
    ) public {
        exploitTarget = ContinuousFundraising(_exploitTarget);
        timesToReenter = _timesToReenter;
        amountToReenterWith = _amountToReenterWith;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        if (reentrancyCount == 0) {
            // store original values
            originalSender = sender;
            originalAmount = amount;
        }
        if (reentrancyCount < timesToReenter) {
            reentrancyCount++;
            exploitTarget.buy(amountToReenterWith, address(this));
        } else {
            reentrancyCount = 0;
            super.transferFrom(originalSender, recipient, originalAmount);
        }
        return true;
    }
}
