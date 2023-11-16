// SPDX-License-Identifier: MIT
// derived from OpenZeppelin Contracts (last updated v4.9.0) (finance/VestingWallet.sol)
/// @author cjentzsch, malteish

pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

interface ERC20Mintable {
    function mint(address, uint256) external;
}

struct VestingPlan {
    /// the amount of tokens to be vested
    uint256 allocation;
    /// the amount of tokens already released
    uint256 released;
    /// the beneficiary who will receive the vested tokens
    address beneficiary;
    /// the start time of the vesting
    uint64 start;
    /// the cliff duration of the vesting - beneficiary gets no tokens before this duration has passed
    uint64 cliff;
    /// the duration of the vesting - after this duration all tokens can be released
    uint64 duration;
    /// if true, the token can be claimed through minting, otherwise the tokens are owned by the contract and can be transferred
    bool isMintable;
}

/**
 * @title Vesting
 * @dev This contract handles the vesting ERC20 tokens for a set of beneficiaries. Custody of multiple tokens
 * can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
 *
 */
contract Vesting is Initializable, ERC2771ContextUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    event Commit(bytes32 hash);
    event ERC20Released(uint64 id, uint256 amount);
    event Revoke(bytes32 hash, uint64 endVestingTime);
    event Reveal(bytes32 hash, uint64 id);
    event VestingCreated(uint64 id);
    event VestingStopped(uint64 id, uint64 endTime);
    event ManagerAdded(address manager);
    event ManagerRemoved(address manager);
    event BeneficiaryChanged(uint64 id, address newBeneficiary);

    uint64 public constant TIME_HORIZON = 20 * 365 days; // 20 years
    /// token to be vested
    address public token;
    /// managers that can create vestings
    mapping(address => bool) public managers; 
    mapping(uint64 => VestingPlan) public vestings;
    /// stores promises without revealing the details. value = maximum end date of vesting
    mapping(bytes32 => uint64) public commitments;
    /// total amount of vesting plans created
    uint64 public ids;

    /**
     * This contract will be used through clones, so the constructor only initializes
     * the logic contract.
     * @param trustedForwarder address of the trusted forwarder that can relay ERC2771 transactions
     */
    constructor(address trustedForwarder) ERC2771ContextUpgradeable(trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract.
     * @param _owner address of the owner of the contract
     * @param _token address of the token to be vested
     */
    function initialize(address _owner, address _token) public initializer {
        require(_owner != address(0), "Owner must not be zero address");
        require(_token != address(0), "Token must not be zero address");
        __Ownable_init();
        transferOwnership(_owner);
        managers[_owner] = true;
        token = _token;
    }

    /**
     * @dev Getter for the allocation.
     *
     */
    function allocation(uint64 _id) public view returns (uint256) {
        return vestings[_id].allocation;
    }

    /**
     * @dev Amount of tokens already released
     */
    function released(uint64 _id) public view returns (uint256) {
        return vestings[_id].released;
    }

    /**
     * @dev Getter for the beneficiary address.
     */
    function beneficiary(uint64 _id) public view returns (address) {
        return vestings[_id].beneficiary;
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start(uint64 _id) public view returns (uint64) {
        return vestings[_id].start;
    }

    /**
     * @dev Getter for the cliff duration.
     */
    function cliff(uint64 _id) public view returns (uint64) {
        return vestings[_id].cliff;
    }

    /**
     * @dev Getter for the total vesting duration.
     */
    function duration(uint64 _id) public view returns (uint64) {
        return vestings[_id].duration;
    }

    /**
     * @dev Getter for type of withdraw.
     * isMintable == true means that tokens are minted form the token contract.
     * isMintable == false means the tokens need to be held by the vesting contract directly.
     */
    function isMintable(uint64 _id) public view returns (bool) {
        return vestings[_id].isMintable;
    }

    /**
     * @dev Getter for the amount of releasable tokens.
     */
    function releasable(uint64 _id) public view returns (uint256) {
        return vestedAmount(_id, uint64(block.timestamp)) - released(_id);
    }

    /**
     * Managers can commit to a vesting plan without revealing it's details.
     * The parameters are hashed and this hash is stored in the commitments mapping.
     * Anyone can then reveal the vesting plan by providing the parameters and the salt.
     * @param _hash commitment hash
     */
    function commit(bytes32 _hash) external onlyManager {
        require(_hash != bytes32(0), "hash must not be zero");
        // the value is interpreted as maximum end date of the vesting
        // for real world use cases, type(uint64).max is "unlimited"
        commitments[_hash] = type(uint64).max;
        emit Commit(_hash);
    }

    /**
     * Managers can revoke a commitment by providing the hash and a new latest end date.
     * @param _hash commitment hash
     * @param _end new latest end date
     */
    function revoke(bytes32 _hash, uint64 _end) external onlyManager {
        require(commitments[_hash] != 0, "invalid-hash");
        // already vested tokens can not be taken away (except of burning in the token contract itself)
        _end = uint64(block.timestamp) > _end ? uint64(block.timestamp) : _end;
        commitments[_hash] = _end;
        emit Revoke(_hash, _end);
    }

    /**
     * Create a public transparent vesting plan from a commitment.
     * @param _hash  commitment hash
     * @param _allocation total token amount
     * @param _beneficiary address receiving the tokens
     * @param _start start date
     * @param _cliff cliff duration
     * @param _duration total duration
     * @param _isMintable true = tokens minted on release, false = tokens held by vesting contract
     * @param _salt salt for privacy
     */
    function reveal(
        bytes32 _hash,
        uint256 _allocation,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        bool _isMintable,
        bytes32 _salt
    ) public returns (uint64 id) {
        require(
            _hash ==
                keccak256(abi.encodePacked(_allocation, _beneficiary, _start, _cliff, _duration, _isMintable, _salt)),
            "invalid-hash"
        );
        uint64 maxEndDate = commitments[_hash];
        require(maxEndDate > 0, "invalid-hash");
        // if a commitment has been revoked with end date before cliff, it can never be revealed
        require(_start + _cliff <= maxEndDate, "commitment revoked before cliff ended");

        if (_start + _duration <= maxEndDate) {
            // the commitment has not been revoked, or the end date of the commitment is after the end of the vesting
            // create the vesting using the original parameters
            id = _createVesting(_allocation, _beneficiary, _start, _cliff, _duration, _isMintable);
        } else {
            // the commitment has been revoked with a new end date of maxEndDate
            // we need to override the duration to be the difference between _start and maxEndDate
            uint64 durationOverride = maxEndDate - _start;
            uint256 allocationOverride = (_allocation * durationOverride) / _duration;
            id = _createVesting(allocationOverride, _beneficiary, _start, _cliff, durationOverride, _isMintable);
        }

        commitments[_hash] = 0; // delete commitment
        emit Reveal(_hash, id);
    }

    function revealAndRelease(
        bytes32 _hash,
        uint256 _allocation,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        bool _isMintable,
        bytes32 _salt
    ) external returns (uint64 id) {
        id = reveal(_hash, _allocation, _beneficiary, _start, _cliff, _duration, _isMintable, _salt);
        release(id);
    }

    function createVesting(
        uint256 _allocation,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        bool _isMintable
    ) external onlyManager returns (uint64 id) {
        return _createVesting(_allocation, _beneficiary, _start, _cliff, _duration, _isMintable);
    }

    function _createVesting(
        uint256 _allocation,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        bool _isMintable
    ) internal returns (uint64 id) {
        require(_allocation > 0, "Allocation must be greater than zero");
        require(_beneficiary != address(0), "Beneficiary must not be zero address");
        require(
            _start >= block.timestamp - TIME_HORIZON && _start <= block.timestamp + TIME_HORIZON,
            "Start must be reasonable"
        );
        require(_cliff >= 0 && _cliff <= _duration, "Cliff must be reasonable");
        require(_duration > 0 && _duration <= TIME_HORIZON, "Duration must be reasonable");

        id = ids++;
        vestings[id] = VestingPlan({
            allocation: _allocation,
            released: 0,
            beneficiary: _beneficiary,
            start: _start,
            cliff: _cliff,
            duration: _duration,
            isMintable: _isMintable
        });

        emit VestingCreated(id);
    }

    function stopVesting(uint64 _id, uint64 _endTime) public onlyManager {
        // already vested tokens can not be taken away (except of burning in the token contract itself)
        _endTime = _endTime < uint64(block.timestamp) ? uint64(block.timestamp) : _endTime;
        require(_endTime < vestings[_id].start + vestings[_id].duration, "endTime must be before vesting end");

        if (vestings[_id].start + vestings[_id].cliff > _endTime) {
            delete vestings[_id];
        } else {
            vestings[_id].allocation = vestedAmount(_id, _endTime);
            vestings[_id].duration = _endTime - vestings[_id].start;
        }
        emit VestingStopped(_id, _endTime);
    }

    function pauseVesting(uint64 _id, uint64 _endTime, uint64 _newStartTime) external onlyManager returns (uint64) {
        VestingPlan memory vesting = vestings[_id];
        require(_endTime > uint64(block.timestamp), "endTime must be in the future");
        require(_endTime < vesting.start + vesting.duration, "endTime must be before vesting end");
        require(_newStartTime > _endTime, "newStartTime must be after endTime");

        uint256 allocationRemainder = allocation(_id) - vestedAmount(_id, _endTime);
        uint64 timeVested = _endTime - start(_id);
        uint64 cliffRemainder = timeVested >= cliff(_id) ? 0 : cliff(_id) - timeVested;
        uint64 durationRemainder = duration(_id) - timeVested;

        // stop old vesting
        stopVesting(_id, _endTime);

        // create new vesting
        return
            _createVesting(
                allocationRemainder,
                vesting.beneficiary,
                _newStartTime,
                cliffRemainder,
                durationRemainder,
                vesting.isMintable
            );
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {ERC20Released} event.
     */
    function release(uint64 _id) public {
        release(_id, type(uint256).max);
    }

    function release(uint64 _id, uint256 _amount) public nonReentrant {
        require(_msgSender() == beneficiary(_id), "Only beneficiary can release tokens");
        _amount = releasable(_id) < _amount ? releasable(_id) : _amount;
        vestings[_id].released += _amount;
        if (isMintable(_id)) {
            ERC20Mintable(token).mint(beneficiary(_id), _amount);
        } else {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(token), beneficiary(_id), _amount);
        }
        emit ERC20Released(_id, _amount);
    }

    /**
     * @dev Calculates the amount of tokens that have already vested. Implements a linear vesting curve.
     * @notice In this context, "vested" means "belong to the beneficiary". The vested amount
     * is also the sum of the released amount and the releasable amount.
     */
    function vestedAmount(uint64 _id, uint64 _timestamp) public view returns (uint256) {
        VestingPlan memory vesting = vestings[_id];
        if (_timestamp < vesting.start + vesting.cliff) {
            return 0;
        } else if (_timestamp > vesting.start + vesting.duration) {
            return vesting.allocation;
        } else {
            return (vesting.allocation * (_timestamp - vesting.start)) / vesting.duration;
        }
    }

    /**
     * @dev Changes the beneficiary to a new one. Only callable by current beneficiary,
     * or the owner one year after the vesting's plan end. The owner being able to update
     * the beneficiary address is a compromise between security and usability:
     * If the beneficiary ever loses access to their address, the owner can update it, but only
     * after this timeout has passed.
     */
    function changeBeneficiary(uint64 _id, address _newBeneficiary) external {
        require(
            _msgSender() == beneficiary(_id) ||
                ((_msgSender() == owner()) && uint64(block.timestamp) > start(_id) + duration(_id) + 365 days)
        );
        require(_newBeneficiary != address(0), "Beneficiary must not be zero address");
        vestings[_id].beneficiary = _newBeneficiary;
        emit BeneficiaryChanged(_id, _newBeneficiary);
    }

    function addManager(address _manager) external onlyOwner {
        managers[_manager] = true;
        emit ManagerAdded(_manager);
    }

    function removeManager(address _manager) external onlyOwner {
        managers[_manager] = false;
        emit ManagerRemoved(_manager);
    }

    modifier onlyManager() {
        require(managers[_msgSender()], "Caller is not a manager");
        _;
    }

    /**
     * @dev both ContextUpgradeable and ERC2771ContextUpgradeable have a _msgSender() function, so we need to override and select which one to use.
     */
    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /**
     * @dev both ERC20Pausable and ERC2771Context have a _msgData() function, so we need to override and select which one to use.
     */
    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }
}
