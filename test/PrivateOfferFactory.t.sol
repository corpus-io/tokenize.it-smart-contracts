// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/PrivateOffer.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/TimeLockCloneFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/TimeLock.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "./resources/CloneCreators.sol";
import "./resources/ERC20MintableByAnyone.sol";

contract PrivateOfferFactoryTest is Test {
    event Deploy(address indexed privateOffer);

    PrivateOfferFactory factory;
    GlobalTokenExitRegistry tokenExitRegistry;

    AllowList list;
    FeeSettings feeSettings;

    Token token;
    ERC20MintableByAnyone currency;

    uint256 MAX_INT = type(uint256).max;

    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant BUYER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant CURRENCY_RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant PAYMENT_TOKEN_PROVIDER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant PRICE = 10000000;

    uint256 public constant TOKEN_AMOUNT = 3e18;
    uint256 public constant CURRENCY_AMOUNT = (TOKEN_AMOUNT * PRICE) / 1e18;
    uint256 public constant EXPIRATION = 200 days;
    bytes32 public constant SALT = bytes32(0);

    function setUp() public {
        TimeLock timeLockImplementation = new TimeLock(TRUSTED_FORWARDER);
        TimeLockCloneFactory timeLockCloneFactory = new TimeLockCloneFactory(address(timeLockImplementation));
        factory = new PrivateOfferFactory(timeLockCloneFactory, CoinvestedPositionCloneFactory(address(1)));
        currency = new ERC20MintableByAnyone("currency", "CUR");

        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        vm.prank(OWNER);
        list.set(address(currency), TRUSTED_CURRENCY);

        feeSettings = createFeeSettings(TRUSTED_FORWARDER, address(this), buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN));

        Token implementation = new Token(TRUSTED_FORWARDER);
        TokenProxyFactory tokenCloneFactory = new TokenProxyFactory(address(implementation));
        token = Token(
            tokenCloneFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, list, 0x0, "token", "TOK")
        );

        tokenExitRegistry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);
    }

    function testDeployContract(bytes32 _salt) public {
        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 _amount = 20000000000000;
        uint256 _expiration = block.timestamp + 1000;

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            BUYER,
            BUYER,
            CURRENCY_RECEIVER,
            _amount,
            PRICE,
            _expiration,
            IERC20(address(currency)),
            token,
            address(0)
        );
        address expectedAddress = factory.predictPrivateOfferAddress(_salt, arguments);

        // make sure no contract lives here yet
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        assert(len == 0);

        vm.prank(ADMIN);
        token.increaseMintingAllowance(expectedAddress, _amount);

        currency.mint(BUYER, _amount * PRICE);
        vm.prank(BUYER);
        currency.approve(expectedAddress, _amount * PRICE);

        vm.expectEmit(true, true, true, true, address(factory));
        emit Deploy(expectedAddress);
        address actualAddress = factory.deployPrivateOffer(_salt, arguments);

        assertTrue(actualAddress == expectedAddress, "Wrong address returned");

        // make sure contract lives here now
        assembly {
            len := extcodesize(expectedAddress)
        }
        assertTrue(len != 0, "Contract not deployed or to wrong address");
    }

    function testDeployWithTimeLock(uint64 _lockedUntil, address tokenReceiver, address timeLockOwner) public {
        vm.assume(_lockedUntil > block.timestamp);
        vm.assume(_lockedUntil < type(uint64).max / 2);
        vm.assume(tokenReceiver != address(0));
        vm.assume(timeLockOwner != address(0));
        vm.assume(tokenReceiver != timeLockOwner);
        vm.assume(timeLockOwner != TRUSTED_FORWARDER);

        // mint currency to BUYER
        currency.mint(BUYER, CURRENCY_AMOUNT);

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            BUYER,
            tokenReceiver,
            CURRENCY_RECEIVER,
            TOKEN_AMOUNT,
            PRICE,
            EXPIRATION,
            IERC20(address(currency)),
            token,
            address(0)
        );

        // predict addresses for time lock contract and private offer contract
        (address expectedPrivateOffer, address expectedTimeLock) = factory.predictPrivateOfferAndTimeLockAddress(
            SALT,
            arguments,
            _lockedUntil,
            timeLockOwner,
            tokenExitRegistry,
            TRUSTED_FORWARDER
        );

        console.log("expectedPrivateOffer", expectedPrivateOffer);
        console.log("expectedTimeLock", expectedTimeLock);

        // make sure no contract lives here yet
        assertFalse(Address.isContract(expectedPrivateOffer), "Private Offer address already contains contract");
        assertFalse(Address.isContract(expectedTimeLock), "TimeLock address already contains contract");

        // give allowances to private offer contract
        vm.prank(BUYER);
        currency.approve(expectedPrivateOffer, CURRENCY_AMOUNT);
        vm.prank(ADMIN);
        token.increaseMintingAllowance(expectedPrivateOffer, TOKEN_AMOUNT);

        // check state before deployment
        assertEq(currency.balanceOf(BUYER), CURRENCY_AMOUNT, "Buyer has wrong currency balance before deployment");
        assertEq(token.balanceOf(BUYER), 0, "Buyer has wrong token balance before deployment");
        assertEq(
            currency.balanceOf(CURRENCY_RECEIVER),
            0,
            "Currency receiver has wrong currency balance before deployment"
        );

        // deploy contracts
        assertEq(
            factory.deployPrivateOfferWithTimeLock(
                SALT,
                arguments,
                _lockedUntil,
                timeLockOwner,
                tokenExitRegistry,
                TRUSTED_FORWARDER
            ),
            expectedTimeLock
        );

        // make sure contracts live here now
        assertTrue(Address.isContract(expectedPrivateOffer), "Private Offer address does not contain contract");
        assertTrue(Address.isContract(expectedTimeLock), "TimeLock address does not contain contract");

        // make sure time lock contract is configured correctly
        TimeLock timeLockContract = TimeLock(expectedTimeLock);
        assertEq(timeLockContract.owner(), timeLockOwner, "TimeLock contract not owned by timeLockOwner");
        assertEq(timeLockContract.lockedUntil(), _lockedUntil, "TimeLock contract has wrong lockedUntil");

        // check balances: tokens are held in the time lock, not yet accessible
        assertEq(currency.balanceOf(BUYER), 0, "Buyer has wrong currency balance after deployment");
        assertEq(token.balanceOf(BUYER), 0, "Buyer has wrong token balance after deployment");
        assertEq(
            currency.balanceOf(CURRENCY_RECEIVER),
            CURRENCY_AMOUNT,
            "Currency receiver has wrong currency balance"
        );
        assertEq(token.balanceOf(tokenReceiver), 0, "Token receiver has wrong token balance");
        assertEq(token.balanceOf(expectedTimeLock), TOKEN_AMOUNT, "TimeLock contract has wrong token balance");

        // try to drain before lock expires — must revert
        vm.prank(timeLockOwner);
        vm.expectRevert(TimeLock.TimeLockNotExpired.selector);
        timeLockContract.drain(IERC20(address(token)), tokenReceiver);

        // drain after lock expires
        vm.warp(_lockedUntil);
        vm.prank(timeLockOwner);
        timeLockContract.drain(IERC20(address(token)), tokenReceiver);
        assertEq(token.balanceOf(tokenReceiver), TOKEN_AMOUNT, "Token receiver has wrong token balance after drain");
    }
}
