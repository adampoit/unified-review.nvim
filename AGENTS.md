# AGENTS.md

## Commands

- Lua/plenary tests: `nix run .`
  - Subsets: `nix run .#test-plugin` or `nix run .#test-components`
- TUI E2E tests: `npm ci && npm run test:e2e`
  - Subsets: `npm run test:e2e:plugin` or `npm run test:e2e:components`
- Flake validation: `nix flake check`
