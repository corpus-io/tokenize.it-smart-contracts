// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

/**
    @notice ERC1363 interface, see https://eips.ethereum.org/EIPS/eip-1363
 */
interface ERC1363Receiver {
    function onTransferReceived(
        address operator,
        address from,
        uint256 value,
        bytes memory data
    ) external returns (bytes4);
}
