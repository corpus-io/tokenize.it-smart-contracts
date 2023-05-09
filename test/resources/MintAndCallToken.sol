// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../../node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../../contracts/interfaces/ERC1363.sol";

/*
    fake currency to test the mint and call feature
*/
contract MintAndCallToken is ERC20, Ownable {
    uint8 decimalPlaces;

    constructor(uint8 _decimals) ERC20("MintAndCallToken", "MACT") Ownable() {
        decimalPlaces = _decimals;
    }

    /// @dev price definition and deal() function rely on proper handling of decimalPlaces. Therefore we need to test if decimalPlaces other than 18 work fine, too.
    function decimals() public view override returns (uint8) {
        return decimalPlaces;
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function mintAndCall(address _to, uint256 _amount, bytes memory _data) external onlyOwner {
        _mint(_to, _amount);
        ERC1363Receiver(_to).onTransferReceived(msg.sender, address(0), _amount, _data);
    }
}
