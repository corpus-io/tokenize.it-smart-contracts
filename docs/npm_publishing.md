# Publishing to npm

The smart contracts are published to npm as a package. The package name is `@tokenizeit/contracts`. This makes it easy to use the contracts in other projects (e.g. in our web app).

Currently, no automated publishing is set up. Publishing is done manually. To publish a new version, follow these steps:

1. Update version in package.json and create git tag:

   ```bash
   npm version <newversion>
   ```

   The version number must be a valid semver version. The version number must be higher than the current version number.

2. Build the contracts:

   ```bash
   yarn build
   ```

3. Test without publishing:

   ```bash
   npm publish [--tag <alpha/beta>] --dry-run
   ```

4. Check if all necessary files are contained and no secrets are leaked.
5. If everything is fine, publish:
   ```bash
   npm publish [--tag <alpha/beta>]
   ```

Sadly, `yarn publish` did not work at the time of writing. It appeared to have trouble with the 2FA.
