// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "@safe-global/safe-contracts/contracts/Safe.sol";
import "@safe-global/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/ExitCloneFactory.sol";
import "../contracts/Exit.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";

/**
 * @notice Tests where a Gnosis Safe multisig is the token holder and calls Exit.claim()
 * by executing real Safe transactions (signed by an EOA owner, submitted via execTransaction).
 *
 * Safe v1.4.1 is imported directly. A remapping in remappings.txt redirects Safe's IERC165 to
 * OZ's IERC165 (they are ABI-identical) to avoid a duplicate-identifier compilation error.
 */
contract ExitSafeTest is Test {
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant exitOwner = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant recipient = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant currencyProvider = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    // DO NOT USE IN PRODUCTION -- test private key only
    uint256 constant SAFE_OWNER_PK = 0xA11CE;
    address public safeOwner;

    uint8 public constant CURRENCY_DECIMALS = 6;
    uint256 public constant PRICE_PER_TOKEN = 2e6; // 2 currency units per token
    uint256 public constant TOKEN_SUPPLY = 100e18;
    uint256 public constant TOTAL_CURRENCY = 200e6;

    uint64 public claimStart;
    uint64 public lockedUntil;

    AllowList allowList;
    FakePaymentToken currency;
    Token token;
    Exit exitLogic;
    ExitCloneFactory exitFactory;
    Exit exitContract;
    TokenProxyFactory tokenFactory;

    Safe public safe;

    function setUp() public {
        safeOwner = vm.addr(SAFE_OWNER_PK);

        claimStart = uint64(block.timestamp + 1 days);
        lockedUntil = uint64(block.timestamp + 30 days);

        // --- Token & currency ---
        allowList = createAllowList(trustedForwarder, admin);
        currency = new FakePaymentToken(0, CURRENCY_DECIMALS);
        vm.prank(admin);
        allowList.set(address(currency), TRUSTED_CURRENCY);

        address tokenLogic = address(new Token(trustedForwarder));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        IFeeSettingsV2 feeSettings = createFeeSettings(
            trustedForwarder,
            admin,
            buildFeeTypes(0, 0, 0, admin, admin, admin)
        );
        token = Token(
            tokenFactory.createTokenProxy(0, trustedForwarder, feeSettings, admin, allowList, 0, "ExitToken", "EXT")
        );

        // --- Exit contract ---
        exitLogic = new Exit(trustedForwarder);
        exitFactory = new ExitCloneFactory(address(exitLogic));

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: exitOwner,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = exitFactory.predictCloneAddress(bytes32(0), trustedForwarder, args);
        currency.mint(currencyProvider, TOTAL_CURRENCY);
        vm.prank(currencyProvider);
        currency.approve(cloneAddr, TOTAL_CURRENCY);
        exitContract = Exit(
            exitFactory.createExitClone(bytes32(0), trustedForwarder, currencyProvider, args, TOTAL_CURRENCY)
        );

        // --- Deploy Gnosis Safe v1.4.1 with safeOwner as sole owner, threshold 1 ---
        Safe singleton = new Safe();
        SafeProxyFactory proxyFactory = new SafeProxyFactory();

        address[] memory owners = new address[](1);
        owners[0] = safeOwner;

        bytes memory initData = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            1, // threshold
            address(0), // no delegate call target
            "", // no delegate call data
            address(0), // no fallback handler
            address(0), // no payment token
            0, // payment
            payable(address(0)) // payment receiver
        );

        safe = Safe(payable(address(proxyFactory.createProxyWithNonce(address(singleton), initData, 0))));

        // --- Mint tokens to the Safe ---
        vm.startPrank(admin);
        token.grantRole(token.MINTALLOWER_ROLE(), admin);
        token.mint(address(safe), TOKEN_SUPPLY);
        vm.stopPrank();
    }

    /// @dev Builds, signs (ECDSA with safeOwner's key), and executes a Safe Call transaction.
    /// Returns false when the inner call reverts (Safe's behaviour); reverts on invalid signature.
    function _execSafeTx(address to, bytes memory data) internal returns (bool) {
        bytes32 txHash = safe.getTransactionHash(
            to,
            0, // value
            data,
            Enum.Operation.Call,
            0,
            0,
            0, // safeTxGas, baseGas, gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            safe.nonce()
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SAFE_OWNER_PK, txHash);
        // Safe compact signature format: r || s || v
        bytes memory sig = abi.encodePacked(r, s, v);

        return safe.execTransaction(to, 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), sig);
    }

    // ========== Tests ==========

    function testSafeApproveAndClaim() public {
        vm.warp(claimStart);

        // Safe approves Exit to spend its full token balance
        bool approveOk = _execSafeTx(
            address(token),
            abi.encodeWithSelector(IERC20.approve.selector, address(exitContract), TOKEN_SUPPLY)
        );
        assertTrue(approveOk, "Safe approve tx should succeed");

        // Safe calls claim -- Safe is msg.sender / holder
        bool claimOk = _execSafeTx(
            address(exitContract),
            abi.encodeWithSelector(bytes4(keccak256("claim(address,uint256)")), recipient, uint256(0))
        );
        assertTrue(claimOk, "Safe claim tx should succeed");

        assertEq(currency.balanceOf(recipient), TOTAL_CURRENCY, "recipient should receive full currency");
        assertEq(token.balanceOf(address(safe)), 0, "Safe should have no tokens after full claim");
        assertEq(token.balanceOf(address(exitContract)), TOKEN_SUPPLY, "Exit should hold the claimed tokens");
    }

    function testSafeClaimDoesNotBurnTokens() public {
        vm.warp(claimStart);

        _execSafeTx(
            address(token),
            abi.encodeWithSelector(IERC20.approve.selector, address(exitContract), TOKEN_SUPPLY)
        );
        _execSafeTx(
            address(exitContract),
            abi.encodeWithSelector(bytes4(keccak256("claim(address,uint256)")), recipient, uint256(0))
        );

        assertEq(token.balanceOf(address(exitContract)), TOKEN_SUPPLY, "Exit should hold Safe's claimed tokens");
        assertEq(token.totalSupply(), TOKEN_SUPPLY, "total supply must not change (no burn)");
    }

    function testSafeClaimCurrencyGoesToRecipientNotSafe() public {
        vm.warp(claimStart);

        _execSafeTx(
            address(token),
            abi.encodeWithSelector(IERC20.approve.selector, address(exitContract), TOKEN_SUPPLY)
        );
        _execSafeTx(
            address(exitContract),
            abi.encodeWithSelector(bytes4(keccak256("claim(address,uint256)")), recipient, uint256(0))
        );

        assertEq(currency.balanceOf(recipient), TOTAL_CURRENCY, "recipient should receive correct currency");
        assertEq(currency.balanceOf(address(safe)), 0, "Safe itself should receive no currency");
    }

    function testSafeClaimBeforeStartFails() public {
        // still before claimStart
        _execSafeTx(
            address(token),
            abi.encodeWithSelector(IERC20.approve.selector, address(exitContract), TOKEN_SUPPLY)
        );

        // Pre-compute the signature so that vm.expectRevert fires on execTransaction,
        // not on the preceding nonce/hash view calls.
        bytes memory claimCalldata = abi.encodeWithSelector(
            bytes4(keccak256("claim(address,uint256)")),
            recipient,
            uint256(0)
        );
        bytes32 txHash = safe.getTransactionHash(
            address(exitContract),
            0,
            claimCalldata,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            safe.nonce()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SAFE_OWNER_PK, txHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Safe v1.4.1: when safeTxGas=0 and gasPrice=0 the Safe requires the inner call to succeed.
        // If it reverts, execTransaction itself reverts with "GS013".
        vm.expectRevert("GS013");
        safe.execTransaction(
            address(exitContract),
            0,
            claimCalldata,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            sig
        );

        assertEq(token.balanceOf(address(safe)), TOKEN_SUPPLY, "Safe token balance must be unchanged");
        assertEq(currency.balanceOf(recipient), 0, "recipient should receive no currency");
    }

    function testSafeFullClaim() public {
        vm.warp(claimStart);

        _execSafeTx(
            address(token),
            abi.encodeWithSelector(IERC20.approve.selector, address(exitContract), TOKEN_SUPPLY)
        );

        bool ok = _execSafeTx(
            address(exitContract),
            abi.encodeWithSelector(bytes4(keccak256("claim(address,uint256)")), recipient, uint256(0))
        );
        assertTrue(ok, "full claim should succeed");

        assertEq(currency.balanceOf(recipient), TOTAL_CURRENCY, "recipient should receive full currency");
        assertEq(token.balanceOf(address(safe)), 0, "Safe balance should be zero after full claim");
    }
}
