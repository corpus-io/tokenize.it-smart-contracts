// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
//import "../lib/forge-std/stdlib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/PrivateOffer.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/TimeLockCloneFactory.sol";
import "../contracts/TimeLock.sol";
import "./resources/CloneCreators.sol";
import "./resources/ERC20Helper.sol";

/**
 * @dev These tests need a mainnet fork of the blockchain, as they access contracts deployed on mainnet. Take a look at docs/testing.md for more information.
 */

contract MainnetCurrencies is Test {
    using SafeERC20 for IERC20;

    ERC20Helper helper = new ERC20Helper();

    AllowList list;
    FeeSettings feeSettings;

    Token token;
    PrivateOfferFactory inviteFactory;

    CrowdinvestingCloneFactory fundraisingFactory;

    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant BUYER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant PAYMENT_TOKEN_PROVIDER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    // use opengsn forwarder https://etherscan.io/address/0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA
    address public constant TRUSTED_FORWARDER = 0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA;

    uint256 public constant MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD = 20 * 10 ** 18; // 20 token
    uint256 public constant MAX_AMOUNT_PER_BUYER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2; // 10 token
    uint256 public constant MIN_AMOUNT_PER_BUYER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 200; // 0.1 token
    uint256 public constant AMOUNT_OF_TOKEN_TO_BUY = MAX_AMOUNT_PER_BUYER;

    // some math
    uint256 public constant PRICE = 7 * 10 ** 18;
    uint256 public currencyCost;
    uint256 public currencyAmount;

    // generate address of invite
    bytes32 salt = bytes32(0);

    // // test currencies
    // IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    // IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // IERC20 WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    // IERC20 EUROC = IERC20(0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c);
    // IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function setUp() public {
        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(100, 100, 100, ADMIN, ADMIN, ADMIN)
        );

        Token implementation = new Token(TRUSTED_FORWARDER);
        TokenProxyFactory tokenCloneFactory = new TokenProxyFactory(address(implementation));
        token = Token(
            tokenCloneFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, list, 0x0, "TESTTOKEN", "TEST")
        );

        fundraisingFactory = new CrowdinvestingCloneFactory(address(new Crowdinvesting(TRUSTED_FORWARDER)));

        TimeLock timeLockImplementation = new TimeLock(TRUSTED_FORWARDER);
        TimeLockCloneFactory timeLockCloneFactory = new TimeLockCloneFactory(address(timeLockImplementation));
        inviteFactory = new PrivateOfferFactory(timeLockCloneFactory);
        currencyCost = (AMOUNT_OF_TOKEN_TO_BUY * PRICE) / 10 ** token.decimals();
        currencyAmount = currencyCost * 2;
    }

    /** 
        @notice sets the balance of who to amount
        taken from here: https://mirror.xyz/brocke.eth/PnX7oAcU4LJCxcoICiaDhq_MUUu9euaM8Y5r465Rd2U
    */
    // function writeERC20Balance(
    //     address who,
    //     address _token,
    //     uint256 amount
    // ) internal {
    //     stdstore
    //         .target(_token)
    //         .sig(IERC20(_token).balanceOf.selector)
    //         .with_key(who)
    //         .checked_write(amount);
    // }

    function crowdinvestingWithIERC20Currency(IERC20 _currency) public {
        // some math
        //uint _decimals = _currency.decimals(); // can't get decimals from IERC20
        //uint _price = 7 * 10**_decimals; // 7 payment tokens per token
        uint256 _price = 7 * 10 ** 18;
        uint256 _currencyCost = (AMOUNT_OF_TOKEN_TO_BUY * _price) / 10 ** token.decimals();
        uint256 _currencyAmount = _currencyCost * 2;

        vm.prank(OWNER);
        list.set(address(_currency), TRUSTED_CURRENCY);

        // set up fundcrowdinvesting with _currency

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            OWNER,
            payable(RECEIVER),
            MIN_AMOUNT_PER_BUYER,
            MAX_AMOUNT_PER_BUYER,
            _price,
            _price,
            _price,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            _currency,
            token,
            type(uint256).max,
            address(0),
            address(0)
        );
        Crowdinvesting _crowdinvesting = Crowdinvesting(
            fundraisingFactory.createCrowdinvestingClone(0, TRUSTED_FORWARDER, arguments)
        );

        // allow crowdinvesting contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(address(_crowdinvesting), MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);

        // give the BUYER funds
        //console.log("BUYER's balance: ", _currency.balanceOf(BUYER));
        helper.writeERC20Balance(BUYER, address(_currency), _currencyAmount);
        //console.log("BUYER's balance: ", _currency.balanceOf(BUYER));

        // give crowdinvesting contract a currency allowance
        vm.prank(BUYER);
        _currency.approve(address(_crowdinvesting), _currencyCost);

        // make sure BUYER has no tokens before and RECEIVER has no _currency before
        assertEq(token.balanceOf(BUYER), 0);
        assertEq(token.balanceOf(RECEIVER), 0);
        assertEq(_currency.balanceOf(RECEIVER), 0);
        assertEq(_currency.balanceOf(BUYER), _currencyAmount);

        // buy tokens
        vm.prank(BUYER);
        _crowdinvesting.buy(MAX_AMOUNT_PER_BUYER, type(uint256).max, BUYER);

        // check BUYER has tokens and RECEIVER has _currency afterwards
        assertEq(token.balanceOf(BUYER), AMOUNT_OF_TOKEN_TO_BUY, "BUYER has tokens");
        assertEq(token.balanceOf(RECEIVER), 0, "RECEIVER has no tokens");
        assertEq(
            _currency.balanceOf(RECEIVER),
            _currencyCost - FeeSettings(address(token.feeSettings())).crowdinvestingFee(_currencyCost, address(token)),
            "RECEIVER should have received currency"
        );
        assertEq(
            _currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            FeeSettings(address(token.feeSettings())).crowdinvestingFee(_currencyCost, address(token)),
            "fee RECEIVER should have received currency"
        );
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            FeeSettings(address(token.feeSettings())).crowdinvestingFee(AMOUNT_OF_TOKEN_TO_BUY, address(token)),
            "fee RECEIVER should have received tokens"
        );
        assertEq(_currency.balanceOf(BUYER), _currencyAmount - _currencyCost, "BUYER should have paid currency");
    }

    function testCrowdinvestingWithMainnetUSDC() public {
        crowdinvestingWithIERC20Currency(USDC);
    }

    function testCrowdinvestingWithMainnetWETH() public {
        crowdinvestingWithIERC20Currency(WETH);
    }

    function testCrowdinvestingWithMainnetWBTC() public {
        crowdinvestingWithIERC20Currency(WBTC);
    }

    function testCrowdinvestingWithMainnetEUROC() public {
        crowdinvestingWithIERC20Currency(EUROC);
    }

    function testCrowdinvestingWithMainnetDAI() public {
        crowdinvestingWithIERC20Currency(DAI);
    }

    function privateOfferWithIERC20Currency(IERC20 _currency) public {
        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 expiration = block.timestamp + 1000;

        vm.prank(OWNER);
        list.set(address(_currency), TRUSTED_CURRENCY);

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            BUYER,
            BUYER,
            RECEIVER,
            AMOUNT_OF_TOKEN_TO_BUY,
            PRICE,
            expiration,
            _currency,
            token,
            address(0)
        );
        address expectedAddress = inviteFactory.predictPrivateOfferAddress(salt, arguments);

        // grant mint allowance to invite
        vm.prank(ADMIN);
        token.increaseMintingAllowance(expectedAddress, AMOUNT_OF_TOKEN_TO_BUY);

        // give the BUYER funds and approve invite
        helper.writeERC20Balance(BUYER, address(_currency), currencyAmount);
        vm.prank(BUYER);
        _currency.approve(address(expectedAddress), currencyCost);

        // make sure balances are as expected before deployment
        assertEq(_currency.balanceOf(BUYER), currencyAmount);
        assertEq(_currency.balanceOf(RECEIVER), 0);
        assertEq(token.balanceOf(BUYER), 0);
        assertEq(token.balanceOf(RECEIVER), 0);

        // deploy invite
        address inviteAddress = inviteFactory.deployPrivateOffer(salt, arguments);

        // check situation after deployment
        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");
        // check BUYER has tokens and RECEIVER has _currency afterwards
        assertEq(token.balanceOf(BUYER), AMOUNT_OF_TOKEN_TO_BUY, "BUYER has tokens");
        assertEq(token.balanceOf(RECEIVER), 0, "RECEIVER has no tokens");
        assertEq(
            _currency.balanceOf(RECEIVER),
            currencyCost - FeeSettings(address(token.feeSettings())).crowdinvestingFee(currencyCost, address(token)),
            "RECEIVER should have received currency"
        );
        assertEq(
            _currency.balanceOf(FeeSettings(address(token.feeSettings())).crowdinvestingFeeCollector(address(token))),
            FeeSettings(address(token.feeSettings())).crowdinvestingFee(currencyCost, address(token)),
            "fee RECEIVER should have received currency"
        );
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            FeeSettings(address(token.feeSettings())).tokenFee(AMOUNT_OF_TOKEN_TO_BUY, address(token)),
            "fee RECEIVER should have received tokens"
        );
        assertEq(_currency.balanceOf(BUYER), currencyAmount - currencyCost, "BUYER should have paid currency");

        // log buyers token balance
        console.log("BUYER's token balance: ", token.balanceOf(BUYER));
    }

    function testPrivateOfferWithMainnetUSDC() public {
        privateOfferWithIERC20Currency(USDC);
    }

    function testPrivateOfferWithMainnetWETH() public {
        privateOfferWithIERC20Currency(WETH);
    }

    function testPrivateOfferWithMainnetWBTC() public {
        privateOfferWithIERC20Currency(WBTC);
    }

    function testPrivateOfferWithMainnetEUROC() public {
        privateOfferWithIERC20Currency(EUROC);
    }

    function testPrivateOfferWithMainnetDAI() public {
        privateOfferWithIERC20Currency(DAI);
    }
}
