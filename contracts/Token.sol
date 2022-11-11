// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "./AllowList.sol";

/**
@title tokenize.it Token
@notice This contract implements the token used to tokenize companies, which follows the ERC20 standard and adds the following features:
    - pausing
    - access control with dedicated roles
    - burning (burner role can burn any token from any address)
    - requirements for sending and receiving tokens
    - allow list (documents which address satisfies which requirement)
    Decimals is inherited as 18 from ERC20. This should be the standard to adhere by for all deployments of this token.

    The contract inherits from ERC2771Context in order to be usable with Gas Station Network (GSN) https://docs.opengsn.org/faq/troubleshooting.html#my-contract-is-using-openzeppelin-how-do-i-add-gsn-support and meta-transactions.

 */
contract Token is ERC2771Context, ERC20Permit, Pausable, AccessControl {
    /// @notice The role that has the ability to define which requirements an address must satisfy to receive tokens
    bytes32 public constant REQUIREMENT_ROLE = keccak256("REQUIREMENT_ROLE");
    /// @notice The role that has the ability to grant the minter role
    bytes32 public constant MINTERADMIN_ROLE = keccak256("MINTERADMIN_ROLE");
    /// @notice The role that has the ability to mint tokens. Will be granted to the relevant PersonalInvite and ContinuousFundraising contracts.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice The role that has the ability to burn tokens from anywhere. Usage is planned for legal purposes and error recovery.
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    /// @notice The role that has the ability to grant transfer rights to other addresses
    bytes32 public constant TRANSFERERADMIN_ROLE = keccak256("TRANSFERERADMIN_ROLE");
    /// @notice Addresses with this role do not need to satisfy any requirements to send or receive tokens
    bytes32 public constant TRANSFERER_ROLE = keccak256("TRANSFERER_ROLE");
    /// @notice The role that has the ability to pause the token
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice The role that has the ability to set the address collecting the platform fee (per default, that is the tokenize.it multi-sig)
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

    // Map managed by tokenize.it, which assigns addresses requirements which they fulfill
    AllowList public allowList;
    /**
    @notice  defines requirements to send or receive tokens for non-TRANSFERER_ROLE. If zero, everbody can transfer the token. If non-zero, then only those who have met the requirements can send or receive tokens. 
        Requirements can be defined by the REQUIREMENT_ROLE, and are validated against the allowList. They can include things like "must have a verified email address", "must have a verified phone number", "must have a verified identity", etc. 
        Also, tiers from 0 to four can be used.
    @dev Requirements are defined as bit mask, with the bit position encoding it's meaning and the bit's value whether this requirement will be enforced. 
        Example:
        - position 0: 1 = must be KYCed (0 = no KYC required)
        - position 1: 1 = must be american citizen (0 = american citizenship not required)
        - position 2: 1 = must be a penguin (0 = penguin status not required)
        These meanings are not defined within the token contract. They MUST match the definitions used in the corresponding allowList contract.
        With requirements 0b0000000000000000000000000000000000000000000000000000000000000101, only KYCed penguins will be allowed to send or receive tokens.
        With requirements 0b0000000000000000000000000000000000000000000000000000000000000111, only KYCed american penguins will be allowed to send or receive tokens.
        With requirements 0b0000000000000000000000000000000000000000000000000000000000000000, even french hedgehogs will be allowed to send or receive tokens.

        The highest four bits are defined as tiers as follows:
        - 0b0000000000000000000000000000000000000000000000000000000000000000 = tier 0 is required
        - 0b0001000000000000000000000000000000000000000000000000000000000000 = tier 1 is required
        - 0b0010000000000000000000000000000000000000000000000000000000000000 = tier 2 is required
        - 0b0100000000000000000000000000000000000000000000000000000000000000 = tier 3 is required
        - 0b1000000000000000000000000000000000000000000000000000000000000000 = tier 4 is required
        This very simple definition allows for a maximum of 5 tiers, even though 4 bits are used for encoding. By sacrificing some space it can be implemented without code changes.

        Keep in mind that addresses with the TRANSFERER_ROLE do not need to satisfy any requirements to send or receive tokens.
    */
    uint256 public requirements;

    /// @notice defines the maximum amount of tokens that can be minted by a specific minter. If zero, no tokens can be minted.
    mapping(address => uint256) public mintingAllowance; // used for token generating events such as vesting or new financing rounds

    /// @notice address used to pay platform fees to. Also used as the address having the FEE_COLLECTOR_ROLE, given the ability to change this address.
    address public feeCollector;

    event RequirementsChanged(uint newRequirements);
    event AllowListChanged(AllowList indexed newAllowList);
    event MintingAllowanceChanged(address indexed newMinter, uint256 newAllowance);
    event FeeCollectorChanged(address indexed newFeeCollector);

    /**
    @notice Constructor for the token 
    @param _trustedForwarder trusted forwarder for the ERC2771Context constructor - used for meta-transactions
    @param _name name of the specific token, e.g. "MyGmbH Token"
    @param _symbol symbol of the token, e.g. "MGT"
    @param _allowList address of the allowList contract
    @param _requirements requirements an address has to meet for sending or receiving tokens
    @param _admin address of the admin. Admin will initially have all roles and can grant roles to other addresses.
    */
    constructor(address _trustedForwarder, address _admin, AllowList _allowList, uint256 _requirements, string memory _name, string memory _symbol) ERC2771Context(_trustedForwarder) ERC20Permit(_name) ERC20(_name, _symbol) {
        // Grant admin roles
        _setupRole(DEFAULT_ADMIN_ROLE, _admin); // except for the Minter and Transferer role, the _admin is the roles admin for all other roles
        _setRoleAdmin(MINTER_ROLE, MINTERADMIN_ROLE);
        _setRoleAdmin(TRANSFERER_ROLE, TRANSFERERADMIN_ROLE);

        // grant all roles to admin for now. Can be changed later, see https://docs.openzeppelin.com/contracts/2.x/api/access#Roles
        _grantRole(REQUIREMENT_ROLE, _admin);
        _grantRole(MINTERADMIN_ROLE, _admin);
        _grantRole(BURNER_ROLE, _admin);
        _grantRole(TRANSFERERADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        // set up fee collection
        feeCollector = 0x0000000000000000000000000000000000000000; // TODO - replace with tokenize.it multi-sig
        _grantRole(FEE_COLLECTOR_ROLE, feeCollector);        

        allowList = _allowList;
        requirements = _requirements;
    }

    function setAllowList(AllowList _allowList) public onlyRole(DEFAULT_ADMIN_ROLE) {
        allowList = _allowList;
        emit AllowListChanged(_allowList);
    }

    function setRequirements(uint256 _requirements) public onlyRole(REQUIREMENT_ROLE) {
        requirements = _requirements;
        emit RequirementsChanged(_requirements);
    }

    function setFeeCollector(address _feeCollector) public onlyRole(FEE_COLLECTOR_ROLE) {
        feeCollector = _feeCollector;
        emit FeeCollectorChanged(_feeCollector);
    }

    /** 
        @notice minting contracts such as personal investment invite, vesting, crowdfunding must be granted minter role through this function. 
            Each call of setUpMinter will make the contract: 
                1. forget how many tokens might have been minted by this minter before. 
                2. set the allowance for this minter to the new value, discarding any remaining allowance that might have been left from before.
            This feels very natural on the first call, but might be surprising on subsequent calls, so be careful.
        @dev The "forget last allowance and count of minted tokens" behavior is accepted in order to reduce the complexity of the contract as well as it's gas usage.
        @param _minter address of the minter contract
        @param _allowance maximum amount of tokens that can be minted by this minter IN THIS ROUND
    */
    function setUpMinter(address _minter, uint256 _allowance) public onlyRole(getRoleAdmin(MINTER_ROLE)){
        _grantRole(MINTER_ROLE, _minter);
        require(mintingAllowance[_minter] == 0 || _allowance == 0); // to prevent frontrunning when setting a new allowance, see https://www.adrianhetman.com/unboxing-erc20-approve-issues/
        mintingAllowance[_minter] = _allowance;
        emit MintingAllowanceChanged(_minter, _allowance);
    }

    function mint(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) returns (bool) {
        require(mintingAllowance[_msgSender()] >= _amount, "MintingAllowance too low");
        mintingAllowance[_msgSender()] -= _amount;
        _mint(_to, _amount);
        // collect fees
        _mint(feeCollector, _amount/100);
        return true;
    }

    function burn(address _from, uint256 _amount) public onlyRole(BURNER_ROLE) {
        _burn(_from, _amount);
    }

    /**
    @notice aborts transfer if the sender or receiver is neither transferer nor fulfills the requirements nor is the 0x0 address
    @dev this hook is executed before the transfer function itself 
     */
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual override {
        super._beforeTokenTransfer(_from, _to, _amount);
        _requireNotPaused();
        require(
            hasRole(BURNER_ROLE, _msgSender()) || hasRole(TRANSFERER_ROLE, _from) || allowList.map(_from) & requirements == requirements || _from == address(0),
            "Sender is not allowed to transact. Either locally issue the role as a TRANSFERER or they must meet requirements as defined in the allowList"
        ); // address(0), because this is the _from address in case of minting new tokens
        require(
            hasRole(TRANSFERER_ROLE, _to) || allowList.map(_to) & requirements == requirements || _to == address(0),
            "Receiver is not allowed to transact. Either locally issue the role as a TRANSFERER or they must meet requirements as defined in the allowList"
        ); // address(0), because this is the _to address in case of burning tokens
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev both ERC20Pausable and ERC2771Context have a _msgSender() function, so we need to override and select which one to use.
     */ 
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    /**
     * @dev both ERC20Pausable and ERC2771Context have a _msgData() function, so we need to override and select which one to use.
     */
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}
