// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/MoneriumI.sol";

/*
The contract is deployed by the fundraising company and is getting an IBAN by Monerium. By sending EUR to this IBAN, the investors agrees to the investment.
The then minted EURe are approved for the corresponding investment contract. In case of an personal invite, it can be executed by the company.
In ces of a continuous fundraising, the investor can now call the `buy`function in order to make an investment.
This contract is inteneded to be used only once per investment per investor.
*/

contract MoneriumInterfacePersonalInvite is MoneriumI {
    address public investor;

    constructor(address _investor, address _investment, uint256 _amount) {
        investor = _investor;
        IERC20(0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f).approve(
            address(_investment),
            _amount
        );
    }

    /* warning: In the case the investment contract does not work anymore (expired personal invites, paused fundraising, ...). All the EURe in this contract are techincally stuck.
    But since this IBAN belongs to the company, they can make a IBAN transfer back to the investor using the Monerium WebApp. Monerium will then burn the tokens belonging to this address.
    */
}
