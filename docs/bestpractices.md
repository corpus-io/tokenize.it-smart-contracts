# Best Practices

## Solidity

### License & Compiler Version

- License: `AGPL-3.0-only`
- Solidity version: `pragma solidity 0.8.23;` — pinned, no `^` or `~`

### Naming

- Constants: `ALL_CAPS_WITH_UNDERSCORES` (e.g., `MAX_TOKEN_NUMERATOR`, `MINTALLOWER_ROLE`)
- Events: PascalCase (e.g., `RequirementsChanged`)
- Public state variables: camelCase (e.g., `allowList`, `mintingAllowance`)
- Private/internal state variables: `_prefixedCamelCase`
- Function parameters: `_prefixedCamelCase`
- Local variables: camelCase
- No shorthand or abbreviated variable names — use full descriptive names (e.g., `leadInvestor`, not `li`; `crowdinvestingContract`, not `ci`)

### Code Style

- Line width: 120 characters (configured in prettier)
- Double quotes in Solidity strings
- Trailing commas in multi-line structures

### Natspec

- All public contracts, functions, events, and errors must have natspec
- Use `@notice` for high-level descriptions, `@dev` for implementation notes, `@param` for parameters
- Include security considerations and invariants in contract-level `@dev` comments

### Custom Errors

- Use custom errors instead of string reverts.
- Use the `require(condition, CustomError(args))` syntax (available since Solidity 0.8.26 via-ir / 0.8.27 legacy pipeline).
- **Generic errors** (e.g. `ZeroAddress`, `ZeroAmount`) are declared as top-level file-level errors in `contracts/common/Errors.sol` and imported where needed.
- **Contract-specific errors** are declared inside the contract that uses them.
- Do not declare errors in interfaces.
- In tests, match custom errors by selector; for errors with parameters also encode the argument values:
  ```solidity
  // parameter-less error
  vm.expectRevert(ZeroAddress.selector);
  vm.expectRevert(MyContract.NoLeadInvestors.selector);
  // error with parameters — verify the argument value too
  vm.expectRevert(abi.encodeWithSelector(MyContract.UnknownFeeType.selector, feeTypeId));
  ```

### Architecture

- Use structs to avoid "stack too deep" errors in functions with many parameters
- Immutable trusted forwarder: set in constructor, never changed afterwards
- Two-step ownership transfers (`Ownable2Step`) for all ownable contracts
- Use `AccessControlUpgradeable` for role-based access; do not mix with `Ownable` in the same contract
- Document all invariants in `docs/invariants.md`

### Deployment

- All contracts deployed via factory contracts (clone or proxy pattern)
- Use salt-based deployment for deterministic addresses
- Never hardcode addresses in contracts — inject via constructor or initializer

---

## Testing

### Test File Naming

- Test helpers and mocks go in `/test/resources/`

### Test Function Naming

- Prefix with `test`: `testOwner()`, `testNotOwnerCannotSet()`
- Names must describe what is being tested, not just the function name

### Specificity

- **No empty `expectRevert` calls.** Always specify the expected error:

  ```solidity
  // bad
  vm.expectRevert();
  contract.doSomething();

  // good
  vm.expectRevert(abi.encodeWithSelector(MyContract.Unauthorized.selector, caller));
  contract.doSomething();
  ```

  Exception: an empty `expectRevert` is acceptable only when immediately followed by a corrected call that succeeds, demonstrating what causes the revert.

- **Verify state changes**, not just that a call succeeds. Assert the expected values after each action.

### Test Structure

- Use `setUp()` to initialize logic contracts, clone factories, and clone instances
- Use `vm.prank(address)` for single-call sender impersonation
- Use `vm.assume()` for property-based test assumptions (fuzz tests)
- Use `vm.expectEmit()` before the call that should emit the event
- Exclude mainnet-fork tests from local runs with `--no-match-test Mainnet`

### Test Helpers

- Shared setup logic belongs in base contracts in `/test/resources/` (e.g., `CoinvestedPositionTestBase.sol`)
- Mock tokens go in `/test/resources/` (e.g., `FakePaymentToken.sol`)

---

## Build

- Always compile with the `fastDev` profile during development:
  ```bash
  export FOUNDRY_PROFILE=fastDev
  forge build
  ```
- Default profile uses `via-ir = true` (slow but required for production builds)
- `bytecode_hash = "none"` — keep this setting to ensure reproducible, deterministic bytecode (compiler metadata would otherwise vary by local file paths)
