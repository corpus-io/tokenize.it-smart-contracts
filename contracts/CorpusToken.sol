// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "./AllowList.sol";

/**
@title Corpus Token
@notice This contract implements the corpus token, which follows the ERC20 standard and adds the following features:
    - pausing
    - access control with dedicated roles
    - burning (burner role can burn any token from any address)
    - requirements for sending and receiving tokens
    - allow list (documents which address satisfies which requirement)
    Decimals is inherited as 18 from ERC20. This should be the standard to adhere by for all deployments of this token.

 */
contract CorpusToken is ERC20Pausable, AccessControl {
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

    // Map managed by corpus, which assigns addresses requirements which they fulfill
    AllowList public allowList;
    /**
    @notice  defines requirements to send or receive tokens for non-TRANSFERER_ROLE. If zero, everbody can transfer the token. If non-zero, then only those who have met the requirements can send or receive tokens. 
        Requirements can be defined by the REQUIREMENT_ROLE, and are validated against the allowList. They can include things like "must have a verified email address", "must have a verified phone number", "must have a verified identity", etc. 
    @dev Requirements are defined as bit mask, with the bit position encoding it's meaning and the bit's value whether this requirement will be enforced. 
        Example:
        - position 0: 1 = must be KYCed (0 = no KYC required)
        - position 1: 1 = must be american citizen (0 = american citizenship not required)
        - position 2: 1 = must be a penguin (0 = penguin status not required)
        These meanings are not defined within the token contract. They MUST match the definitions used in the corresponding allowList contract.
        With requirements 0b0000000000000000000000000000000000000000000000000000000000000101, only KYCed penguins will be allowed to send or receive tokens.
        With requirements 0b0000000000000000000000000000000000000000000000000000000000000111, only KYCed american penguins will be allowed to send or receive tokens.
        With requirements 0b0000000000000000000000000000000000000000000000000000000000000000, even french hedgehogs will be allowed to send or receive tokens.

        Keep in mind that addresses with the TRANSFERER_ROLE do not need to satisfy any requirements to send or receive tokens.
    @notice initialized as 0 (=no requirements), so needs updating if applicable
    */
    uint256 public requirements;

    /// @notice defines the maximum amount of tokens that can be minted by a specific minter. If zero, no tokens can be minted.
    mapping(address => uint256) public mintingAllowance; // used for token generating events such as vesting or new financing rounds

    event RequirementsChanged(uint newRequirements);
    event AllowListChanged(AllowList indexed allowList);
    event MintingAllowanceChanged(address indexed minter, uint256 newAllowance);


    /**
    @notice Constructor for the corpus token 
    @param _name name of the specific token, e.g. "MyGmbH Token"
    @param _symbol symbol of the token, e.g. "MGT"
    @param _allowList address of the allowList contract
    @param _requirements requirements an address has to meet for sending or receiving tokens
    @param _admin address of the admin. Admin will initially have all roles and can grant roles to other addresses.
    */
    constructor(address _admin, AllowList _allowList, uint256 _requirements, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
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
        mintingAllowance[_minter] = _allowance;
        emit MintingAllowanceChanged(_minter, _allowance);
    }

    function mint(address _to, uint256 _amount) public onlyRole(MINTER_ROLE) returns (bool) {
        require(mintingAllowance[msg.sender] >= _amount, "MintingAllowance too low");
        mintingAllowance[msg.sender] -= _amount;
        _mint(_to, _amount);
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

        require(
            hasRole(BURNER_ROLE, msg.sender) || hasRole(TRANSFERER_ROLE, _from) || allowList.map(_from) & requirements == requirements || _from == address(0),
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
}
