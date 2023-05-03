// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "../contracts/Token.sol";
import "../contracts/ContinuousFundraising.sol";
import "../contracts/PersonalInvite.sol";
import "../contracts/PersonalInviteFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/ERC20Helper.sol";


/**
 * @dev These tests need a mainnet fork of the blockchain, as they access contracts deployed on mainnet. Take a look at docs/testing.md for more information.
 */

contract MainnetCurrencies is Test {
    using SafeERC20 for IERC20;

    ERC20Helper helper = new ERC20Helper();


    uint256 public constant tokenOwnerPrivateKey =
        0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public tokenOwner = vm.addr(tokenOwnerPrivateKey); // = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    // use opengsn forwarder https://etherscan.io/address/0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA
    address public constant trustedForwarder =
        0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA;

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token
    uint256 public constant amountOfTokenToBuy = maxAmountPerBuyer;

    // some math
    uint256 public constant price = 7 * 10 ** 18;
    uint256 public currencyCost;
    uint256 public currencyAmount;

    // global variable because I am running out of local ones
    uint256 nonce;
    uint256 deadline;
    bytes32 permitTypehash;
    bytes32 DOMAIN_SEPARATOR;
    bytes32 structHash;

    function setUp() public {
        
    }

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
        permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();
        structHash = keccak256(
            abi.encode(
                permitTypehash,
                tokenOwner,
                tokenSpender,
                _tokenPermitAmount,
                nonce,
                deadline
            )
        );

        bytes32 hash = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_tokenOwnerPrivateKey, hash);

        // verify signature
        require(
            tokenOwner == ECDSA.recover(hash, v, r, s),
            "invalid signature"
        );

        // check allowance
        assertEq(token.allowance(tokenOwner, tokenSpender), 0, "allowance should be 0");

        // call permit with a wallet that is not tokenOwner
        token.permit(
            tokenOwner,
            tokenSpender,
            _tokenPermitAmount,
            deadline,
            v,
            r,
            s
        );

        // check allowance
        assertEq(token.allowance(tokenOwner, tokenSpender), _tokenPermitAmount, "allowance should be _tokenPermitAmount");

        // check token balance of tokenSpender
        assertEq(token.balanceOf(tokenOwner), _tokenPermitAmount, "token balance of tokenOwner should be _tokenPermitAmount");
        assertEq(token.balanceOf(tokenSpender), 0, "token balance of tokenSpender should be 0");

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
        assertEq(token.balanceOf(tokenSpender), _tokenTransferAmount, "token balance of tokenSpender should be _tokenTransferAmount");
    }

    function testPermitEUROC() public {
        permitERC2612(ERC20Permit(address(EUROC)), 200, 100, tokenOwnerPrivateKey, address(2));
    }

    // still fails for some reason
    // function testPermitUSDC() public {
    //     permitERC2612(ERC20Permit(address(USDC)), 200, 100, tokenOwnerPrivateKey, address(2));
    // }
}
