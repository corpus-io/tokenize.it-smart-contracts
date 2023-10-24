// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

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
        uint64 durationSeconds
    ) public {
        vm.assume(beneficiaryAddress != address(0));
        vm.assume(startTimestamp > block.timestamp);
        vm.assume(durationSeconds > 0);
        //uint256 rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        address expectedAddress = factory.getAddress(salt, beneficiaryAddress, startTimestamp, durationSeconds);

        // make sure no contract lives here yet
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        assertTrue(len == 0, "A contract has already been deployed at this address");

        vm.expectEmit(true, true, true, true, address(factory));
        emit Deploy(expectedAddress);
        address actualAddress = factory.deploy(salt, beneficiaryAddress, startTimestamp, durationSeconds);

        assertTrue(actualAddress == expectedAddress, "actualAddress != expectedAddress");

        // make sure contract lives here now
        assembly {
            len := extcodesize(expectedAddress)
        }
        assertTrue(len != 0, "Contract deployment failed");
    }

    function testWalletVestsAsExpected(
        uint256 rawSalt,
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint256 amount
    ) public {
        vm.assume(beneficiaryAddress != address(0));
        vm.assume(startTimestamp > block.timestamp);
        vm.assume(type(uint64).max - durationSeconds > startTimestamp);
        vm.assume(amount < type(uint128).max);
        vm.assume(amount > 0);
        vm.assume(durationSeconds > 0);
        //uint256 rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        VestingWallet vestingWallet = VestingWallet(
            payable(factory.deploy(salt, beneficiaryAddress, startTimestamp, durationSeconds))
        );

        // mint currency to vesting wallet
        assertTrue(currency.balanceOf(address(vestingWallet)) == 0, "currency.balanceOf(expectedAddress) != 0");
        currency.mint(address(vestingWallet), amount);
        assertTrue(currency.balanceOf(address(vestingWallet)) == amount, "currency balance wrong");

        // make sure nothing can be withdrawn before startTimestamp
        assertTrue(vestingWallet.releasable(address(currency)) == 0, "tokens are releasable before startTimestamp");

        // make sure nothing can be withdrawn at startTimestamp
        vm.warp(startTimestamp);
        assertTrue(vestingWallet.releasable(address(currency)) == 0, "tokens are releasable at startTimestamp");

        // make sure everything can be withdrawn at startTimestamp + durationSeconds
        vm.warp(startTimestamp + durationSeconds);
        assertTrue(vestingWallet.releasable(address(currency)) == amount, "tokens are not releasable at end");

        // withdraw and check amount
        assertTrue(currency.balanceOf(beneficiaryAddress) == 0, "beneficiary already has currency");
        vestingWallet.release(address(currency));
        assertTrue(currency.balanceOf(beneficiaryAddress) == amount, "beneficiary has wrong amount of currency");
    }
}
