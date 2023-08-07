// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/TokenCloneFactory.sol";
import "../contracts/FeeSettings.sol";

contract tokenTest is Test {
    Token implementation;
    AllowList allowList;
    FeeSettings feeSettings;
    TokenCloneFactory factory;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant requirer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant burner = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant transfererAdmin = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant transferer = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant pauser = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant feeSettingsAndAllowListOwner = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    uint256 requirements = 0;

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        vm.startPrank(feeSettingsAndAllowListOwner);
        allowList = new AllowList();
        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, feeSettingsAndAllowListOwner);
        vm.stopPrank();

        implementation = new Token(trustedForwarder, feeSettings, admin, allowList, requirements, "testToken", "TEST");

        factory = new TokenCloneFactory(address(implementation));
    }

    function testAddressPrediction(bytes32 salt) public {
        address expected = factory.predictCloneAddress(salt);
        address actual = factory.createTokenClone(
            salt,
            feeSettings,
            admin,
            allowList,
            requirements,
            "testToken",
            "TEST"
        );
        assertEq(expected, actual, "address prediction failed");
    }

    function testInitialization(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address _admin,
        address _allowList,
        uint256 _requirements
    ) public {
        vm.assume(_admin != address(0));
        vm.assume(_allowList != address(0));
        vm.assume(keccak256(abi.encodePacked(name)) != keccak256(abi.encodePacked("")));
        vm.assume(keccak256(abi.encodePacked(symbol)) != keccak256(abi.encodePacked("")));

        console.log("name: %s", name);
        console.log("symbol: %s", symbol);

        FeeSettings _feeSettings = new FeeSettings(Fees(100, 100, 100, 0), feeSettingsAndAllowListOwner);

        Token clone = Token(
            factory.createTokenClone(salt, _feeSettings, _admin, AllowList(_allowList), _requirements, name, symbol)
        );

        // test constructor arguments are used
        assertEq(clone.name(), name, "name not set");
        assertEq(clone.symbol(), symbol, "symbol not set");
        assertTrue(clone.hasRole(clone.DEFAULT_ADMIN_ROLE(), _admin), "admin not set");
        assertEq(address(clone.allowList()), _allowList, "allowList not set");
        assertEq(clone.requirements(), _requirements, "requirements not set");
        assertEq(address(clone.feeSettings()), address(_feeSettings), "feeSettings not set");

        // check trustedForwarder is set
        assertTrue(clone.isTrustedForwarder(trustedForwarder), "trustedForwarder not set");

        // test roles are assigned
        assertTrue(clone.hasRole(clone.REQUIREMENT_ROLE(), _admin), "requirer not set");
        assertTrue(clone.hasRole(clone.MINTALLOWER_ROLE(), _admin), "mintAllower not set");
        assertTrue(clone.hasRole(clone.BURNER_ROLE(), _admin), "burner not set");
        assertTrue(clone.hasRole(clone.TRANSFERERADMIN_ROLE(), _admin), "transfererAdmin not set");
        assertTrue(clone.hasRole(clone.PAUSER_ROLE(), _admin), "pauser not set");

        // test EIP712 Domain Separator is set correctly
        string memory domainSeparatorName;
        string memory domainSeparatorVersion;
        uint256 domainSeparatorChainId;
        address domainSeparatorAddress;

        (, domainSeparatorName, domainSeparatorVersion, domainSeparatorChainId, domainSeparatorAddress, , ) = clone
            .eip712Domain();

        assertEq(domainSeparatorName, name, "domainSeparatorName not set");
        assertEq(domainSeparatorVersion, "1", "domainSeparatorVersion not set");
        assertEq(domainSeparatorChainId, block.chainid, "domainSeparatorChainId not set");
        assertEq(domainSeparatorAddress, address(clone), "domainSeparatorAddress not set");

        // test contract can not be initialized again
        vm.expectRevert("Initializable: contract is already initialized");
        clone.initialize(feeSettings, admin, allowList, requirements, "testToken", "TEST");
    }

    function testEmptyStringReverts(
        bytes32 salt,
        string memory someString,
        address _admin,
        address _allowList,
        uint256 _requirements
    ) public {
        vm.assume(_admin != address(0));
        vm.assume(_allowList != address(0));
        vm.assume(bytes(someString).length > 0);

        FeeSettings _feeSettings = new FeeSettings(Fees(100, 100, 100, 0), feeSettingsAndAllowListOwner);

        vm.expectRevert("String must not be empty");
        factory.createTokenClone(salt, _feeSettings, _admin, AllowList(_allowList), _requirements, "", someString);

        vm.expectRevert("String must not be empty");
        factory.createTokenClone(salt, _feeSettings, _admin, AllowList(_allowList), _requirements, someString, "");
    }

    /*
        pausing and unpausing
    */
    function testPausing(address _admin, address rando) public {
        vm.assume(_admin != address(0));
        vm.assume(rando != address(0));
        vm.assume(rando != _admin);

        FeeSettings _feeSettings = new FeeSettings(Fees(100, 100, 100, 0), feeSettingsAndAllowListOwner);

        Token _token = Token(
            factory.createTokenClone(0, _feeSettings, _admin, AllowList(address(3)), 0, "TestToken", "TST")
        );

        vm.prank(rando);
        vm.expectRevert();
        _token.pause();

        vm.prank(rando);
        vm.expectRevert();
        _token.unpause();

        assertFalse(_token.paused());
        vm.prank(_admin);
        _token.pause();
        assertTrue(_token.paused());

        // can't transfer when paused
        vm.prank(rando);
        vm.expectRevert("Pausable: paused");
        _token.transfer(_admin, 1);

        vm.prank(_admin);
        _token.unpause();
        assertFalse(_token.paused());
    }

    /*
        granting role
    */
    function testGrantRole(address newPauser) public {
        vm.assume(newPauser != address(0));
        vm.assume(newPauser != admin);

        FeeSettings _feeSettings = new FeeSettings(Fees(100, 100, 100, 0), feeSettingsAndAllowListOwner);

        Token _token = Token(
            factory.createTokenClone(0, _feeSettings, admin, AllowList(address(3)), 0, "TestToken", "TST")
        );

        bytes32 pauserRole = _token.PAUSER_ROLE();

        assertFalse(_token.hasRole(pauserRole, newPauser));

        vm.expectRevert();
        vm.prank(newPauser);
        _token.pause();

        vm.prank(admin);
        _token.grantRole(pauserRole, newPauser);

        assertTrue(_token.hasRole(pauserRole, newPauser));

        assertFalse(_token.paused());

        vm.prank(newPauser);
        _token.pause();

        assertTrue(_token.paused());
    }
}
