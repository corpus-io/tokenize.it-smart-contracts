// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/interfaces/IFeeSettings.sol";

contract IFeeSettingsTest is Test {
    function testManuallyVerifyInterfaceID() public {
        // see https://medium.com/@chiqing/ethereum-standard-erc165-explained-63b54ca0d273
        bytes4 expected = getFunctionSelector("tokenFee(uint256)");
        expected = expected ^ getFunctionSelector("publicFundraisingFee(uint256)");
        expected = expected ^ getFunctionSelector("privateOfferFee(uint256)");
        expected = expected ^ getFunctionSelector("feeCollector()");
        expected = expected ^ getFunctionSelector("owner()");
        expected = expected ^ getFunctionSelector("supportsInterface(bytes4)");
        bytes4 actual = type(IFeeSettingsV1).interfaceId;

        assertEq(actual, expected, "interface ID mismatch");
    }

    function getFunctionSelector(string memory signature) public pure returns (bytes4) {
        return bytes4(keccak256(bytes(signature)));
    }
}
