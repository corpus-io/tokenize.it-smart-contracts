// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

interface IFeeSettingsV1 {
    function tokenFee(uint256) external view returns (uint256);

    function continuousFundraisingFee(uint256) external view returns (uint256);

    function personalInviteFee(uint256) external view returns (uint256);

    function feeCollector() external view returns (address);

    function owner() external view returns (address);

    function supportsInterface(bytes4) external view returns (bool); //because we inherit from ERC165
}

struct Fees {
    uint32 tokenFeeNumerator;
    uint32 tokenFeeDenominator;
    uint32 continuousFundraisingFeeNumerator;
    uint32 continuousFundraisingFeeDenominator;
    uint32 personalInviteFeeNumerator;
    uint32 personalInviteFeeDenominator;
    uint64 time;
}
