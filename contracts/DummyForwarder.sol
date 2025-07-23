// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract DummyForwarder {
    function isTrustedForwarder(address) external pure returns (bool) {
        return true;
    }
}
