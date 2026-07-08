#!/usr/bin/env bash
set -euo pipefail

suite="all"
if (($#)) && [[ "$1" != -* ]]; then
	suite="$1"
	shift
fi

while (($#)); do
	case "$1" in
	--artifacts)
		export UNIFIED_REVIEW_E2E_ARTIFACTS=1
		;;
	-h | --help)
		suite="help"
		;;
	*)
		echo "Unknown option: $1" >&2
		exit 2
		;;
	esac
	shift
done

run_suite() {
	bash "$0" "$1"
}

run_tui() {
	nix develop -c npm exec -- tui-test "$1"
}

case "$suite" in
all)
	run_suite typecheck
	run_suite pi-unit
	run_suite pi-bridge
	run_suite flake
	run_suite tui
	;;
typecheck)
	npm exec -- tsc --noEmit
	;;
lua)
	nix run .
	;;
lua-plugin)
	nix run .#test-plugin
	;;
lua-components)
	nix run .#test-components
	;;
pi-unit)
	node --experimental-strip-types --test tests/extensions/unit/*.test.ts
	;;
pi-bridge)
	nix develop -c node --experimental-strip-types --test tests/extensions/integration/*.test.ts
	;;
flake)
	nix flake check --print-build-logs
	;;
tui)
	run_suite tui-plugin
	run_suite tui-components
	;;
tui-plugin)
	run_tui "tests/e2e/"
	;;
tui-components)
	run_tui "tests/storybook/"
	;;
help)
	cat <<'EOF'
Usage: scripts/test.sh [suite] [--artifacts]

Suites:
  all             Full validation across every test suite
  typecheck       TypeScript typecheck
  lua             All Lua/plenary tests
  lua-plugin      Lua plugin tests, excluding component specs
  lua-components  Lua component specs
  pi-unit         Pi extension unit tests
  pi-bridge       Pi/Neovim bridge integration test
  flake           Nix flake checks
  tui             Plugin and component TUI tests
  tui-plugin      Plugin TUI tests
  tui-components  Component/storybook TUI tests
EOF
	;;
*)
	echo "Unknown test suite: $suite" >&2
	echo "Run scripts/test.sh --help for available suites." >&2
	exit 2
	;;
esac
