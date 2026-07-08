# AGENTS.md

## Commands

- Full validation: `scripts/test.sh all`
- Individual suites: `scripts/test.sh <typecheck|lua|lua-plugin|lua-components|pi-unit|pi-bridge|flake|tui|tui-plugin|tui-components>`
- TUI artifacts: `scripts/test.sh tui --artifacts`
- Install Node dependencies before TypeScript or E2E tests: `npm ci`

## Boundaries

- Keep pi/Neovim handoffs on the versioned JSON artifact contracts; do not couple extensions to Neovim UI internals.
