// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ERC1363.sol";
import "./ContinuousFundraising.sol";

/**

 */

contract Wallet is Ownable2Step, ERC1363Receiver {
    using SafeERC20 for IERC20;
    /**
    @notice stores the receiving address for each IBAN hash
    */
    mapping(bytes32 => address) public receiverAddress;

    ContinuousFundraising public fundraising;

    event Set(bytes32 indexed ibanHash, address tokenReceiver);

    constructor(ContinuousFundraising _fundraising) Ownable2Step() {
        fundraising = _fundraising;
    }

    /**
    @notice sets (or updates) the receiving address for an IBAN hash
    */
    function set(bytes32 _ibanHash, address _tokenReceiver) external onlyOwner {
        receiverAddress[_ibanHash] = _tokenReceiver;
        emit Set(_ibanHash, _tokenReceiver);
    }

    /**
     * @notice ERC1363 callback
     * @dev to support the mintAndCall standard, this function MUST NOT revert!
     */
    function onTransferReceived(
        address operator,
        address from,
        uint256 value,
        bytes memory data
    ) external override returns (bytes4) {
        bytes32 ibanHash = abi.decode(data, (bytes32));
        if (receiverAddress[ibanHash] == address(0)) {
            return bytes4(0xDEADD00D); // ERC1363ReceiverNotRegistered
        }
        address tokenReceiver = receiverAddress[ibanHash];
        // todo: calculate amount
        uint256 amount = 100;
        // grant allowance to fundraising
        IERC20(fundraising.currency()).approve(address(fundraising), amount);
        // todo: add try catch https://solidity-by-example.org/try-catch/
        fundraising.buy(amount, tokenReceiver);
        return 0x600D600D; // ERC1363ReceiverSuccess
    }

    /*
    @notice withdraws tokens to a given address
    */
    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransferFrom(address(this), to, amount);
    }
}
