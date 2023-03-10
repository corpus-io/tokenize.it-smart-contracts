# Publishing to npm

The smart contracts are published to npm as a package. The package name is `@tokenizeit/contracts`. This makes it easy to use the contracts in other projects.

Currently, no automated publishing is set up. Publishing is done manually. To publish a new version, follow these steps:

1. First test without publishing:

   ```bash
   npm publish --access public --dry-run
   ```

2. Check if all necessary files are contained and no secrets are leaked.
3. If everything is fine, publish:
   ```bash
   npm publish --access public
   ```

Sadly, `yarn publish` did not work at the time of writing. It appeared to have trouble with the 2FA.
