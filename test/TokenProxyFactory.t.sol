// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/ERC2771Helper.sol";
import "./resources/CloneCreators.sol";

contract tokenProxyFactoryTest is Test {
    using ECDSA for bytes32;

    Token implementation;
    AllowList allowList;
    FeeSettings feeSettings;
    TokenProxyFactory factory;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant REQUIRER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant BURNER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRANSFERER_ADMIN = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant TRANSFERER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant PAUSER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant FEE_SETTINGS_AND_ALLOW_LIST_OWNER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    uint256 requirements = 0;

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
            buildFeeTypes(
                100,
                100,
                100,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER
            )
        );
        vm.stopPrank();

        implementation = new Token(TRUSTED_FORWARDER);

        factory = new TokenProxyFactory(address(implementation));
    }

    function testAddressPrediction(
        bytes32 _salt,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) public {
        console.log("IFeeSettingsV2 interface id: ");
        console.logBytes4(type(IFeeSettingsV2).interfaceId);

        console.log("Supports interface: ", feeSettings.supportsInterface(type(IFeeSettingsV2).interfaceId));

        vm.assume(TRUSTED_FORWARDER != address(0));
        vm.assume(_admin != address(0));
        vm.assume(address(_allowList) != address(0));

        bytes32 salt = keccak256(
            abi.encode(_salt, TRUSTED_FORWARDER, feeSettings, _admin, _allowList, _requirements, _name, _symbol)
        );
        address expected1 = factory.predictProxyAddress(salt);
        address expected2 = factory.predictProxyAddress(
            _salt,
            TRUSTED_FORWARDER,
            feeSettings,
            _admin,
            _allowList,
            _requirements,
            _name,
            _symbol
        );
        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        address actual = factory.createTokenProxy(
            _salt,
            TRUSTED_FORWARDER,
            feeSettings,
            _admin,
            _allowList,
            _requirements,
            _name,
            _symbol
        );
        assertEq(expected1, actual, "address prediction failed");
    }

    function testSecondDeploymentFails(
        bytes32 _salt,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) public {
        vm.assume(TRUSTED_FORWARDER != address(0));
        vm.assume(_admin != address(0));
        vm.assume(address(_allowList) != address(0));

        factory.createTokenProxy(
            _salt,
            TRUSTED_FORWARDER,
            feeSettings,
            _admin,
            _allowList,
            _requirements,
            _name,
            _symbol
        );

        vm.expectRevert("Create2: Failed on deploy");
        factory.createTokenProxy(
            _salt,
            TRUSTED_FORWARDER,
            feeSettings,
            _admin,
            _allowList,
            _requirements,
            _name,
            _symbol
        );
    }

    function testWrongForwarder(address _wrongForwarder) public {
        vm.assume(TRUSTED_FORWARDER != _wrongForwarder);
        vm.assume(_wrongForwarder != address(0));

        // using a different TRUSTED_FORWARDER should fail
        vm.expectRevert("TokenProxyFactory: Unexpected trustedForwarder");
        factory.createTokenProxy(
            bytes32(uint256(0)),
            _wrongForwarder,
            feeSettings,
            ADMIN,
            AllowList(allowList),
            requirements,
            "testToken",
            "TEST"
        );
    }

    function testInitialization(
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

        FeeSettings _feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(
                100,
                100,
                100,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER
            )
        );

        Token clone = Token(
            factory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                _feeSettings,
                _admin,
                AllowList(_allowList),
                _requirements,
                name,
                symbol
            )
        );

        // test constructor arguments are used
        assertEq(clone.name(), name, "name not set");
        assertEq(clone.symbol(), symbol, "symbol not set");
        assertTrue(clone.hasRole(clone.DEFAULT_ADMIN_ROLE(), _admin), "ADMIN not set");
        assertEq(address(clone.allowList()), _allowList, "allowList not set");
        assertEq(clone.requirements(), _requirements, "requirements not set");
        assertEq(address(clone.feeSettings()), address(_feeSettings), "feeSettings not set");

        // check TRUSTED_FORWARDER is set
        assertTrue(clone.isTrustedForwarder(TRUSTED_FORWARDER), "TRUSTED_FORWARDER not set");

        // test roles are assigned
        assertTrue(clone.hasRole(clone.REQUIREMENT_ROLE(), _admin), "REQUIRER not set");
        assertTrue(clone.hasRole(clone.MINTALLOWER_ROLE(), _admin), "MINT_ALLOWER not set");
        assertTrue(clone.hasRole(clone.BURNER_ROLE(), _admin), "BURNER not set");
        assertTrue(clone.hasRole(clone.TRANSFERERADMIN_ROLE(), _admin), "TRANSFERER_ADMIN not set");
        assertTrue(clone.hasRole(clone.PAUSER_ROLE(), _admin), "PAUSER not set");

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
        clone.initialize(feeSettings, ADMIN, allowList, requirements, "testToken", "TEST");
    }

    /*
        pausing and unpausing
    */
    function testPausing(address _admin, address rando) public {
        vm.assume(_admin != address(0));
        vm.assume(_admin != TRUSTED_FORWARDER);
        vm.assume(rando != address(0));
        vm.assume(rando != _admin);
        vm.assume(rando != TRUSTED_FORWARDER);

        FeeSettings _feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(
                100,
                100,
                100,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER
            )
        );

        Token _token = Token(
            factory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                _feeSettings,
                _admin,
                AllowList(address(3)),
                0,
                "TestToken",
                "TST"
            )
        );

        vm.prank(rando);
        vm.expectRevert();
        _token.pause();

        assertFalse(_token.paused());
        vm.prank(_admin);
        _token.pause();
        assertTrue(_token.paused());

        vm.prank(rando);
        vm.expectRevert();
        _token.unpause();

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
        vm.assume(newPauser != ADMIN);
        vm.assume(newPauser != TRUSTED_FORWARDER);

        FeeSettings _feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(
                100,
                100,
                100,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER
            )
        );

        Token _token = Token(
            factory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                _feeSettings,
                ADMIN,
                AllowList(address(3)),
                0,
                "TestToken",
                "TST"
            )
        );

        bytes32 pauserRole = _token.PAUSER_ROLE();

        assertFalse(_token.hasRole(pauserRole, newPauser));

        vm.expectRevert();
        vm.prank(newPauser);
        _token.pause();

        vm.prank(ADMIN);
        _token.grantRole(pauserRole, newPauser);

        assertTrue(_token.hasRole(pauserRole, newPauser));

        assertFalse(_token.paused());

        vm.prank(newPauser);
        _token.pause();

        assertTrue(_token.paused());
    }

    function testPermitWithProxy(
        string memory name,
        string memory symbol,
        address _admin,
        uint256 _tokenPermitAmount,
        uint256 _tokenOwnerPrivateKey,
        address _tokenSpender,
        address _relayer
    ) public {
        vm.assume(_relayer != address(0));
        vm.assume(_admin != TRUSTED_FORWARDER);
        vm.assume(_tokenSpender != address(0));
        vm.assume(_tokenSpender != FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        vm.assume(_tokenSpender != TRUSTED_FORWARDER);
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(symbol).length > 0);
        vm.assume(_tokenPermitAmount < type(uint256).max / feeSettings.FEE_DENOMINATOR()); // leave room for fees
        vm.assume(
            _tokenOwnerPrivateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        vm.assume(_tokenOwnerPrivateKey > 0);

        Token clone = Token(
            factory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                _admin,
                AllowList(allowList),
                requirements,
                name,
                symbol
            )
        );

        address tokenOwner = vm.addr(_tokenOwnerPrivateKey);
        vm.assume(tokenOwner != address(0));
        vm.assume(tokenOwner != FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        vm.assume(_tokenSpender != tokenOwner);
        vm.assume(_relayer != tokenOwner);

        // permit spender to spend holder's tokens
        //uint256 nonce = clone.nonces(tokenOwner);
        uint256 deadline = block.timestamp + 1000;
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                tokenOwner,
                _tokenSpender,
                _tokenPermitAmount,
                clone.nonces(tokenOwner),
                block.timestamp + 1000
            )
        );

        //bytes32 hash = ECDSA.toTypedDataHash(clone.DOMAIN_SEPARATOR(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _tokenOwnerPrivateKey,
            ECDSA.toTypedDataHash(clone.DOMAIN_SEPARATOR(), structHash)
        );

        // check allowance
        assertEq(clone.allowance(tokenOwner, _tokenSpender), 0);

        // call permit with a wallet that is not tokenOwner
        vm.prank(_relayer);
        clone.permit(tokenOwner, _tokenSpender, _tokenPermitAmount, deadline, v, r, s);

        // check allowance
        assertEq(clone.allowance(tokenOwner, _tokenSpender), _tokenPermitAmount);

        // mint tokens to tokenOwner
        vm.startPrank(_admin);
        clone.mint(tokenOwner, _tokenPermitAmount);
        vm.stopPrank();

        // check token balances before transfer
        assertEq(clone.balanceOf(tokenOwner), _tokenPermitAmount);
        assertEq(clone.balanceOf(_tokenSpender), 0);

        // spend tokens
        vm.startPrank(_tokenSpender);
        clone.transferFrom(tokenOwner, _tokenSpender, _tokenPermitAmount);
        vm.stopPrank();

        // check token balances after transfer
        assertEq(clone.balanceOf(tokenOwner), 0);
        assertEq(clone.balanceOf(_tokenSpender), _tokenPermitAmount);
    }
}
