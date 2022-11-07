// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/CorpusToken.sol";
import "../contracts/ContinuousFundraising.sol";



/*
    malicious currency to that tries to reenter a function a set number of times
*/
contract MaliciousPaymentToken is ERC20 {
    ContinuousFundraising public exploitTarget;
    uint public timesToReenter;
    uint public amountToReenterWith;
    uint public reentrancyCount;
    address public originalSender;
    uint public originalAmount;


    constructor(uint256 _initialSupply) ERC20("MaliciousPaymentToken", "MPT") {
        _mint(msg.sender, _initialSupply);
    }

    /**
    @notice set which contract to exploit
     */
    function setExploitTarget(address _exploitTarget, uint _timesToReenter, uint _amountToReenterWith) public {
        exploitTarget = ContinuousFundraising(_exploitTarget);
        timesToReenter = _timesToReenter;
        amountToReenterWith = _amountToReenterWith;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (reentrancyCount == 0) {
            // store original values
            originalSender = sender;
            originalAmount = amount;
        }
        if (reentrancyCount < timesToReenter) {
            reentrancyCount++;
            exploitTarget.buy(amountToReenterWith);
        }
        else {
            reentrancyCount = 0;
            super.transferFrom(originalSender, recipient, originalAmount);
        }
        return true;
    }

}