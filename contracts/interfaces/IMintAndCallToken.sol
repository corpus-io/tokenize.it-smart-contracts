// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../../contracts/interfaces/ERC1363.sol";

/*
    interface to test the mint and call feature
*/
interface IMintAndCallToken is IERC20 {
    function decimals() external view returns (uint8);

    function mint(address _to, uint256 _amount) external;

    function getController() external view returns (address);

    function mintAndCall(address _to, uint256 _amount, bytes memory _data) external;

    function mintTo(address to, uint256 amount) external returns (bool ok);

    function setMaxMintAllowance(uint256 amount) external;

    function getMaxMintAllowance() external view returns (uint256);

    function setMintAllowance(address account, uint256 amount) external;

    function getMintAllowance(address) external view returns (uint256);
}

interface IMintAndCallTokenController is IERC20 {
    function decimals() external view returns (uint8);

    function mint(address _to, uint256 _amount) external;

    function mintAndCall(address _to, uint256 _amount, bytes memory _data) external;

    function mintTo(address to, uint256 amount) external returns (bool ok);

    function setMaxMintAllowance(uint256 amount) external;

    function getMaxMintAllowance() external view returns (uint256);

    function setMintAllowance(address account, uint256 amount) external;

    function getMintAllowance(address) external view returns (uint256);

    function addSystemAccount(address account) external;

    function addAdminAccount(address account) external;
}
