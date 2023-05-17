// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/VestingWalletFactory.sol";
import "./resources/FakePaymentToken.sol";

contract VestingWalletFactoryTest is Test {
    event Deploy(address indexed addr);

    FakePaymentToken currency; // todo: add different ERC20 token as currency!

    VestingWalletFactory factory;

    function setUp() public {
        factory = new VestingWalletFactory();
        currency = new FakePaymentToken(0, 18);
    }

    function testDeployVestingWallet(
        uint256 rawSalt,
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint256 amount
    ) public {
        vm.assume(beneficiaryAddress != address(0));
        vm.assume(startTimestamp > block.timestamp);
        vm.assume(durationSeconds > 0);
        vm.assume(amount > 0);
        //uint256 rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        address expectedAddress = factory.getAddress(salt, beneficiaryAddress, startTimestamp, durationSeconds);

        // make sure no contract lives here yet
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        assertTrue(len == 0, "A contract has already been deployed at this address");

        // take some risk: mint currency to vesting wallet before the contract is deployed
        assertTrue(currency.balanceOf(expectedAddress) == 0, "currency.balanceOf(expectedAddress) != 0");
        currency.mint(expectedAddress, amount);

        vm.expectEmit(true, true, true, true, address(factory));
        emit Deploy(expectedAddress);
        address actualAddress = factory.deploy(salt, beneficiaryAddress, startTimestamp, durationSeconds);

        assertTrue(actualAddress == expectedAddress, "actualAddress != expectedAddress");

        // make sure contract lives here now
        assembly {
            len := extcodesize(expectedAddress)
        }
        assertTrue(len != 0, "Contract deployment failed");

        // make sure withdraw fails before startTimestamp
        assert(currency.balanceOf(expectedAddress) == amount);
    }
}
