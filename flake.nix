{
  description = "unified-review.nvim plugin tests";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        plugin-src = ./.;

        nvim-with-deps = pkgs.neovim.override {
          configure = {
            customRC = ''
              lua << EOF
              vim.opt.runtimepath:prepend("${plugin-src}")
              EOF
            '';
            packages.test-deps = {
              start = with pkgs.vimPlugins; [
                plenary-nvim
                codediff-nvim
              ];
            };
          };
        };

        plenary-directory-command = path: ''
          ${nvim-with-deps}/bin/nvim --headless -n -u ${plugin-src}/tests/minimal_init.lua \
            -c "PlenaryBustedDirectory ${path} { minimal_init = '${plugin-src}/tests/minimal_init.lua' }" \
            -c "qa!"
        '';

        test-command = plenary-directory-command "${plugin-src}/tests";
        component-test-command = plenary-directory-command "${plugin-src}/tests/components";
        plugin-test-command = ''
          set -euo pipefail
          while IFS= read -r spec; do
            ${nvim-with-deps}/bin/nvim --headless -n -u ${plugin-src}/tests/minimal_init.lua \
              -c "lua require('plenary.busted').run('$spec')" \
              -c "qa!"
          done < <(${pkgs.findutils}/bin/find ${plugin-src}/tests -name '*_spec.lua' ! -path '${plugin-src}/tests/components/*' | ${pkgs.coreutils}/bin/sort)
        '';

        with-test-env = command: ''
          TEST_HOME="$(mktemp -d)"
          export HOME="$TEST_HOME"
          export XDG_CACHE_HOME="$HOME/.cache"
          export XDG_CONFIG_HOME="$HOME/.config"
          export XDG_DATA_HOME="$HOME/.local/share"
          export XDG_STATE_HOME="$HOME/.local/state"
          export PLENARY_PATH="${pkgs.vimPlugins.plenary-nvim}"
          export CODEDIFF_PATH="${pkgs.vimPlugins.codediff-nvim}"
          export PATH="${pkgs.lib.makeBinPath [pkgs.git pkgs.jujutsu pkgs.nodejs_22]}:$PATH"
          mkdir -p "$HOME"
          ${command}
        '';

        test-runner = pkgs.writeShellScript "unified-review-tests" (with-test-env test-command);
        plugin-test-runner = pkgs.writeShellScript "unified-review-plugin-tests" (with-test-env plugin-test-command);
        component-test-runner = pkgs.writeShellScript "unified-review-component-tests" (with-test-env component-test-command);
        test-nvim = pkgs.writeShellScript "unified-review-test-nvim" (with-test-env ''
          exec ${nvim-with-deps}/bin/nvim -n -u ${plugin-src}/tests/minimal_init.lua \
            -c "lua require('unified_review').setup({})" "$@"
        '');
      in {
        packages.default = nvim-with-deps;

        apps.default = {
          type = "app";
          program = toString test-runner;
        };

        apps.test-plugin = {
          type = "app";
          program = toString plugin-test-runner;
        };

        apps.test-components = {
          type = "app";
          program = toString component-test-runner;
        };

        apps.test-nvim = {
          type = "app";
          program = toString test-nvim;
        };

        checks.default = pkgs.runCommand "unified-review-tests" {} ''
          ${with-test-env test-command}
          touch $out
        '';

        checks.plugin = pkgs.runCommand "unified-review-plugin-tests" {} ''
          ${with-test-env plugin-test-command}
          touch $out
        '';

        checks.components = pkgs.runCommand "unified-review-component-tests" {} ''
          ${with-test-env component-test-command}
          touch $out
        '';

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.git
            pkgs.jujutsu
            pkgs.nodejs_22
          ];
          PLENARY_PATH = "${pkgs.vimPlugins.plenary-nvim}";
          CODEDIFF_PATH = "${pkgs.vimPlugins.codediff-nvim}";
          NVIM_BIN = "${nvim-with-deps}/bin/nvim";
          shellHook = ''
            echo "unified-review test shell"
            echo "  All tests:   scripts/test.sh all"
            echo "  Test suites: scripts/test.sh --help"
            echo "  Test Neovim: nix run .#test-nvim"
            echo "  Single spec: nix run .#test-nvim -- --headless +'lua require(\"plenary.busted\").run(\"tests/ui/thread_panel_spec.lua\")'"
          '';
        };
      }
    );
}
