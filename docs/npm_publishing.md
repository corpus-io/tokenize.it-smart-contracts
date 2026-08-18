# Publishing to npm

The smart contracts are published to npm as a package. The package name is `@tokenize.it/contracts`. This makes it easy to use the contracts in other projects (e.g. in our web app).

Publishing is automated: pushing a version tag triggers the [release workflow](../.github/workflows/release.yml), which runs the tests, builds the artifacts from a fresh checkout, publishes to npm and creates a GitHub release with the notes from the matching `CHANGELOG.md` section.

## Releasing a new version

1. Make sure `CHANGELOG.md` has a `## [<newversion>]` section — it becomes the GitHub release notes.
2. Update the version in package.json and create the git tag:

   ```bash
   npm version <newversion>
   ```

   The version number must be a valid semver version higher than the current one.

3. Push the branch and the tag:

   ```bash
   git push --follow-tags
   ```

That's it. The release workflow takes care of the rest.

## Prereleases

Versions with an `-alpha`/`-beta` suffix (e.g. `7.2.0-beta1`) are published under the `alpha`/`beta` dist-tag and marked as prereleases on GitHub; any other prerelease suffix goes to the `next` dist-tag. Only stable versions are published as `latest`, so `npm install @tokenize.it/contracts` never picks up a preview.

## Authentication

The workflow authenticates via [npm trusted publishing](https://docs.npmjs.com/trusted-publishers) (OIDC): npm is configured to accept publishes for this package from the `release.yml` workflow of this repository. There are no npm tokens stored in the repository, and no 2FA one-time passwords are involved. Each publish carries a `--provenance` attestation linking the tarball to the exact commit and workflow run.

Changing the workflow's file name breaks the trusted-publisher registration — update the npm package settings if `release.yml` is ever renamed.

## Manual publishing (fallback)

If CI is unavailable, a package can still be published by a maintainer:

```bash
yarn test && yarn build                             # prepack no longer runs tests/build
npm pack                                            # builds the tarball (verify its contents!)
npm publish ./tokenize.it-contracts-<version>.tgz [--tag <alpha/beta>]
```

Run `npm publish` from an interactive terminal — the 2FA browser flow does not work in non-interactive shells. Note that the tarball is packed from the working directory, so untracked files inside `contracts/`, `docs/` etc. would be included: check the file list printed by `npm pack` before publishing.
