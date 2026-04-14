// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/Exit.sol";

/**
 * @notice Malicious ERC20 currency that reenters Exit.claim() from its transfer() hook.
 *  Used to verify that Exit's nonReentrant guard blocks cross-function reentrancy.
 */
contract MaliciousExitCurrency is ERC20 {
    Exit public exploitTarget;
    address public claimRecipient;
    bool private _attacking;

    constructor() ERC20("MaliciousCurrency", "MC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setExploitTarget(address _target, address _recipient) external {
        exploitTarget = Exit(_target);
        claimRecipient = _recipient;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (!_attacking && address(exploitTarget) != address(0)) {
            _attacking = true;
            exploitTarget.claim(claimRecipient, 0);
            _attacking = false;
        }
        return super.transfer(to, amount);
    }
}
