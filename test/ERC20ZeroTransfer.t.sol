// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./resources/ERC20Helper.sol";

/**
 * @dev Broken ERC20 implementation that reverts on zero transfers
 * Used to verify our tests would catch such broken behavior
 */
contract BrokenERC20 is ERC20 {
    constructor() ERC20("BrokenToken", "BROKEN") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(amount > 0, "BrokenERC20: zero transfers not allowed");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        require(amount > 0, "BrokenERC20: zero transfers not allowed");
        return super.transferFrom(from, to, amount);
    }
}

/**
 * @dev These tests verify that the trusted currencies handle zero-value transfers correctly, instead
 * of reverting.
 * Tests need a mainnet fork of the blockchain. Take a look at docs/testing.md for more information.
 */
contract ERC20ZeroTransferTest is Test {
    ERC20Helper helper = new ERC20Helper();

    address public constant sender = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant spender = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;

    function setUp() public {}

    /**
     * @dev Helper function to test zero-value transfer for a given ERC20 token
     * Tests the principle: have 0, transfer 0
     */
    function testZeroTransfer(IERC20 token, string memory tokenName) internal {
        // Verify sender has no tokens (or at least get their balance)
        uint256 senderBalance = token.balanceOf(sender);
        uint256 receiverBalanceBefore = token.balanceOf(receiver);

        // Execute zero-value transfer with zero balance
        vm.prank(sender);
        bool success = token.transfer(receiver, 0);

        // Verify transfer succeeded
        assertTrue(success, string.concat(tokenName, ": zero transfer should succeed"));

        // Verify balances unchanged
        assertEq(
            token.balanceOf(sender),
            senderBalance,
            string.concat(tokenName, ": sender balance should remain unchanged")
        );
        assertEq(
            token.balanceOf(receiver),
            receiverBalanceBefore,
            string.concat(tokenName, ": receiver balance should remain unchanged")
        );

        console.log(tokenName, "zero transfer: SUCCESS");
    }

    /**
     * @dev Helper function to test zero-value transferFrom for a given ERC20 token
     * Tests the principle: have 0, transfer 0
     */
    function testZeroTransferFrom(IERC20 token, string memory tokenName) internal {
        uint256 allowanceAmount = 500 * 10 ** 18;

        // Verify sender has no tokens (or at least get their balance) and approve spender
        uint256 senderBalance = token.balanceOf(sender);
        vm.prank(sender);
        token.approve(spender, allowanceAmount);

        // Verify initial state
        assertEq(
            token.allowance(sender, spender),
            allowanceAmount,
            string.concat(tokenName, ": spender should have allowance")
        );
        uint256 receiverBalanceBefore = token.balanceOf(receiver);

        // Execute zero-value transferFrom
        vm.prank(spender);
        bool success = token.transferFrom(sender, receiver, 0);

        // Verify transfer succeeded
        assertTrue(success, string.concat(tokenName, ": zero transferFrom should succeed"));

        // Verify balances and allowance unchanged
        assertEq(
            token.balanceOf(sender),
            senderBalance,
            string.concat(tokenName, ": sender balance should remain unchanged")
        );
        assertEq(
            token.balanceOf(receiver),
            receiverBalanceBefore,
            string.concat(tokenName, ": receiver balance should remain unchanged")
        );
        assertEq(
            token.allowance(sender, spender),
            allowanceAmount,
            string.concat(tokenName, ": allowance should remain unchanged")
        );

        console.log(tokenName, "zero transferFrom: SUCCESS");
    }

    // Individual test functions for USDC
    function testUSDCZeroTransferMainnet() public {
        testZeroTransfer(USDC, "USDC");
    }

    function testUSDCZeroTransferFromMainnet() public {
        testZeroTransferFrom(USDC, "USDC");
    }

    // Individual test functions for WETH
    function testWETHZeroTransferMainnet() public {
        testZeroTransfer(WETH, "WETH");
    }

    function testWETHZeroTransferFromMainnet() public {
        testZeroTransferFrom(WETH, "WETH");
    }

    // Individual test functions for WBTC
    function testWBTCZeroTransferMainnet() public {
        testZeroTransfer(WBTC, "WBTC");
    }

    function testWBTCZeroTransferFromMainnet() public {
        testZeroTransferFrom(WBTC, "WBTC");
    }

    // Individual test functions for EUROC
    function testEUROCZeroTransferMainnet() public {
        testZeroTransfer(EUROC, "EUROC");
    }

    function testEUROCZeroTransferFromMainnet() public {
        testZeroTransferFrom(EUROC, "EUROC");
    }

    // Individual test functions for DAI
    function testDAIZeroTransferMainnet() public {
        testZeroTransfer(DAI, "DAI");
    }

    function testDAIZeroTransferFromMainnet() public {
        testZeroTransferFrom(DAI, "DAI");
    }

    // Individual test functions for EURe
    function testEUReZeroTransferMainnet() public {
        testZeroTransfer(EURe, "EURe");
    }

    function testEUReZeroTransferFromMainnet() public {
        testZeroTransferFrom(EURe, "EURe");
    }

    // Negative tests with broken ERC20 to verify our test infrastructure works
    function testBrokenERC20ZeroTransferReverts() public {
        BrokenERC20 brokenToken = new BrokenERC20();

        // Get initial balances
        uint256 senderBalance = brokenToken.balanceOf(sender);
        uint256 receiverBalanceBefore = brokenToken.balanceOf(receiver);

        // Execute zero-value transfer and expect revert
        vm.prank(sender);
        vm.expectRevert("BrokenERC20: zero transfers not allowed");
        brokenToken.transfer(receiver, 0);

        // Verify balances unchanged after revert
        assertEq(brokenToken.balanceOf(sender), senderBalance, "Sender balance should be unchanged");
        assertEq(brokenToken.balanceOf(receiver), receiverBalanceBefore, "Receiver balance should be unchanged");

        console.log("BrokenERC20 zero transfer: correctly reverted");
    }

    function testBrokenERC20ZeroTransferFromReverts() public {
        BrokenERC20 brokenToken = new BrokenERC20();
        uint256 allowanceAmount = 500 * 10 ** 18;

        // Get initial balance and approve spender
        uint256 senderBalance = brokenToken.balanceOf(sender);
        vm.prank(sender);
        brokenToken.approve(spender, allowanceAmount);

        // Verify initial state
        assertEq(brokenToken.allowance(sender, spender), allowanceAmount, "Spender should have allowance");
        uint256 receiverBalanceBefore = brokenToken.balanceOf(receiver);

        // Execute zero-value transferFrom and expect revert
        vm.prank(spender);
        vm.expectRevert("BrokenERC20: zero transfers not allowed");
        brokenToken.transferFrom(sender, receiver, 0);

        // Verify balances and allowance unchanged after revert
        assertEq(brokenToken.balanceOf(sender), senderBalance, "Sender balance should be unchanged");
        assertEq(brokenToken.balanceOf(receiver), receiverBalanceBefore, "Receiver balance should be unchanged");
        assertEq(brokenToken.allowance(sender, spender), allowanceAmount, "Allowance should be unchanged");

        console.log("BrokenERC20 zero transferFrom: correctly reverted");
    }
}
