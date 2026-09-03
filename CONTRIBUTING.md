# Contributing to Rokumio

Thanks for helping improve Rokumio client. The project is maintained through
forks and pull requests; contributors do not need write access to the main
repository.

## Before opening a pull request

1. Fork the repository and create a focused branch.
2. Run `npm install` and `npm test`.
3. Keep changes scoped to the behavior being fixed or added.
4. Do not include credentials, account keys, private-network addresses, local
   machine paths, generated build output, or unlicensed screenshots/artwork.
5. Describe Roku model, resolution, and developer-mode testing when relevant.

Pull requests should explain the user-visible change, include tests for new
logic where practical, and call out any Roku hardware behavior that could not
be tested locally.

## Code and design notes

Rokumio client is an independent Roku client. Do not copy Stremio web assets,
logos, screenshots, or source code into a contribution unless you have the
right to redistribute them. Use neutral descriptions and original assets in
tests and documentation.

By submitting a contribution, you agree that it may be distributed under the
project license.

### Naming and Upstream References

Rokumio is based on Stroku Native. When modifying or extending the
codebase, distinguish between inherited upstream code and Rokumio-specific
code where practical.

- Keep `Stroku` references when they identify original upstream
  functionality, attribution, tests, or implementation details.
- Use `Rokumio` for new project-specific functionality, branding,
  identifiers, and test fixtures introduced or adapted for Rokumio.
- Do not remove or alter copyright notices, license information, or
  required attribution from the original Stroku Native project.
- Avoid unnecessary renaming of inherited internal identifiers when doing
  so would provide no functional benefit.
