// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../contracts/PersonalInvite.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*
The contract is deployed by the fundraising company and is getting an IBAN by Monerium. By sending EUR to this IBAN, the investors is able to approve funds to investment contract which are added by the fundraising company.
In case of an personal invite, it can be executed by the company.
In ces of a continuous fundraising, the investor can now call the `buy`function in order to make an investment.
This contract is inteneded to be used for all investments into one specific fundraising company (`owner`) by a single investor.
*/

contract MoneriumInterface is Ownable2Step {
    mapping(address => bool) public map;

    event Set(address indexed key, bool value);

    IERC20 constant EURe = IERC20(0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f); // ToDO get address from ENS
    address public investor;

    constructor(address _investor) {
        investor = _investor;
    }

    function addInvestmentContract(
        address _addr,
        bool _active
    ) external onlyOwner {
        map[_addr] = _active;
        emit Set(_addr, _active);
    }

    function approve(address _investment, uint256 _amount) external {
        require(msg.sender == investor);
        require(map[_investment]);
        EURe.approve(address(_investment), _amount);
    }

    /**
    @notice purges an address from the map
    @dev this is a convenience function, it is equivalent to calling addInvestmentContract(_addr, 0)
    */
    function remove(address _addr) external onlyOwner {
        delete map[_addr];
        emit Set(_addr, false);
    }

    // called in case money is stuck in the contract due to malfunction of investment contracts or missing approve calls // TODO do we really need this?
    function emergency() external onlyOwner {
        EURe.transfer(owner(), EURe.balanceOf(address(this)));
    }
}
