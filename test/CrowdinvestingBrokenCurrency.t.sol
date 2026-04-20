// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/Token.sol";
import "../contracts/Crowdinvesting.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/AllowList.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "./resources/CloneCreators.sol";

/**
 * @dev Broken ERC20 implementation that reverts on zero transfers
 * Also implements ERC677 for testing onTokenTransfer
 */
contract BrokenERC677 is ERC20 {
    constructor() ERC20("BrokenToken", "BROKEN") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(amount > 0, "BrokenERC677: zero transfers not allowed");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        require(amount > 0, "BrokenERC677: zero transfers not allowed");
        return super.transferFrom(from, to, amount);
    }

    // ERC677 transferAndCall
    function transferAndCall(address _to, uint256 _value, bytes memory _data) public returns (bool success) {
        require(_value > 0, "BrokenERC677: zero transfers not allowed");
        transfer(_to, _value);
        emit Transfer(msg.sender, _to, _value, _data);
        if (isContract(_to)) {
            IERC677Receiver receiver = IERC677Receiver(_to);
            require(receiver.onTokenTransfer(msg.sender, _value, _data), "onTokenTransfer failed");
        }
        return true;
    }

    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);
}

interface IERC677Receiver {
    function onTokenTransfer(address _from, uint256 _value, bytes memory _data) external returns (bool);
}

/**
 * @dev Tests to verify Crowdinvesting behavior with currencies that revert on zero transfers
 */
contract CrowdinvestingBrokenCurrencyTest is Test {
    using SafeERC20 for IERC20;

    AllowList list;
    FeeSettings feeSettings;
    Token token;
    Crowdinvesting crowdinvesting;
    BrokenERC677 brokenCurrency;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant trustedForwarder = address(0);

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18;
    uint256 public constant minAmountPerBuyer = 1 * 10 ** 17; // 0.1 token minimum
    uint256 public constant price = 1 * 10 ** 18; // 1:1 for simplicity
    uint256 public constant tokensToBuy = 10 * 10 ** 18;

    function setUp() public {
        // Create broken currency
        brokenCurrency = new BrokenERC677();

        // Setup AllowList
        list = createAllowList(trustedForwarder, admin);
        vm.prank(admin);
        list.set(address(brokenCurrency), TRUSTED_CURRENCY);
        vm.prank(admin);
        list.set(buyer, 1); // Any non-zero value to allow buyer to receive tokens

        // Setup FeeSettings with ZERO fee
        Fees memory fees = Fees(0, 0, 0, 0); // All fees set to 0
        feeSettings = createFeeSettings(trustedForwarder, address(this), fees, admin, admin, admin);

        // Setup Token
        Token implementation = new Token(trustedForwarder);
        TokenProxyFactory tokenFactory = new TokenProxyFactory(address(implementation));
        token = Token(
            tokenFactory.createTokenProxy(0, trustedForwarder, feeSettings, admin, list, 0x0, "TEST", "TEST")
        );

        // Setup Crowdinvesting
        CrowdinvestingCloneFactory crowdinvestingFactory = new CrowdinvestingCloneFactory(
            address(new Crowdinvesting(trustedForwarder))
        );

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            admin, // owner
            payable(receiver), // currency receiver
            minAmountPerBuyer,
            maxAmountOfTokenToBeSold, // maxAmountPerBuyer
            price, // tokenPrice
            price, // priceMin (not used in this test)
            price, // priceMax (not used in this test)
            maxAmountOfTokenToBeSold,
            brokenCurrency,
            token,
            type(uint256).max, // deadline
            address(0), // no price oracle
            address(0) // no pricing contract
        );

        crowdinvesting = Crowdinvesting(
            crowdinvestingFactory.createCrowdinvestingClone(0, trustedForwarder, arguments)
        );

        // Grant minting allowance to crowdinvesting
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        vm.prank(admin);
        token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        token.increaseMintingAllowance(address(crowdinvesting), maxAmountOfTokenToBeSold);

        // Give buyer some broken currency
        brokenCurrency.transfer(buyer, 100 * 10 ** 18);
    }

    function testBuyWithBrokenCurrencyAndZeroFeeWorks() public {
        // With buy() function, zero fee should work because of the if(fee != 0) check
        uint256 currencyCost = tokensToBuy; // 1:1 price

        vm.startPrank(buyer);
        brokenCurrency.approve(address(crowdinvesting), currencyCost);

        // This should succeed because buy() checks if(fee != 0) before transferring
        crowdinvesting.buy(tokensToBuy, type(uint256).max, buyer);
        vm.stopPrank();

        assertEq(token.balanceOf(buyer), tokensToBuy, "Buyer should have received tokens");
        console.log("buy() with zero fee: SUCCESS (as expected)");
    }

    function testOnTokenTransferWithBrokenCurrencyAndZeroFeeWorks() public {
        // With onTokenTransfer, zero fee should FAIL because there's no if(fee != 0) check
        uint256 currencyCost = tokensToBuy; // 1:1 price

        vm.prank(buyer);
        brokenCurrency.transferAndCall(address(crowdinvesting), currencyCost, "");
    }
}
