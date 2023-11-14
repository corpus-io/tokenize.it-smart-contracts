// SPDX-License-Identifier: MIT
// derived from OpenZeppelin Contracts (last updated v4.9.0) (finance/VestingWallet.sol)
/// @author cjentzsch, malteish

pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface ERC20Mintable {
    function mint(address, uint256) external;
}

struct VestingPlan {
    uint256 allocation;
    uint256 released;
    address beneficiary;
    uint64 start;
    uint64 cliff;
    uint64 duration;
    bool isMintable;
}

/**
 * @title Vesting
 * @dev This contract handles the vesting ERC20 tokens for a set of beneficiaries. Custody of multiple tokens
 * can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
 *
 * @custom:storage-size 52
 */
contract Vesting is Initializable, ERC2771ContextUpgradeable, OwnableUpgradeable {
    event ERC20Released(address indexed token, uint256 amount);
    event Commit(bytes32);
    event Revoke(bytes32);
    event VestingCreated(uint64 id);
    event ManagerAdded(address manager);
    event ManagerRemoved(address manager);

    uint64 public constant TIME_HORIZON = 20 * 365 days; // 20 years
    address public token;
    mapping(address => bool) public managers; // managers can create vestings
    mapping(uint64 => VestingPlan) public vestings;
    mapping(bytes32 => uint64) public commitments; // value = maximum end date of vesting
    uint64 public ids;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;

    constructor(address trustedForwarder) ERC2771ContextUpgradeable(trustedForwarder) {
        _disableInitializers();
    }

    function initialize(address owner, address _token) public initializer {
        require(owner != address(0), "Owner must not be zero address");
        require(_token != address(0), "Token must not be zero address");
        __Ownable_init();
        transferOwnership(owner);
        managers[owner] = true;
        token = _token;
    }

    /**
     * @dev Getter for the allocation.
     */
    function allocation(uint64 id) public view virtual returns (uint256) {
        return vestings[id].allocation;
    }

    /**
     * @dev Amount of tokens already released
     */
    function released(uint64 id) public view virtual returns (uint256) {
        return vestings[id].released;
    }

    /**
     * @dev Getter for the beneficiary address.
     */
    function beneficiary(uint64 id) public view virtual returns (address) {
        return vestings[id].beneficiary;
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start(uint64 id) public view virtual returns (uint64) {
        return vestings[id].start;
    }

    /**
     * @dev Getter for the cliff.
     */
    function cliff(uint64 id) public view virtual returns (uint64) {
        return vestings[id].cliff;
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration(uint64 id) public view virtual returns (uint64) {
        return vestings[id].duration;
    }

    /**
     * @dev Getter for type of withdraw. Minting == true mean that tokens are minted form the token contract. False means the tokens need to be held by the vesting contract directly.
     */
    function isMintable(uint64 id) public view virtual returns (bool) {
        return vestings[id].isMintable;
    }

    /**
     * @dev Getter for the amount of releasable tokens.
     */
    function releasable(uint64 id) public view virtual returns (uint256) {
        return vestedAmount(id, uint64(block.timestamp)) - released(id);
    }

    function commit(bytes32 hash) external onlyManager {
        commitments[hash] = type(uint64).max;
        emit Commit(hash);
    }

    function revoke(bytes32 hash, uint64 endVestingTime) external onlyManager {
        require(endVestingTime > block.timestamp);
        commitments[hash] = endVestingTime;
        emit Commit(hash);
    }

    function reveal(
        bytes32 hash,
        uint256 _allocation,
        address _beneficiary,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        bool _isMintable,
        bytes32 salt
    ) external returns (uint64 id) {
        require(
            hash ==
                keccak256(abi.encodePacked(_allocation, _beneficiary, _start, _cliff, _duration, _isMintable, salt)),
            "invalid-hash"
        );
        require(commitments[hash] > 0, "commitment-not-found");
        require(_start < commitments[hash]);
        uint64 durationOverride = _start + _duration < commitments[hash] ? _duration : commitments[hash] - _start; // handle case of a revoke
        commitments[hash] = 0;
        id = _createVesting(_allocation, _beneficiary, _start, _cliff, durationOverride, _isMintable);
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
        require(address(_beneficiary) != address(0), "Beneficiary must not be zero address");
        require(
            _start >= block.timestamp - TIME_HORIZON && _start <= block.timestamp + TIME_HORIZON,
            "Start must be reasonable"
        );
        require(_cliff >= 0 && _cliff <= TIME_HORIZON, "Cliff must be reasonable");
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
    }

    function stopVesting(uint64 id, uint64 endTime) public onlyManager {
        require(endTime > uint64(block.timestamp));
        require(endTime < vestings[id].start + vestings[id].duration);

        if (vestings[id].start + vestings[id].cliff > endTime) {
            delete vestings[id];
        } else {
            vestings[id].allocation = vestedAmount(id, endTime);
            vestings[id].duration = endTime - vestings[id].start;
        }
    }

    function pauseVesting(uint64 id, uint64 endTime, uint64 newStartTime) external onlyManager returns (uint64) {
        VestingPlan memory vesting = vestings[id];
        require(endTime > uint64(block.timestamp), "endTime must be in the future");
        require(endTime < vesting.start + vesting.duration, "endTime must be before vesting end");
        require(newStartTime > endTime, "newStartTime must be after endTime");

        uint256 allocationRemainder = allocation(id) - vestedAmount(id, endTime);
        uint64 timeVested = endTime - start(id);
        uint64 cliffRemainder = timeVested >= cliff(id) ? 0 : cliff(id) - timeVested;
        uint64 durationRemainder = duration(id) - timeVested;

        // stop old vesting
        stopVesting(id, endTime);

        // create new vesting
        return
            _createVesting(
                allocationRemainder,
                vesting.beneficiary,
                newStartTime,
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
    function release(uint64 id) public virtual {
        require(_msgSender() == beneficiary(id), "Only beneficiary can release tokens");
        uint256 amount = releasable(id);
        vestings[id].released += amount;
        emit ERC20Released(token, amount);
        if (isMintable(id)) {
            ERC20Mintable(token).mint(beneficiary(id), amount);
        } else {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(token), beneficiary(id), amount);
        }
    }

    // Todo: add relase(id, amount) function

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(uint64 id, uint64 timestamp) public view virtual returns (uint256) {
        VestingPlan memory vesting = vestings[id];
        if (timestamp < vesting.start + vesting.cliff) {
            return 0;
        } else if (timestamp > vesting.start + vesting.duration) {
            return vesting.allocation;
        } else {
            return (vesting.allocation * (timestamp - vesting.start)) / vesting.duration;
        }
    }

    /**
     * @dev Changes the beneficiary to a new one. Only callable by current beneficiary, or the manager one year after the vesting's plan end.
     */
    function changeBeneficiary(uint64 id, address newBeneficiary) external {
        require(
            _msgSender() == beneficiary(id) ||
                (managers[_msgSender()] && uint64(block.timestamp) > start(id) + duration(id) + 365 days)
        );
        require(newBeneficiary != address(0), "Beneficiary must not be zero address");
        vestings[id].beneficiary = newBeneficiary;
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
