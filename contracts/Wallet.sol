// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "./interfaces/ERC1363.sol";
import "./ContinuousFundraising.sol";

/**
 * @title Wallet
 * @notice A wallet contract that can react to receiving ERC20 payment tokens according to the ERC1363 standard.
 * The owner can associate a hash that will be inlcuded in the data field of the onTokenTransfer call
 * with an address. When the wallet receives payment tokens with this hash in the data field, it will buy
 * company tokens from the company's fundraising contract and send them to the address associated with the hash.
 * @dev This implementation of the ERC1363Receiver interface is not fully compliant with the standard, because
 * we never revert after onTransferReceived. See function details for more information.
 */
contract Wallet is Ownable2Step, ERC1363Receiver, IERC1271 {
    using SafeERC20 for IERC20;
    /**
     * @notice stores the receiving address for each IBAN hash
     */
    mapping(bytes32 => address) public receiverAddress;

    ContinuousFundraising public fundraising;

    event Set(bytes32 indexed ibanHash, address tokenReceiver);

    constructor(ContinuousFundraising _fundraising) Ownable2Step() {
        fundraising = _fundraising;
    }

    /**
     * @notice sets (or updates) the receiving address for an IBAN hash
     * @param _ibanHash the hash of the IBAN to set the receiving address for
     * @param _tokenReceiver the address to send the tokens to
     */
    function set(bytes32 _ibanHash, address _tokenReceiver) external onlyOwner {
        receiverAddress[_ibanHash] = _tokenReceiver;
        emit Set(_ibanHash, _tokenReceiver);
    }

    /**
     * @notice ERC1363 callback
     * @dev To support the mintAndCall standard, this function MUST NOT revert! It deviates from the ERC1363
     * standard in this regard. The intended use of monerium tokens, which are minted after a SEPA transfer,
     * makes this necessary. If the intended action of buying tokens fails, the payment tokens remain in balance
     * of the wallet contract. The owner can withdraw them later.
     * @param operator The address which called `transferAndCall` or `transferFromAndCall` function
     * @param from The address which are token transferred from
     * @param value The amount of tokens transferred
     * @return 0x600D600D on success, 0x0BAD0BAD if the buy failed, 0xDEADD00D if the receiver is not registered
     */
    function onTransferReceived(
        address operator,
        address from,
        uint256 value,
        bytes memory data
    ) external override returns (bytes4) {
        bytes32 ibanHash = abi.decode(data, (bytes32));
        if (receiverAddress[ibanHash] == address(0)) {
            return 0xDEADD00D; // DEAD DOOD: ReceiverNotRegistered
        }
        IERC20 paymentCurrency = fundraising.currency();
        if (_msgSender() != address(paymentCurrency)) {
            return 0x4B1D4B1D; // FORBID FORBID: OperatorNotPaymentCurrency
        }
        uint256 amount = fundraising.calculateBuyAmount(value);
        // grant allowance to fundraising
        paymentCurrency.approve(address(fundraising), amount);
        // try buying tokens https://solidity-by-example.org/try-catch/
        try fundraising.buy(amount, receiverAddress[ibanHash]) {
            return 0x600D600D; // ReceiverSuccess
        } catch {
            return 0x0BAD0BAD; // ReceiverFailure
        }
    }

    /**
     * @notice withdraws tokens to a given address
     * @param token the token to withdraw
     * @param to the address to send the tokens to
     * @param amount the amount of tokens to send
     */
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice withdraws ETH to a given address
     * @param to the address to send the ETH to
     * @param amount the amount of ETH to send
     */
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        to.transfer(amount);
    }

    /**
     * @notice enable signing of messages in the name of the contract using the owner's private key
     * @dev Messages signed by an owner will be valid without a deadline. However, once the contract's owner changes, all old signatures will be invalid.
     * @param _hash the hash of the data to be signed
     * @param _signature the signature to be checked
     * @return 0x1626ba7e
     */
    function isValidSignature(bytes32 _hash, bytes memory _signature) public view override returns (bytes4) {
        if (owner() == address(0)) {
            // in case the ownership if the contract has been renounced, nobody should be able to sign in its name anymore
            return bytes4(0);
        }
        return ECDSA.recover(_hash, _signature) == owner() ? this.isValidSignature.selector : bytes4(0);
    }
}
