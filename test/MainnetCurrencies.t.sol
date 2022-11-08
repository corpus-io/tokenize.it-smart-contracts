// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
//import "../lib/forge-std/stdlib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/CorpusToken.sol";
import "../contracts/ContinuousFundraising.sol";
import "./resources/USDC.sol";


contract MainnetCurrencies is Test {
    using SafeERC20 for IERC20;
    using stdStorage for StdStorage; // for stdStorage.set()

    AllowList list;
    CorpusToken token;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant minterAdmin = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    // use opengsn forwarder https://etherscan.io/address/0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA
    address public constant trustedForwarder = 0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA;
    
    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10**18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token
    uint256 public constant amountOfTokenToBuy = maxAmountPerBuyer;

    // test currencies
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 wbtc = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 eurc = IERC20(0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c);


    function setUp() public {
        list = new AllowList();
        token = new CorpusToken(admin, list, 0x0, "TESTTOKEN", "TEST");
        
    }

    // function testUSDCBalance() public {
    //     uint balance1 = usdc.balanceOf(buyer);
    //     console.log("buyer's balance: ", balance1);
    //     uint balance2 = usdc.balanceOf(address(0x55FE002aefF02F77364de339a1292923A15844B8));
    //     console.log("circle's balance: ", balance2);
    // }

    /** 
        @notice sets the balance of who to amount
        taken from here: https://mirror.xyz/brocke.eth/PnX7oAcU4LJCxcoICiaDhq_MUUu9euaM8Y5r465Rd2U
    */
    function writeERC20Balance(address who, address _token, uint256 amount) internal {
        stdstore
            .target(_token)
            .sig(IERC20(_token).balanceOf.selector)
            .with_key(who)
            .checked_write(amount);
    }

    function continuousFundraisingWithRealERC20Currency(IERC20 _currency) public {
        // some math
        //uint _decimals = _currency.decimals(); // can't get decimals from IERC20
        //uint _price = 7 * 10**_decimals; // 7 payment tokens per token
        uint _price = 7 * 10**18;
        uint _currencyCost = amountOfTokenToBuy * _price / 10**token.decimals();
        uint _currencyAmount = _currencyCost * 2;

        // set up fundraise with _currency
        vm.prank(owner);
        ContinuousFundraising _raise = new ContinuousFundraising(trustedForwarder, payable(receiver), minAmountPerBuyer, maxAmountPerBuyer, _price, maxAmountOfTokenToBeSold, _currency, MintableERC20(address(token)));

        // allow raise contract to mint
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();
        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(address(_raise), maxAmountOfTokenToBeSold);

        // give the buyer funds
        //console.log("buyer's balance: ", _currency.balanceOf(buyer));
        writeERC20Balance(buyer, address(_currency), _currencyAmount);
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
        _raise.buy(maxAmountPerBuyer);

        // check buyer has tokens and receiver has _currency afterwards
        assertEq(token.balanceOf(buyer), amountOfTokenToBuy);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(_currency.balanceOf(receiver), _currencyCost);
        assertEq(_currency.balanceOf(buyer), _currencyAmount - _currencyCost);
    }

    function testContinuousFundraisingWithUSDC() public {
        continuousFundraisingWithRealERC20Currency(usdc);
    }

    function testContinuousFundraisingWithWETH() public {
        continuousFundraisingWithRealERC20Currency(weth);
    }

    function testContinuousFundraisingWithWBTC() public {
        continuousFundraisingWithRealERC20Currency(wbtc);
    }

    function testContinuousFundraisingWithEURC() public {
        continuousFundraisingWithRealERC20Currency(eurc);
    }



}