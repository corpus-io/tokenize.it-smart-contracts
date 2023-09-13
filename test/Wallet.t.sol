// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/ContinuousFundraising.sol";
import "./resources/MintAndCallToken.sol";
import "./resources/MaliciousPaymentToken.sol";
import "../contracts/Wallet.sol";

contract WalletTest is Test {
    function setUp() public {}

    function testSignAsContract(uint256 ownerPrivateKey, address fundraising, string memory message) public {
        vm.assume(ownerPrivateKey != 0);
        vm.assume(ownerPrivateKey < 2 ** 250 - 1);
        address owner = vm.addr(ownerPrivateKey);
        vm.assume(fundraising != address(0));
        vm.assume(bytes(message).length > 0);

        bytes32 messageHash = keccak256(abi.encodePacked(message));

        Wallet wallet = new Wallet(ContinuousFundraising(fundraising));

        // todo: create signature and check with contract
    }
}
