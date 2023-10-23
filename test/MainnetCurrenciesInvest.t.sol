// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
//import "../lib/forge-std/stdlib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/TokenCloneFactory.sol";
import "../contracts/PublicFundraisingCloneFactory.sol";
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

    AllowList list;
    FeeSettings feeSettings;

    Token token;
    PersonalInviteFactory inviteFactory;

    PublicFundraisingCloneFactory fundraisingFactory;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    // use opengsn forwarder https://etherscan.io/address/0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA
    address public constant trustedForwarder = 0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA;

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token
    uint256 public constant amountOfTokenToBuy = maxAmountPerBuyer;

    // some math
    uint256 public constant price = 7 * 10 ** 18;
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
        list = new AllowList();
        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, admin, admin, admin);

        Token implementation = new Token(trustedForwarder);
        TokenCloneFactory tokenCloneFactory = new TokenCloneFactory(address(implementation));
        token = Token(
            tokenCloneFactory.createTokenClone(0, trustedForwarder, feeSettings, admin, list, 0x0, "TESTTOKEN", "TEST")
        );

        fundraisingFactory = new PublicFundraisingCloneFactory(address(new PublicFundraising(trustedForwarder)));

        inviteFactory = new PersonalInviteFactory();
        currencyCost = (amountOfTokenToBuy * price) / 10 ** token.decimals();
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

    function publicFundraisingWithIERC20Currency(IERC20 _currency) public {
        // some math
        //uint _decimals = _currency.decimals(); // can't get decimals from IERC20
        //uint _price = 7 * 10**_decimals; // 7 payment tokens per token
        uint256 _price = 7 * 10 ** 18;
        uint256 _currencyCost = (amountOfTokenToBuy * _price) / 10 ** token.decimals();
        uint256 _currencyAmount = _currencyCost * 2;

        // set up fundraise with _currency
        PublicFundraising _raise = PublicFundraising(
            fundraisingFactory.createPublicFundraisingClone(
                0,
                trustedForwarder,
                owner,
                payable(receiver),
                minAmountPerBuyer,
                maxAmountPerBuyer,
                _price,
                maxAmountOfTokenToBeSold,
                _currency,
                token
            )
        );

        // allow raise contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(admin);
        token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        token.increaseMintingAllowance(address(_raise), maxAmountOfTokenToBeSold);

        // give the buyer funds
        //console.log("buyer's balance: ", _currency.balanceOf(buyer));
        helper.writeERC20Balance(buyer, address(_currency), _currencyAmount);
        //console.log("buyer's balance: ", _currency.balanceOf(buyer));

        // give raise contract a currency allowance
        vm.prank(buyer);
        _currency.approve(address(_raise), _currencyCost);

        // make sure buyer has no tokens before and receiver has no _currency before
        assertEq(token.balanceOf(buyer), 0);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(_currency.balanceOf(receiver), 0);
        assertEq(_currency.balanceOf(buyer), _currencyAmount);

        // buy tokens
        vm.prank(buyer);
        _raise.buy(maxAmountPerBuyer, buyer);

        // check buyer has tokens and receiver has _currency afterwards
        assertEq(token.balanceOf(buyer), amountOfTokenToBuy, "buyer has tokens");
        assertEq(token.balanceOf(receiver), 0, "receiver has no tokens");
        assertEq(
            _currency.balanceOf(receiver),
            _currencyCost - _currencyCost / FeeSettings(address(token.feeSettings())).publicFundraisingFeeDenominator(),
            "receiver should have received currency"
        );
        assertEq(
            _currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            _currencyCost / FeeSettings(address(token.feeSettings())).publicFundraisingFeeDenominator(),
            "fee receiver should have received currency"
        );
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            amountOfTokenToBuy / FeeSettings(address(token.feeSettings())).publicFundraisingFeeDenominator(),
            "fee receiver should have received tokens"
        );
        assertEq(_currency.balanceOf(buyer), _currencyAmount - _currencyCost, "buyer should have paid currency");
    }

    function testPublicFundraisingWithMainnetUSDC() public {
        publicFundraisingWithIERC20Currency(USDC);
    }

    function testPublicFundraisingWithMainnetWETH() public {
        publicFundraisingWithIERC20Currency(WETH);
    }

    function testPublicFundraisingWithMainnetWBTC() public {
        publicFundraisingWithIERC20Currency(WBTC);
    }

    function testPublicFundraisingWithMainnetEUROC() public {
        publicFundraisingWithIERC20Currency(EUROC);
    }

    function testPublicFundraisingWithMainnetDAI() public {
        publicFundraisingWithIERC20Currency(DAI);
    }

    function personalInviteWithIERC20Currency(IERC20 _currency) public {
        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 expiration = block.timestamp + 1000;

        address expectedAddress = inviteFactory.getAddress(
            salt,
            buyer,
            buyer,
            receiver,
            amountOfTokenToBuy,
            price,
            expiration,
            _currency,
            IERC20(address(token))
        );

        // grant mint allowance to invite
        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, amountOfTokenToBuy);

        // give the buyer funds and approve invite
        helper.writeERC20Balance(buyer, address(_currency), currencyAmount);
        vm.prank(buyer);
        _currency.approve(address(expectedAddress), currencyCost);

        // make sure balances are as expected before deployment
        assertEq(_currency.balanceOf(buyer), currencyAmount);
        assertEq(_currency.balanceOf(receiver), 0);
        assertEq(token.balanceOf(buyer), 0);
        assertEq(token.balanceOf(receiver), 0);

        // deploy invite
        address inviteAddress = inviteFactory.deploy(
            salt,
            buyer,
            buyer,
            receiver,
            amountOfTokenToBuy,
            price,
            expiration,
            _currency,
            IERC20(address(token))
        );

        // check situation after deployment
        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");
        // check buyer has tokens and receiver has _currency afterwards
        assertEq(token.balanceOf(buyer), amountOfTokenToBuy, "buyer has tokens");
        assertEq(token.balanceOf(receiver), 0, "receiver has no tokens");
        assertEq(
            _currency.balanceOf(receiver),
            currencyCost - token.feeSettings().publicFundraisingFee(currencyCost),
            "receiver should have received currency"
        );
        assertEq(
            _currency.balanceOf(token.feeSettings().publicFundraisingFeeCollector()),
            token.feeSettings().publicFundraisingFee(currencyCost),
            "fee receiver should have received currency"
        );
        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            FeeSettings(address(token.feeSettings())).tokenFee(amountOfTokenToBuy),
            "fee receiver should have received tokens"
        );
        assertEq(_currency.balanceOf(buyer), currencyAmount - currencyCost, "buyer should have paid currency");

        // log buyers token balance
        console.log("buyer's token balance: ", token.balanceOf(buyer));
    }

    function testPersonalInviteWithMainnetUSDC() public {
        personalInviteWithIERC20Currency(USDC);
    }

    function testPersonalInviteWithMainnetWETH() public {
        personalInviteWithIERC20Currency(WETH);
    }

    function testPersonalInviteWithMainnetWBTC() public {
        personalInviteWithIERC20Currency(WBTC);
    }

    function testPersonalInviteWithMainnetEUROC() public {
        personalInviteWithIERC20Currency(EUROC);
    }

    function testPersonalInviteWithMainnetDAI() public {
        personalInviteWithIERC20Currency(DAI);
    }
}
