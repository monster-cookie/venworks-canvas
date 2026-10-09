# Repository and toolchain

This is the context template for `Venworks Canvas`. Unconfigured external services affect only work that needs them. These are repository-owned settings, with no global policy discovery or override system.

## Repository and Tool Chain

| Setting | Value |
| --- | --- |
| Project name | `Venworks Canvas` |
| Repository URL | `https://github.com/monster-cookie/venworks-canvas` |
| Target game | `Starfield` |

Use the current checkout as the repository path. Verify its remote against the configured repository before publishing. Keep machine-specific paths and secrets in protected local configuration, outside the repository.

The supplied pipeline currently targets Starfield. Other BGS games require appropriate compiler, runtime, and packaging configuration. [README.md](../../README.md#maintainer-and-contributor-workflow) is the maintainer and contributor guide; [Tools/sharedConfig.ps1](../../Tools/sharedConfig.ps1) owns variant and build configuration and loads the local `.env`. Inspect the selected script and configuration for actual parameters, prerequisites, and side effects before execution.
