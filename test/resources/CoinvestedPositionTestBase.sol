// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../../lib/forge-std/src/Test.sol";
import "../../contracts/factories/TokenProxyFactory.sol";
import "../../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../../contracts/CoinvestedPosition.sol";
import "../../contracts/GlobalTokenExitRegistry.sol";
import "../../contracts/FeeSettings.sol";
import "./FakePaymentToken.sol";
import "./CloneCreators.sol";

abstract contract CoinvestedPositionTestBase is Test {
    // ── Well-known addresses ──────────────────────────────────────────────────
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant LEAD_A = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant TRUSTED_FORWARDER = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;
    address public constant TOKEN_RECEIVER = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;

    // ── Test constants ────────────────────────────────────────────────────────
    // 10% of uint64.max (floor)
    uint64 public constant CARRY_10PCT = type(uint64).max / 10;

    // ── Shared state ──────────────────────────────────────────────────────────
    AllowList allowList;
    IFeeSettingsV2 feeSettings;
    Token token;
    TokenProxyFactory tokenFactory;
    FakePaymentToken eurc; // 6 decimals

    // The clone deployed for most tests
    CoinvestedPosition coinvestedPosition;
    GlobalTokenExitRegistry tokenExitRegistry;

    // ── Internal helpers ──────────────────────────────────────────────────────

    /// Mint tokens to coinvestedPosition then set price and unpause
    function _setupBuy(uint256 tokenAmount, uint256 tokenPrice) internal {
        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), tokenAmount);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(tokenPrice);
        vm.prank(OWNER);
        coinvestedPosition.unpause();
    }

    /// Drain pending pull-payout credits in `_currency` for every lead investor and the receiver
    /// of `position`. Used after buy/claimDistribution/claimExit so legacy push-style balance
    /// assertions continue to work.
    function _drainCredits(CoinvestedPosition position, IERC20 _currency) internal {
        uint256 leadCount = position.getLeadInvestorsCount();
        for (uint256 i = 0; i < leadCount; i++) {
            uint256 credit = position.leadInvestorCredit(i, _currency);
            if (credit != 0) {
                (address account, ) = position.leadInvestors(i);
                vm.prank(account);
                position.withdrawAsLeadInvestor(i, _currency);
            }
        }
        if (position.receiverCredit(_currency) != 0) {
            vm.prank(position.receiver());
            position.withdrawAsReceiver(_currency);
        }
    }
}
