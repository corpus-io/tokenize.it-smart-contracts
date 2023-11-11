// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (finance/VestingWallet.sol)
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface MintLike {
    function mint(address, uint256) external;
}

/**
 * @title VestingWallet
 * @dev This contract handles the vesting of Eth and ERC20 tokens for a given beneficiary. Custody of multiple tokens
 * can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
 * The vesting schedule is customizable through the {vestedAmount} function.
 *
 * Any token transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
 * Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
 * be immediately releasable.
 *
 * @custom:storage-size 52
 */
contract VestingWalletUpgradeable is Initializable, ERC2771ContextUpgradeable, OwnableUpgradeable {
    event ERC20Released(address indexed token, uint256 amount);
    event Commit(bytes32);

    struct VestingPlan {
            address _token;
            uint256 _allocation;
            uint256 _released;
            address _beneficiary;
            address _manager;
            uint64 _start;
            uint64 _cliff;
            uint64 _duration;
            bool _minting;
        }

    mapping (uint64 => VestingPlan) public vestings;
    mapping (bytes32 => uint64) public commitments; // value = expiration date
    uint64 ids;

    constructor(address _trustedForwarder) initializer ERC2771ContextUpgradeable(_trustedForwarder) {}

    /**
     * @dev Getter for the token address.
     */
    function token(uint64 id) public view virtual returns (address) {
        return vestings[id]._token;
    }

    /**
     * @dev Getter for the allocation.
     */
    function allocation(uint64 id) public view virtual returns (uint256) {
        return vestings[id]._allocation;
    }

    /**
     * @dev Amount of tokens already released
     */
    function released(uint64 id) public view virtual returns (uint256) {
        return vestings[id]._released;
    }

    /**
     * @dev Getter for the beneficiary address.
     */
    function beneficiary(uint64 id) public view virtual returns (address) {
        return vestings[id]._beneficiary;
    }

    /**
     * @dev Getter for the manager address.
     */
    function manager(uint64 id) public view virtual returns (address) {
        return vestings[id]._manager;
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start(uint64 id) public view virtual returns (uint64) {
        return vestings[id]._start;
    }

   /**
     * @dev Getter for the cliff.
     */
    function cliff(uint64 id) public view virtual returns (uint64) {
        return vestings[id]._cliff;
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration(uint64 id) public view virtual returns (uint64) {
        return vestings[id]._duration;
    }

    /**
     * @dev Amount of tokens already released
     */
    function minting(uint64 id) public view virtual returns (bool) {
        return vestings[id]._minting;
    }

    /**
     * @dev Getter for the amount of releasable tokens.
     */
    function releasable(uint64 id) public view virtual returns (uint256) {
        return vestedAmount(id, uint64(block.timestamp)) - released(id);
    }

    function commit(bytes32 hash) external onlyOwner {
        commitments[hash] = type(uint64).max;
        emit Commit(hash);
    }

    function revoke(bytes32 hash) external onlyOwner {
        commitments[hash] = uint64(block.timestamp);
        emit Commit(hash);
    }

    function reveal(bytes32 hash, address token, uint256 allocation, address beneficiary, address manager, uint64 start, uint64 cliff, uint64 duration, bool minting, bytes32 salt) external returns(uint64 id) {
        require(hash == keccak256(abi.encodePacked(token, allocation, beneficiary, manager, start, cliff, duration, minting, salt)), "invalid-hash");
        require(commitments[hash] > 0, "commitment-not-found");
        uint64 durationOverride = duration;
        if (commitments[hash] <= block.timestamp) { // in case of a revoke
            durationOverride = commitments[hash] - start;
        }
        commitments[hash] = 0;
        id = _createVesting(token, allocation, beneficiary, manager, start, cliff, durationOverride, minting);
    }

    function createVesting(address token, uint256 allocation, address beneficiary, address manager, uint64 start, uint64 cliff, uint64 duration, bool minting) external onlyOwner returns(uint64 id) {
        return _createVesting(token, allocation, beneficiary, manager, start, cliff, duration, minting);
    }

    function _createVesting(address token, uint256 allocation, address beneficiary, address manager, uint64 start, uint64 cliff, uint64 duration, bool minting) internal returns(uint64 id) {
        require(address(token) != address(0), "AllowList must not be zero address");
        require(allocation > 0, "Allocation must be greater than zero");
        require(address(beneficiary) != address(0), "AllowList must not be zero address");
        require(address(manager) != address(0), "AllowList must not be zero address");
        require(start > block.timestamp && start < block.timestamp + 20 * 365 days, "Start must be reasonable");
        require(cliff > 0 && cliff < 20 * 365 days, "Cliff must be reasonable");
        require(duration > 0 && duration < 20 * 365 days, "Duration must be reasonable");

        id = ++ids;
        vestings[id] = VestingPlan({
            _token: token,
            _allocation: allocation,
            _released: 0,
            _beneficiary: beneficiary,
            _manager: manager,
            _start: start,
            _cliff: cliff,
            _duration: duration,
            _minting: minting
        });
    }

    function stopVesting(uint64 id, uint64 endingtime) public {
        require(_msgSender() == vestings[id]._manager);
        require(endingtime > uint64(block.timestamp));
        require(endingtime < vestings[id]._start + vestings[id]._duration);

        if (vestings[id]._start + vestings[id]._cliff > endingtime) {
            delete vestings[id];
        }
        else {
            vestings[id]._duration = endingtime - vestings[id]._start;
        }
    }

    function pauseVesting(uint64 id, uint64 endingTime, uint64 newStartTime) external returns(uint64 returnId){
        require(_msgSender() == vestings[id]._manager);
        require(endingTime > uint64(block.timestamp));
        require(endingTime < vestings[id]._start + vestings[id]._duration);

        uint256 allocationRemainder = allocation(id) - vestedAmount(id, endingTime);
        require(allocationRemainder > 0); // not necessary
        uint64 timevested = endingTime - start(id);
        uint64 cliffRemainder = timevested > cliff(id) ? 0 : cliff(id) - timevested;
        uint64 durationRemainder = duration(id) - timevested;
        returnId = _createVesting(token(id), allocationRemainder, beneficiary(id), manager(id), newStartTime, cliffRemainder, durationRemainder, minting(id));
        stopVesting(id, endingTime);
    }


    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {ERC20Released} event.
     */
    function release(uint64 id) public virtual {
        require(_msgSender() == beneficiary(id));
        uint256 amount = releasable(id);
        vestings[id]._released += amount;
        emit ERC20Released(token(id), amount);
        if (minting(id)) {
            MintLike(token(id)).mint(beneficiary(id), amount);
        }
        else {SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(token(id)), beneficiary(id), amount);}
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(uint64 id, uint64 timestamp) public view virtual returns (uint256) {
        if (timestamp < vestings[id]._start + vestings[id]._cliff) {
            return 0;
        } else if (timestamp > vestings[id]._start + vestings[id]._duration) {
            return allocation(id);
        } else {
            return (allocation(id) * (timestamp - vestings[id]._start)) / vestings[id]._duration;
        }
    }

    /**
    * @dev Changes the beneficiary to a new one. Only callable by current beneficiary, or the manager one year after the vesting's plan end.
    */
    function changeBeneficiary(uint64 id, address newBeneficiary) external {
        require(_msgSender() == beneficiary(id) || (_msgSender() == manager(id) && uint64(block.timestamp) > start(id) + cliff(id) + 365 days));
        require(newBeneficiary != address(0), "Beneficiary must not be zero address");
        vestings[id]._beneficiary = newBeneficiary;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;

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

