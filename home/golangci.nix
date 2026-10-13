# The default golangci-lint config for Go repos of this user's own, shared by
# ./dev.nix (golangci-init, on PATH) and ./claude-code.nix (claude-go-hook).
#
# It is not installed as ~/.golangci.yml, where golangci-lint would pick it up
# for any repo without a config of its own. In Go, no config is the norm: it
# means "gofmt and nothing more", and a stranger's repo rewrapped to 88 columns
# is a diff its maintainers would ask to have reverted. Instead each own repo
# carries a committed copy, written by golangci-init, so its own CI can enforce
# it too; and claude-go-hook applies it to an own repo that has no copy yet,
# going by the module path's prefix (`owner` below).
{ pkgs }:
rec {
  owner = "github.com/serverplumber/";

  # Go's equivalent of ruff's defaults plus black's 88 columns.
  #
  # The formatters are the Python habits: golines wraps long code the way
  # black does (always one argument per line, though, with no black-style
  # "all on one indented line" step first), gofumpt is gofmt with black's
  # strictness, and gci sorts imports into isort's std / third-party / own
  # sections. lll catches what golines cannot break: strings and comments.
  # Both count a tab as 4 columns, as Helix draws it; lll's default of 1
  # would let tab-indented code run well past 88 on screen.
  #
  # The exclusion presets are what golangci-lint v1 applied by default and
  # v2 made opt-in. Without them errcheck flags every unchecked fmt.Fprintf
  # and Close.
  config = (pkgs.formats.yaml { }).generate "golangci.yml" {
    version = "2";
    linters = {
      default = "standard";
      enable = [ "lll" ];
      settings.lll = {
        line-length = 88;
        tab-width = 4;
      };
      exclusions.presets = [
        "std-error-handling"
        "common-false-positives"
      ];
    };
    formatters = {
      enable = [
        "gci"
        "gofumpt"
        "golines"
      ];
      settings = {
        gci.sections = [
          "standard"
          "default"
          "localmodule"
        ];
        golines = {
          max-len = 88;
          tab-len = 4;
        };
      };
    };
  };

  # `golangci-init [DIR]`: write the default into a repo as .golangci.yml.
  # Never overwrites. A copy that differs is shown as a diff and left alone,
  # since a repo may have tuned its copy on purpose; rerunning is therefore
  # also the drift check, exiting 1 when the copy and the default disagree.
  init = pkgs.writeShellApplication {
    name = "golangci-init";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
    ];
    text = ''
      dir=''${1:-.}
      [ -e "$dir/go.mod" ] || { echo "golangci-init: no go.mod in $dir" >&2; exit 1; }
      for f in "$dir"/.golangci.yaml "$dir"/.golangci.toml "$dir"/.golangci.json; do
        if [ -e "$f" ]; then
          echo "golangci-init: $f already configures this repo" >&2
          exit 1
        fi
      done
      target=$dir/.golangci.yml
      if [ ! -e "$target" ]; then
        install -m 644 ${config} "$target"
        echo "wrote $target"
      elif cmp -s ${config} "$target"; then
        echo "$target matches the default"
      else
        diff -u --label "$target" --label default "$target" ${config} || true
        echo "golangci-init: $target differs from the default; left alone" >&2
        exit 1
      fi
    '';
  };
}
