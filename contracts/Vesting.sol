// SPDX-License-Identifier: MIT
// derived from OpenZeppelin Contracts (last updated v4.9.0) (finance/VestingWallet.sol)
/// @author cjentzsch, malteish
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface ERC20Mintable {
    function mint(address, uint256) external;
}

/**
 * @title Vesting
 * @dev This contract handles the vesting ERC20 tokens for a set of beneficiaries. Custody of multiple tokens
 * can be given to this contract, which will release the token to the beneficiary following a given vesting schedule.
 *
 * @custom:storage-size 52
 */
contract VestingWalletUpgradeable is Initializable, ERC2771ContextUpgradeable, OwnableUpgradeable {
    event ERC20Released(address indexed token, uint256 amount);
    event Commit(bytes32);

    struct VestingPlan {
        address token;
        uint256 allocation;
        uint256 released;
        address beneficiary;
        address manager;
        uint64 start;
        uint64 cliff;
        uint64 duration;
        bool minting;
    }

    mapping(uint64 => VestingPlan) public vestings;
    mapping(bytes32 => uint64) public commitments; // value = expiration date
    uint64 public ids;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;

    constructor(address _trustedForwarder) initializer ERC2771ContextUpgradeable(_trustedForwarder) {}

    /**
     * @dev Getter for the token address.
     */
    function token(uint64 id) public view virtual returns (address) {
        return vestings[id].token;
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
     * @dev Getter for the manager address.
     */
    function manager(uint64 id) public view virtual returns (address) {
        return vestings[id].manager;
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
    function minting(uint64 id) public view virtual returns (bool) {
        return vestings[id].minting;
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

    function revoke(bytes32 hash, uint64 endVestingTime) external onlyOwner {
        require(endVestingTime > block.timestamp);
        commitments[hash] = endVestingTime;
        emit Commit(hash);
    }

    function reveal(
        bytes32 hash,
        address _token,
        uint256 _allocation,
        address _beneficiary,
        address _manager,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        bool _minting,
        bytes32 salt
    ) external returns (uint64 id) {
        require(
            hash ==
                keccak256(
                    abi.encodePacked(
                        _token,
                        _allocation,
                        _beneficiary,
                        _manager,
                        _start,
                        _cliff,
                        _duration,
                        _minting,
                        salt
                    )
                ),
            "invalid-hash"
        );
        require(commitments[hash] > 0, "commitment-not-found");
        require(_start < commitments[hash]);
        uint64 durationOverride = _start + _duration < commitments[hash] ? _duration : commitments[hash] - _start; // handle case of a revoke
        commitments[hash] = 0;
        id = _createVesting(_token, _allocation, _beneficiary, _manager, _start, _cliff, durationOverride, _minting);
    }

    function createVesting(
        address _token,
        uint256 _allocation,
        address _beneficiary,
        address _manager,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        bool _minting
    ) external onlyOwner returns (uint64 id) {
        return _createVesting(_token, _allocation, _beneficiary, _manager, _start, _cliff, _duration, _minting);
    }

    function _createVesting(
        address _token,
        uint256 _allocation,
        address _beneficiary,
        address _manager,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration,
        bool _minting
    ) internal returns (uint64 id) {
        require(address(_token) != address(0), "AllowList must not be zero address");
        require(_allocation > 0, "Allocation must be greater than zero");
        require(address(_beneficiary) != address(0), "AllowList must not be zero address");
        require(address(_manager) != address(0), "AllowList must not be zero address");
        require(_start > block.timestamp && _start < block.timestamp + 20 * 365 days, "Start must be reasonable");
        require(_cliff > 0 && _cliff < 20 * 365 days, "Cliff must be reasonable");
        require(_duration > 0 && _duration < 20 * 365 days, "Duration must be reasonable");

        id = ids++;
        vestings[id] = VestingPlan({
            token: _token,
            allocation: _allocation,
            released: 0,
            beneficiary: _beneficiary,
            manager: _manager,
            start: _start,
            cliff: _cliff,
            duration: _duration,
            minting: _minting
        });
    }

    function stopVesting(uint64 id, uint64 endingtime) public {
        require(_msgSender() == vestings[id].manager);
        require(endingtime > uint64(block.timestamp));
        require(endingtime < vestings[id].start + vestings[id].duration);

        if (vestings[id].start + vestings[id].cliff > endingtime) {
            delete vestings[id];
        } else {
            vestings[id].duration = endingtime - vestings[id].start;
        }
    }

    function pauseVesting(uint64 id, uint64 endTime, uint64 newStartTime) external returns (uint64) {
        VestingPlan memory vesting = vestings[id];
        require(_msgSender() == vesting.manager);
        require(endTime > uint64(block.timestamp));
        require(endTime < vesting.start + vesting.duration);

        uint256 allocationRemainder = allocation(id) - vestedAmount(id, endTime);
        uint64 timeVested = endTime - start(id);
        uint64 cliffRemainder = timeVested > cliff(id) ? 0 : cliff(id) - timeVested;
        uint64 durationRemainder = duration(id) - timeVested;

        // stop old vesting
        stopVesting(id, endTime);

        // create new vesting
        return
            _createVesting(
                vesting.token,
                allocationRemainder,
                vesting.beneficiary,
                vesting.manager,
                newStartTime,
                cliffRemainder,
                durationRemainder,
                vesting.minting
            );
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {ERC20Released} event.
     */
    function release(uint64 id) public virtual {
        require(_msgSender() == beneficiary(id));
        uint256 amount = releasable(id);
        vestings[id].released += amount;
        emit ERC20Released(token(id), amount);
        if (minting(id)) {
            ERC20Mintable(token(id)).mint(beneficiary(id), amount);
        } else {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(token(id)), beneficiary(id), amount);
        }
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(uint64 id, uint64 timestamp) public view virtual returns (uint256) {
        if (timestamp < vestings[id].start + vestings[id].cliff) {
            return 0;
        } else if (timestamp > vestings[id].start + vestings[id].duration) {
            return allocation(id);
        } else {
            return (allocation(id) * (timestamp - vestings[id].start)) / vestings[id].duration;
        }
    }

    /**
     * @dev Changes the beneficiary to a new one. Only callable by current beneficiary, or the manager one year after the vesting's plan end.
     */
    function changeBeneficiary(uint64 id, address newBeneficiary) external {
        require(
            _msgSender() == beneficiary(id) ||
                (_msgSender() == manager(id) && uint64(block.timestamp) > start(id) + duration(id) + 365 days)
        );
        require(newBeneficiary != address(0), "Beneficiary must not be zero address");
        vestings[id].beneficiary = newBeneficiary;
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
