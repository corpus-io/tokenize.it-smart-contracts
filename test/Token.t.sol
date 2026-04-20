// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "./resources/CloneCreators.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract tokenTest is Test {
    event RequirementsChanged(uint newRequirements);
    event MintingAllowanceChanged(address indexed MINTER, uint256 newAllowance);

    Token token;
    Token implementation = new Token(TRUSTED_FORWARDER);
    TokenProxyFactory tokenCloneFactory = new TokenProxyFactory(address(implementation));

    AllowList allowList;
    FeeSettings feeSettings;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant REQUIRER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant BURNER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRANSFERER_ADMIN = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant TRANSFERER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant PAUSER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant FEE_SETTINGS_OWNER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        vm.prank(FEE_SETTINGS_OWNER);
        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(100, 100, 100, ADMIN, ADMIN, ADMIN)
        );
        token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                allowList,
                0x0,
                "testToken",
                "TEST"
            )
        );

        // set up roles
        vm.startPrank(ADMIN);
        token.grantRole(token.BURNER_ROLE(), BURNER);
        token.grantRole(token.TRANSFERER_ROLE(), TRANSFERER);
        token.grantRole(token.PAUSER_ROLE(), PAUSER);
        token.grantRole(token.REQUIREMENT_ROLE(), REQUIRER);
        token.grantRole(token.MINTALLOWER_ROLE(), MINT_ALLOWER);
        token.grantRole(token.TRANSFERERADMIN_ROLE(), TRANSFERER_ADMIN);

        // revoke roles from ADMIN
        token.revokeRole(token.BURNER_ROLE(), ADMIN);
        token.revokeRole(token.TRANSFERER_ROLE(), ADMIN);
        token.revokeRole(token.PAUSER_ROLE(), ADMIN);
        token.revokeRole(token.REQUIREMENT_ROLE(), ADMIN);
        token.revokeRole(token.MINTALLOWER_ROLE(), ADMIN);
        token.revokeRole(token.TRANSFERERADMIN_ROLE(), ADMIN);

        vm.stopPrank();
    }

    function testSetUp() public view {
        assertTrue(token.hasRole(token.getRoleAdmin(token.REQUIREMENT_ROLE()), ADMIN));
        assertTrue(token.allowList() == allowList);
        assertTrue(keccak256(bytes(token.name())) == keccak256(bytes("testToken")));
        assertTrue(keccak256(bytes(token.symbol())) == keccak256(bytes("TEST")));
    }

    function testLogicContractCreation() public {
        Token _logic = new Token(address(1));

        console.log("address of logic contract: ", address(_logic));

        // try to initialize
        vm.expectRevert("Initializable: contract is already initialized");
        _logic.initialize(IFeeSettingsV2(address(2)), address(3), AllowList(address(4)), 3, "testToken", "TEST");

        // all settings are 0
        assertTrue(address(_logic.feeSettings()) == address(0));
        assertTrue(address(_logic.allowList()) == address(0));
        assertTrue(_logic.requirements() == 0);
        assertTrue(keccak256(abi.encodePacked(_logic.name())) == keccak256(bytes("")));
        assertTrue(keccak256(abi.encodePacked(_logic.symbol())) == keccak256(bytes("")));

        // we are not the ADMIN
        assertFalse(_logic.hasRole(_logic.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    function testAllowList0() public {
        AllowList _noList = AllowList(address(0));
        vm.expectRevert(Token.ZeroAllowListAddress.selector);
        tokenCloneFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, _noList, 0x0, "testToken", "TEST");
    }

    function testFeeSettings0() public {
        FeeSettings _noFeeSettings = FeeSettings(address(0));
        console.log("fee settings address:", address(_noFeeSettings));
        vm.expectRevert();
        tokenCloneFactory.createTokenProxy(
            0,
            TRUSTED_FORWARDER,
            _noFeeSettings,
            ADMIN,
            allowList,
            0x0,
            "testToken",
            "TEST"
        );
    }

    function testFeeSettingsNoERC165() public {
        vm.expectRevert();
        tokenCloneFactory.createTokenProxy(
            0,
            TRUSTED_FORWARDER,
            FeeSettings(address(allowList)),
            ADMIN,
            allowList,
            0x0,
            "testToken",
            "TEST"
        );
    }

    function testThisIsNotMintAllower() public view {
        assertFalse(token.hasRole(token.MINTALLOWER_ROLE(), address(this)));
    }

    function testMsgSenderIsNotMintAllower() public view {
        assertFalse(token.hasRole(token.MINTALLOWER_ROLE(), msg.sender));
    }

    /**
    @notice test that addresses that are not the ADMIN cannot perform the mint allower tasks
     */
    function testIsNotAdmin(address x) public view {
        // test would fail (to fail) if x = ADMIN. This has actually happened! Abort test in that case.
        vm.assume(x != ADMIN);
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), x));
    }

    function testAdmin() public view {
        assertTrue(token.hasRole(token.getRoleAdmin(token.REQUIREMENT_ROLE()), ADMIN));
    }

    function testMinterAdmin() public view {
        assertTrue(token.hasRole(token.MINTALLOWER_ROLE(), MINT_ALLOWER));
    }

    function testMintAllower(address x) public view {
        vm.assume(x != MINT_ALLOWER);
        assertFalse(token.hasRole(token.MINTALLOWER_ROLE(), x));
    }

    function testThisCanNotSetRequirements() public {
        vm.expectRevert();
        token.setRequirements(3);
    }

    function testDecimals() public view {
        assertTrue(token.decimals() == 18);
    }

    function testAdminNotCanSetRequirements() public {
        // ADMIN does not have the Requirements role, only the right to grant this role
        vm.prank(ADMIN);
        vm.expectRevert();
        token.setRequirements(3);
    }

    function testXCanNotSetRequirements(address X) public {
        // x is missing the Requirements role
        vm.assume(X != REQUIRER);
        vm.assume(X != TRUSTED_FORWARDER);
        vm.prank(X);
        vm.expectRevert();
        token.setRequirements(3);
    }

    function testSetRoleRequirements() public {
        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        assertTrue(token.hasRole(role, REQUIRER));
    }

    function testSetRoleMintallower() public {
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        assertTrue(token.hasRole(roleMintAllower, MINT_ALLOWER));
    }

    function testSetRoleBurner() public {
        bytes32 role = token.BURNER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, BURNER);
        assertTrue(token.hasRole(role, BURNER));
    }

    function testSetRoleTransferer() public {
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleTransfererAdmin, TRANSFERER_ADMIN);
        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, TRANSFERER);
        assertTrue(token.hasRole(roleTransferer, TRANSFERER));
    }

    function testSetRolePauser() public {
        bytes32 role = token.PAUSER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, PAUSER);
        assertTrue(token.hasRole(role, PAUSER));
    }

    function testSetRoleDefaultAdmin() public {
        bytes32 role = token.DEFAULT_ADMIN_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, PAUSER);
        assertTrue(token.hasRole(role, PAUSER));
    }

    function testSetRequirements(uint256 newRequirements) public {
        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        vm.prank(REQUIRER);
        vm.expectEmit(true, true, true, true, address(token));
        emit RequirementsChanged(newRequirements);
        token.setRequirements(newRequirements);
        assertTrue(token.requirements() == newRequirements);
    }

    function testPauserCanNotSetRequirements() public {
        vm.prank(PAUSER);
        vm.expectRevert();
        token.setRequirements(3);
        assertTrue(token.requirements() == 0);
    }

    function testSetUpMinter(uint256 newAllowance, uint256 mintAmount) public {
        vm.assume(newAllowance < type(uint256).max / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()); // avoid overflow because of fees
        vm.assume(mintAmount <= newAllowance);
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.expectEmit(true, true, true, true, address(token));
        emit MintingAllowanceChanged(MINTER, newAllowance);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, newAllowance);
        assertTrue(token.mintingAllowance(MINTER) == newAllowance, "minting allowance should be newAllowance");

        vm.prank(MINTER);
        token.mint(PAUSER, mintAmount);
        assertTrue(token.balanceOf(PAUSER) == mintAmount, "balance of PAUSER should be mintAmount");
        assertTrue(
            token.mintingAllowance(MINTER) == newAllowance - mintAmount,
            "minting allowance should be newAllowance - mintAmount"
        );

        // set allowance to 0
        vm.prank(MINT_ALLOWER);
        token.decreaseMintingAllowance(MINTER, UINT256_MAX);
        assertTrue(token.mintingAllowance(MINTER) == 0);
    }

    function testMintOnce(uint256 x) public {
        vm.assume(x <= UINT256_MAX / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()); // avoid overflow
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, x);
        assertTrue(token.mintingAllowance(MINTER) == x);

        vm.prank(MINTER);
        token.mint(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == x);
        assertTrue(token.mintingAllowance(MINTER) == 0);
    }

    function testMint0() public {
        uint x = 0;
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, x);
        assertTrue(token.mintingAllowance(MINTER) == x);

        vm.prank(MINTER);
        token.mint(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == x);
        assertTrue(token.mintingAllowance(MINTER) == 0);
    }

    function testMintAllowerDoesNotNeedAllowance(uint256 x) public {
        vm.assume(x <= UINT256_MAX / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()); // avoid overflow
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        assertTrue(token.mintingAllowance(MINT_ALLOWER) == 0);

        vm.prank(MINT_ALLOWER);
        token.mint(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == x);
        assertTrue(token.mintingAllowance(MINTER) == 0);
    }

    function testMintWith0Fee() public {
        uint256 x = 1; // fee is 1%, so fee will be 0

        vm.prank(MINT_ALLOWER);
        token.mint(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == x);
        assertTrue(token.totalSupply() == x);
    }

    function testIncreaseAllowance(uint256 x, uint256 y) public {
        vm.assume(
            x < UINT256_MAX - y && x + y <= UINT256_MAX / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()
        ); // avoid overflow

        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);

        vm.startPrank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, x);
        assertTrue(token.mintingAllowance(MINTER) == x);

        token.increaseMintingAllowance(MINTER, y);
        assertTrue(token.mintingAllowance(MINTER) == x + y);
        vm.stopPrank();

        vm.prank(MINTER);
        token.mint(PAUSER, y);
        assertTrue(token.balanceOf(PAUSER) == y);
        assertTrue(token.mintingAllowance(MINTER) == x);

        vm.prank(MINTER);
        token.mint(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == x + y);
        assertTrue(token.mintingAllowance(MINTER) == 0);
    }

    function testDecreaseAllowance(uint256 x, uint256 y) public {
        vm.assume(x > y);

        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);

        vm.expectEmit(true, true, true, true, address(token));
        emit MintingAllowanceChanged(MINTER, x);
        vm.startPrank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, x);
        assertTrue(token.mintingAllowance(MINTER) == x);

        vm.expectEmit(true, true, true, true, address(token));
        emit MintingAllowanceChanged(MINTER, x - y);
        token.decreaseMintingAllowance(MINTER, y);
        assertTrue(token.mintingAllowance(MINTER) == x - y);

        // decrease works with more than the current allowance and results in 0
        token.decreaseMintingAllowance(MINTER, x);
        vm.stopPrank();

        assertTrue(token.mintingAllowance(MINTER) == 0);
    }

    function testMintingFailsIfMintAllowanceUsed(uint256 x) public {
        vm.assume(x <= UINT256_MAX / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()); // avoid overflow
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, x);
        assertTrue(token.mintingAllowance(MINTER) == x);

        vm.prank(MINTER);
        token.mint(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == x);
        assertTrue(token.mintingAllowance(MINTER) == 0);

        vm.prank(MINTER);
        vm.expectRevert(Token.MintingAllowanceTooLow.selector);
        token.mint(PAUSER, 1);
    }

    /**
     *  test if the MINTER can mint exactly the amount of tokens that is allowed, but in multiple steps
     */
    function testMintAgain(uint256 totalMintAmount, uint256 steps) public {
        vm.assume(totalMintAmount <= UINT256_MAX / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()); // avoid overflow
        //vm.assume(steps < 200);

        steps = steps % 100; // don't be ridiculous

        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, totalMintAmount);
        assertTrue(token.mintingAllowance(MINTER) == totalMintAmount);

        // mint in steps
        uint256 minted = 0;
        for (uint256 i = 0; i < steps; i++) {
            uint256 mintAmount = totalMintAmount / steps;
            vm.prank(MINTER);
            token.mint(PAUSER, mintAmount);
            minted += mintAmount;
            assertTrue(token.balanceOf(PAUSER) == minted);
            assertTrue(token.mintingAllowance(MINTER) == totalMintAmount - minted);
        }

        // mint the rest
        if (totalMintAmount - minted > 0) {
            vm.prank(MINTER);
            token.mint(PAUSER, totalMintAmount - minted);
            assertTrue(token.balanceOf(PAUSER) == totalMintAmount);
            assertTrue(token.mintingAllowance(MINTER) == 0);
        }
    }

    function testMintingFailsIfMintAllowanceRevoked(uint256 x) public {
        vm.assume(x > 0);

        assertTrue(token.mintingAllowance(MINTER) == 0); // check allowance is 0

        vm.prank(MINTER);
        vm.expectRevert(Token.MintingAllowanceTooLow.selector);
        token.mint(PAUSER, x); // try to mint -> must fail!
    }

    function testBurnSimple(uint256 x) public {
        vm.assume(x <= UINT256_MAX / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()); // avoid overflow
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        bytes32 role = token.BURNER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, x);
        assertTrue(token.mintingAllowance(MINTER) == x);

        console.log("minting %s tokens", x);
        console.log("fee demoninator: %s", FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR());
        console.log("amount: %s", x);

        console.log("remainder: %s", x % FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR());
        console.log(
            "amount without remainder: %s",
            x - (x % FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR())
        );

        console.log(
            "total tokens to mint (amount + fee): %s",
            x + x / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()
        );

        uint fee = x / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR();
        console.log("fee: %s", fee);
        vm.prank(MINTER);
        token.mint(PAUSER, x);
        console.log("failed minting");
        assertTrue(token.balanceOf(PAUSER) == x, "PAUSER balance is wrong before burn");
        vm.prank(ADMIN);
        token.grantRole(role, BURNER);
        vm.prank(BURNER);
        token.burn(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == 0, "PAUSER balance is wrong");
    }

    /**
     * Burn with requirements
     */
    function testBurnWithRequirements(uint256 x) public {
        vm.assume(x <= UINT256_MAX / FeeSettings(address(token.feeSettings())).FEE_DENOMINATOR()); // avoid overflow
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, x);
        assertTrue(token.mintingAllowance(MINTER) == x);

        vm.prank(MINTER);
        token.mint(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == x);

        // set requirements
        vm.prank(REQUIRER);
        token.setRequirements(3);

        vm.prank(BURNER);
        token.burn(PAUSER, x);
        assertTrue(token.balanceOf(PAUSER) == 0);
    }

    function testBurn0() public {
        vm.prank(MINT_ALLOWER);
        token.decreaseMintingAllowance(MINTER, UINT256_MAX);
        assertTrue(token.mintingAllowance(MINTER) == 0);

        vm.prank(MINTER);
        token.mint(PAUSER, 0);
        assertTrue(token.balanceOf(PAUSER) == 0);

        vm.prank(BURNER);
        token.burn(PAUSER, 0);
        assertTrue(token.balanceOf(PAUSER) == 0);
    }

    function testTransferTo0(address _address) public {
        vm.assume(token.balanceOf(_address) == 0);
        vm.assume(_address != address(0));
        vm.assume(_address != TRUSTED_FORWARDER);
        vm.assume(_address != FeeSettings(address(token.feeSettings())).feeCollector());

        uint _amount = 100;

        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, _amount);

        vm.prank(MINTER);
        token.mint(_address, _amount);
        assertTrue(token.balanceOf(_address) == _amount, "balance is wrong");

        vm.expectRevert("ERC20: transfer to the zero address");
        vm.prank(_address);
        token.transfer(address(0), _amount);
    }

    function testTransferFrom0(address _address) public {
        uint _amount = 100;

        vm.expectRevert("ERC20: transfer from the zero address");
        vm.prank(address(0));
        token.transfer(_address, _amount);
    }

    function testBurningNonExistentTokensFails() public {
        vm.prank(BURNER);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.burn(PAUSER, 1);
    }

    function testBeforeTokenTransfer() public {
        // create tokens
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        vm.prank(MINTER);
        token.mint(PAUSER, 50);
        assertTrue(token.balanceOf(PAUSER) == 50);

        // create TRANSFERER
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleTransfererAdmin, TRANSFERER_ADMIN);

        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, TRANSFERER);
        assertTrue(token.hasRole(roleTransferer, TRANSFERER));

        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, BURNER);
        assertTrue(token.hasRole(roleTransferer, BURNER));

        // move tokens around
        vm.prank(PAUSER);
        token.transfer(BURNER, 50);
        assertTrue(token.balanceOf(BURNER) == 50);
    }

    function testTokenTransferFailsIfRequirementsNotMet() public {
        // create tokens
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        //SetRequirements
        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        vm.prank(REQUIRER);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        assertTrue(token.hasRole(roleTransferer, TRANSFERER));

        vm.prank(MINTER);
        token.mint(TRANSFERER, 50);

        assertTrue(token.balanceOf(TRANSFERER) == 50);

        // move tokens around
        vm.prank(TRANSFERER);
        vm.expectRevert(Token.NotAllowedToTransact.selector);
        token.transfer(BURNER, 50);
        assertTrue(token.balanceOf(BURNER) == 0);
    }

    function testBeforeTokenTransferRequirementsOverfulfilled() public {
        // create tokens
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        vm.prank(REQUIRER);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3, "requirements not set");

        vm.prank(ADMIN);
        allowList.set(PAUSER, 7);
        vm.prank(MINTER);
        token.mint(PAUSER, 50);

        assertTrue(token.balanceOf(PAUSER) == 50, "balance not minted");
    }

    function testTokenTransferFailsIfRequirementsNotfulfilled() public {
        // grant minting allowance
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        //SetRequirements
        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        vm.prank(REQUIRER);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        vm.prank(ADMIN);
        allowList.set(PAUSER, 4); // only one bit set, but bit 1 and 2 (=3) should be set
        vm.prank(MINTER);
        vm.expectRevert(Token.NotAllowedToTransact.selector);
        token.mint(PAUSER, 50);

        assertTrue(token.balanceOf(PAUSER) == 0);
    }

    function testBeforeTokenTransferRequirements2() public {
        // create tokens
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        vm.prank(REQUIRER);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3); // 0x0011

        vm.prank(ADMIN);
        allowList.set(PAUSER, 7); // 0x0111 -> includes required 0x0011
        vm.prank(MINTER);
        token.mint(PAUSER, 50);

        assertTrue(token.balanceOf(PAUSER) == 50);

        // create TRANSFERER
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleTransfererAdmin, TRANSFERER_ADMIN);

        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, TRANSFERER);
        assertTrue(token.hasRole(roleTransferer, TRANSFERER));

        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, BURNER);
        assertTrue(token.hasRole(roleTransferer, BURNER));

        // move tokens around
        vm.prank(PAUSER);
        token.transfer(BURNER, 20);
        assertTrue(token.balanceOf(BURNER) == 20);
        assertTrue(token.balanceOf(PAUSER) == 30);
    }

    function testTransferWhilePaused() public {
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        //SetRequirements
        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        vm.prank(REQUIRER);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        vm.prank(ADMIN);
        allowList.set(MINTER, 3);
        vm.prank(ADMIN);
        allowList.set(PAUSER, 3);
        vm.prank(MINTER);
        token.mint(PAUSER, 50);

        assertTrue(token.balanceOf(PAUSER) == 50);

        // create TRANSFERER
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleTransfererAdmin, TRANSFERER_ADMIN);

        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, TRANSFERER);
        assertTrue(token.hasRole(roleTransferer, TRANSFERER));

        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, BURNER);
        assertTrue(token.hasRole(roleTransferer, BURNER));

        // move tokens around
        vm.prank(PAUSER);
        token.transfer(BURNER, 20);
        assertTrue(token.balanceOf(BURNER) == 20);

        //pause
        bytes32 rolePauser = token.PAUSER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(rolePauser, PAUSER);
        assertTrue(token.hasRole(rolePauser, PAUSER));

        vm.prank(PAUSER);
        token.pause();

        // move tokens around with pause
        vm.prank(PAUSER);
        vm.expectRevert("Pausable: paused");
        token.transfer(BURNER, 20);
        assertTrue(token.balanceOf(BURNER) == 20);
    }

    function testTransferUnpaused() public {
        // create tokens
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        vm.prank(REQUIRER);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        vm.prank(ADMIN);
        allowList.set(MINTER, 3);
        vm.prank(ADMIN);
        allowList.set(PAUSER, 3);
        vm.prank(MINTER);
        token.mint(PAUSER, 50);

        assertTrue(token.balanceOf(PAUSER) == 50);

        // create TRANSFERER
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleTransfererAdmin, TRANSFERER_ADMIN);

        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, TRANSFERER);
        assertTrue(token.hasRole(roleTransferer, TRANSFERER));

        vm.prank(TRANSFERER_ADMIN);
        token.grantRole(roleTransferer, BURNER);
        assertTrue(token.hasRole(roleTransferer, BURNER));

        // move tokens around
        vm.prank(PAUSER);
        token.transfer(BURNER, 20);
        assertTrue(token.balanceOf(BURNER) == 20);

        //pause
        bytes32 rolePauser = token.PAUSER_ROLE();
        vm.prank(ADMIN);
        token.grantRole(rolePauser, PAUSER);
        assertTrue(token.hasRole(rolePauser, PAUSER));

        vm.prank(PAUSER);
        token.pause();

        assertTrue(token.paused());

        vm.prank(PAUSER);
        token.unpause();

        assertFalse(token.paused());

        // move tokens around with pause
        vm.prank(PAUSER);
        token.transfer(BURNER, 20);
        assertTrue(token.balanceOf(BURNER) == 40);
    }

    function testTransferWith0Requirements() public {
        uint256 mintAmount = 200;
        uint256 transferAmount = 82;
        address receiver = address(0x123);
        vm.assume(mintAmount >= transferAmount);
        vm.assume(mintAmount < type(uint256).max / 2); // avoid overflow due to fees
        vm.assume(receiver != address(0));
        vm.assume(receiver != PAUSER);

        // create tokens
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, mintAmount);
        assertTrue(token.mintingAllowance(MINTER) == mintAmount);

        // set requirements to 0
        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(ADMIN);
        token.grantRole(role, REQUIRER);
        vm.prank(REQUIRER);
        token.setRequirements(0);
        assertTrue(token.requirements() == 0);

        // mint some tokens
        vm.prank(MINTER);
        token.mint(PAUSER, mintAmount);

        assertTrue(token.balanceOf(PAUSER) == mintAmount);

        // transfer token
        vm.prank(PAUSER);
        uint256 gasAfter = gasleft();
        uint256 gasBefore = gasleft();
        token.transfer(receiver, transferAmount);
        gasAfter = gasleft();

        console.log("gas used: ", gasBefore - gasAfter);

        assertTrue(token.balanceOf(PAUSER) == mintAmount - transferAmount);
        assertTrue(token.balanceOf(receiver) == transferAmount);
    }

    function testLoseAndGainRequirements() public {
        address person1 = vm.addr(1);
        address person2 = vm.addr(2);

        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        // //testSetRequirements
        vm.prank(REQUIRER);
        token.setRequirements(11);
        assertTrue(token.requirements() == 11); // 0x1011

        vm.prank(ADMIN);
        allowList.set(person1, 27); // 0x0111 -> includes required 0x0011
        vm.prank(ADMIN);
        allowList.set(person2, 11); // 0x1011

        vm.prank(MINTER);
        token.mint(person1, 50);
        assertTrue(token.balanceOf(person1) == 50);

        vm.prank(person1);
        token.transfer(person2, 20);
        assertTrue(token.balanceOf(person2) == 20);
        assertTrue(token.balanceOf(person1) == 30);

        // person1 loses requirements
        vm.prank(ADMIN);
        allowList.set(person1, 3); // 0x0011 -> does not include required 0x1011

        console.log("person1: ", person1);

        vm.prank(person1);
        vm.expectRevert(Token.NotAllowedToTransact.selector);
        token.transfer(person2, 20);
        assertTrue(token.balanceOf(person2) == 20);
        assertTrue(token.balanceOf(person1) == 30);

        vm.prank(person2);
        vm.expectRevert(Token.NotAllowedToTransact.selector);
        token.transfer(person1, 10);
        assertTrue(token.balanceOf(person2) == 20);
        assertTrue(token.balanceOf(person1) == 30);

        // requirements are lowered to 3
        vm.prank(REQUIRER);
        token.setRequirements(3); // 0x0011
        assertTrue(token.requirements() == 3);

        // now transfers should work again between person 1 and 2
        vm.prank(person1);
        token.transfer(person2, 20);
        assertTrue(token.balanceOf(person2) == 40);
        assertTrue(token.balanceOf(person1) == 10);

        vm.prank(person2);
        token.transfer(person1, 10);
        assertTrue(token.balanceOf(person2) == 30);
        assertTrue(token.balanceOf(person1) == 20);
    }

    /*
        mint more than mintingAllowance
        behavior of mintingAllowance is to not take into account tokens
        already minted once a new allowance is set
    */
    function testExceedMintingAllowance() public {
        address person1 = vm.addr(1);
        address person2 = vm.addr(2);

        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        // //testSetRequirements
        vm.prank(REQUIRER);
        token.setRequirements(11);
        assertTrue(token.requirements() == 11); // 0x1011

        vm.prank(ADMIN);
        allowList.set(person1, 27); // 0x0111 -> includes required 0x0011
        vm.prank(ADMIN);
        allowList.set(person2, 11); // 0x1011

        vm.prank(MINTER);
        token.mint(person1, 50);
        assertTrue(token.balanceOf(person1) == 50);

        vm.prank(MINT_ALLOWER);
        token.decreaseMintingAllowance(MINTER, UINT256_MAX);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 10);
        assertTrue(token.mintingAllowance(MINTER) == 10);

        vm.prank(MINTER);
        //vm.expectRevert("Minting allowance exceeded");
        token.mint(person2, 3);
        assertTrue(token.balanceOf(person2) == 3);
    }

    function testIncreaseMintingAllowance() public {
        address person1 = vm.addr(1);
        address person2 = vm.addr(2);

        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 100);
        assertTrue(token.mintingAllowance(MINTER) == 100);

        // //testSetRequirements
        vm.prank(REQUIRER);
        token.setRequirements(11);
        assertTrue(token.requirements() == 11); // 0x1011

        vm.prank(ADMIN);
        allowList.set(person1, 27); // 0x0111 -> includes required 0x0011
        vm.prank(ADMIN);
        allowList.set(person2, 11); // 0x1011

        vm.prank(MINTER);
        token.mint(person1, 50);
        assertTrue(token.balanceOf(person1) == 50);

        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 10);
        assertTrue(token.mintingAllowance(MINTER) == 60);

        vm.prank(MINTER);
        token.mint(person2, 55);

        assertTrue(token.balanceOf(person2) == 55);
    }

    function testDeployerDoesNotGetRole() public {
        Token localToken = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                allowList,
                0x0,
                "testTokenRole",
                "TEST"
            )
        );
        address deployer = msg.sender;
        assertFalse(localToken.hasRole(localToken.REQUIREMENT_ROLE(), deployer));
        assertFalse(localToken.hasRole(localToken.MINTALLOWER_ROLE(), deployer));
        assertFalse(localToken.hasRole(localToken.BURNER_ROLE(), deployer));
        assertFalse(localToken.hasRole(localToken.TRANSFERERADMIN_ROLE(), deployer));
        assertFalse(localToken.hasRole(localToken.TRANSFERER_ROLE(), deployer));
        assertFalse(localToken.hasRole(localToken.PAUSER_ROLE(), deployer));
    }

    function testAcceptFeeSettings0() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        token.acceptNewFeeSettings(FeeSettings(address(0)));
    }

    /**
     * This test checks if the token contract's storage begins at slot 1000.
     * This is important. For more information, see ../docs/upgradeability.md
     */
    function testTokenStorageGap(address _allowList) public {
        vm.assume(_allowList != address(0));
        vm.startPrank(ADMIN);
        token.setAllowList(AllowList(_allowList));
        vm.stopPrank();

        bytes32 inputAddress = bytes32(uint256(uint160(_allowList)));
        console.logBytes32(inputAddress);
        bytes32 storedAddress = vm.load(address(token), bytes32(uint256(1000)));
        console.logBytes32(storedAddress);

        assertEq(
            storedAddress,
            inputAddress,
            "stored address is not the same as input address. Storage slot of allowList in Token changed!"
        );
    }
}
