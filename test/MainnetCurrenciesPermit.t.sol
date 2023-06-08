// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/Token.sol";
import "../contracts/ContinuousFundraising.sol";
import "../contracts/PersonalInvite.sol";
import "../contracts/PersonalInviteFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/ERC20Helper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface DaiLike is IERC20 {
    function PERMIT_TYPEHASH() external view returns (bytes32);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/**
 * @dev These tests need a mainnet fork of the blockchain, as they access contracts deployed on mainnet. Take a look at docs/testing.md for more information.
 */
contract MainnetCurrencies is Test {
    using SafeERC20 for IERC20;

    ERC20Helper helper = new ERC20Helper();

    uint256 public constant tokenOwnerPrivateKey = 0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public tokenOwner = vm.addr(tokenOwnerPrivateKey); // = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;

    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;

    // global variable because I am running out of local ones
    uint256 nonce;
    uint256 deadline;
    bytes32 PERMIT_TYPE_HASH;
    bytes32 DOMAIN_SEPARATOR;
    bytes32 structHash;

    function setUp() public {}

    function permitERC2612(
        ERC20Permit token,
        uint256 _tokenPermitAmount,
        uint256 _tokenTransferAmount,
        uint256 _tokenOwnerPrivateKey,
        address tokenSpender
    ) public {
        vm.assume(_tokenTransferAmount <= _tokenPermitAmount);
        tokenOwner = vm.addr(_tokenOwnerPrivateKey);
        helper.writeERC20Balance(tokenOwner, address(token), _tokenPermitAmount);

        // permit spender to spend holder's tokens
        nonce = token.nonces(tokenOwner);
        deadline = block.timestamp + 1000;
        PERMIT_TYPE_HASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();
        structHash = keccak256(
            abi.encode(PERMIT_TYPE_HASH, tokenOwner, tokenSpender, _tokenPermitAmount, deadline, nonce)
        );

        bytes32 hash = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_tokenOwnerPrivateKey, hash);

        // verify signature
        require(tokenOwner == ECDSA.recover(hash, v, r, s), "invalid signature");

        // check allowance
        assertEq(token.allowance(tokenOwner, tokenSpender), 0, "allowance should be 0");

        // call permit as and address a that is not tokenOwner
        assertTrue(address(this) != tokenOwner, "address(this) must not be tokenOwner");
        token.permit(tokenOwner, tokenSpender, _tokenPermitAmount, deadline, v, r, s);

        // check allowance
        assertEq(
            token.allowance(tokenOwner, tokenSpender),
            _tokenPermitAmount,
            "allowance should be _tokenPermitAmount"
        );

        assertEq(
            token.balanceOf(tokenOwner),
            _tokenPermitAmount,
            "token balance of tokenOwner should be _tokenPermitAmount"
        );
        // store token balance of tokenSpender
        uint tokenSpenderBalanceBefore = token.balanceOf(tokenSpender);

        console.log("Tranfering %s tokens from %s to %s", _tokenPermitAmount, tokenOwner, tokenSpender);
        // spend tokens
        vm.prank(tokenSpender);
        token.transferFrom(tokenOwner, tokenSpender, _tokenTransferAmount);

        // check token balance of tokenSpender
        assertEq(
            token.balanceOf(tokenOwner),
            _tokenPermitAmount - _tokenTransferAmount,
            "token balance of tokenOwner should be _tokenPermitAmount - _tokenTransferAmount"
        );
        assertEq(
            token.balanceOf(tokenSpender),
            _tokenTransferAmount + tokenSpenderBalanceBefore,
            "token balance of tokenSpender should be _tokenTransferAmount"
        );
    }

    function testDebugTrouble() public {
        /*
            data for mainnet
        */
        ERC20Permit token = ERC20Permit(0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c);
        uint256 tokenPermitAmount = 1800000000;
        uint8 v = 27;
        bytes32 r = 0x6a563919a587bda53a1482d716bae140eae93bc19e458c9af99c903a83d566d8;
        bytes32 s = 0x4de5f3efd908d130d97c62042bb7d9f322a93ee405fede7a016b8511d3abdbb9;
        tokenOwner = 0xe8ef87DB07d9FD0544Ff1ECDa896f14208E4e207;
        address tokenSpender = 0x625F73836E72Da0b0819a0dD1427CF925592bcFd;
        nonce = 0; //token.nonces(tokenOwner);
        deadline = 1687392000; //1687392000;
        DOMAIN_SEPARATOR = 0x99f188f447f0c6eaf68589359cd2ead8c2faaaaee984ab926fdb734d0040073b; // wrong separator on mainnet

        console.log("Domain separator tests");
        bytes32 domainSeparator = keccak256(
            abi.encode(
                // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                keccak256(bytes("SSS Coin")),
                keccak256(bytes("2")),
                1,
                address(token)
            )
        );
        console.log("domainSeparator:");
        console.logBytes32(domainSeparator);

        /*
            data for goerli
        */
        // ERC20Permit token = ERC20Permit(0xA683d909e996052955500DDc45CA13E25c76e286);
        // tokenOwner = 0xe8ef87DB07d9FD0544Ff1ECDa896f14208E4e207;
        // address tokenSpender = 0x0D4bE5bBE1e481576c0483BF355684CF5DF10b57;
        // uint256 tokenPermitAmount = 2000000;
        // uint8 v = 28;
        // bytes32 r = 0x8cbd86cbff62452aab8f05ad5affacb43cb910e03904466627fb58a23f44601e;
        // bytes32 s = 0x176899a64446d974f1c7c7495de14069597500ffb4284d22cb9734b0c3b81cc1;
        // nonce = 0; //token.nonces(tokenOwner);
        // deadline = 1687478400; //1687392000;
        // DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();

        // console.log("Domain separator tests");
        // bytes32 domainSeparator = keccak256(
        //     abi.encode(
        //         // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        //         0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
        //         keccak256(bytes("Euro Coin")),
        //         keccak256(bytes("2")),
        //         5,
        //         address(token)
        //     )
        // );
        // console.log("domainSeparator:");
        // console.logBytes32(domainSeparator);

        PERMIT_TYPE_HASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        console.log("PERMIT_TYPE_HASH:");
        console.logBytes32(PERMIT_TYPE_HASH);

        console.log("DOMAIN_SEPARATOR:");
        console.logBytes32(DOMAIN_SEPARATOR);
        console.log("keccak256(abi.encode(DOMAIN_SEPARATOR)):");
        console.logBytes32(keccak256(abi.encode(DOMAIN_SEPARATOR)));
        structHash = keccak256(
            abi.encode(PERMIT_TYPE_HASH, tokenOwner, tokenSpender, tokenPermitAmount, nonce, deadline)
        );

        console.log("structHash:");
        console.logBytes32(structHash);

        bytes32 hash = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        console.log("hash:");
        console.logBytes32(hash);

        console.log("signer: %s ", ECDSA.recover(hash, v, r, s));

        if (tokenOwner == ECDSA.recover(hash, v, r, s)) {
            console.log("matches");
        } else console.log("does not match");
    }

    function testPermitMainnetEUROC() public {
        permitERC2612(ERC20Permit(address(EUROC)), 200, 123, tokenOwnerPrivateKey, receiver);
    }

    function testPermitMainnetUSDC() public {
        permitERC2612(ERC20Permit(address(USDC)), 200, 190, tokenOwnerPrivateKey, receiver);
    }

    /**
     * @dev This test takes into account the special permit implementation of DAI
     */
    function testPermitMainnetDAI() public {
        DaiLike token = DaiLike(address(DAI));
        uint256 _tokenPermitAmount = 200;
        uint256 _tokenTransferAmount = 70;
        tokenOwner = vm.addr(tokenOwnerPrivateKey);
        address tokenSpender = receiver;

        vm.assume(_tokenTransferAmount <= _tokenPermitAmount);
        tokenOwner = vm.addr(tokenOwnerPrivateKey);
        helper.writeERC20Balance(tokenOwner, address(token), _tokenPermitAmount);

        // permit spender to spend ALL OF the owner's tokens. This is the special case for DAI.
        bool allowed = true;
        nonce = token.nonces(tokenOwner);
        deadline = block.timestamp + 1000;
        DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();
        structHash = keccak256(
            abi.encode(DaiLike(address(token)).PERMIT_TYPEHASH(), tokenOwner, tokenSpender, nonce, deadline, allowed)
        );

        bytes32 hash = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(tokenOwnerPrivateKey, hash);

        // verify signature
        require(tokenOwner == ECDSA.recover(hash, v, r, s), "invalid signature");

        // check allowance
        assertEq(token.allowance(tokenOwner, tokenSpender), 0, "allowance should be 0");

        // call permit as and address a that is not tokenOwner
        assertTrue(address(this) != tokenOwner, "address(this) must not be tokenOwner");

        DaiLike(address(token)).permit(tokenOwner, tokenSpender, nonce, deadline, true, v, r, s);

        // check allowance
        assertEq(token.allowance(tokenOwner, tokenSpender), UINT256_MAX, "allowance should be UINT256_MAX");

        assertEq(
            token.balanceOf(tokenOwner),
            _tokenPermitAmount,
            "token balance of tokenOwner should be _tokenPermitAmount"
        );
        // store token balance of tokenSpender
        uint tokenSpenderBalanceBefore = token.balanceOf(tokenSpender);

        console.log("Tranfering %s tokens from %s to %s", _tokenPermitAmount, tokenOwner, tokenSpender);
        // spend tokens
        vm.prank(tokenSpender);
        token.transferFrom(tokenOwner, tokenSpender, _tokenTransferAmount);

        // check token balance of tokenSpender
        assertEq(
            token.balanceOf(tokenOwner),
            _tokenPermitAmount - _tokenTransferAmount,
            "token balance of tokenOwner should be _tokenPermitAmount - _tokenTransferAmount"
        );
        assertEq(
            token.balanceOf(tokenSpender),
            _tokenTransferAmount + tokenSpenderBalanceBefore,
            "token balance of tokenSpender should be _tokenTransferAmount"
        );
    }

    // sadly, WETH and WBTC seem not to support permit or an equivalent meta transaction
}
