{ pkgs, lib, config, ... }:

let
  # The headless package for a channel. Lazy: only forced when withGame is true
  # (the fct-paths case interpolates it conditionally), so a busted-only shell
  # never downloads the ~150 MB game binary.
  headlessFor = channel:
    if channel == "experimental"
    then pkgs.factorio-headless-experimental
    else pkgs.factorio-headless;

  # "bin data" pair for the headless server of a channel.
  headlessPaths = channel:
    "${headlessFor channel}/bin/factorio ${headlessFor channel}/share/factorio/data";
in
{
  options.withGame = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Pull the free headless server and enable the load-smoke / bench commands. Disable for a busted-only lightweight shell.";
  };

  options.withClient = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Build the full (unfree) game client for `play`. Requires FACTORIO_USERNAME / FACTORIO_TOKEN at build time.";
  };

  config = {
    # mkDefault so an exported FACTORIO_CHANNEL wins. Client paths (and the
    # unfree client build) only land in env when withClient is true.
    env = {
      FACTORIO_CHANNEL = lib.mkDefault "experimental";
      HAS_GAME = if config.withGame then "1" else "0";
      # Make `require("foo")` find ./lib/foo.lua from any Lua invocation
      # (busted's .busted lpath isn't honoured by this nix build, so set it here).
      # ';;' expands to the compiled-in default so busted's own rocks still load.
      LUA_PATH = "./lib/?.lua;./?.lua;;";
    } // (lib.optionalAttrs config.withClient {
      FACTORIO_CLIENT_EXPERIMENTAL = "${pkgs.factorio-experimental}/bin/factorio";
      FACTORIO_CLIENT_STABLE = "${pkgs.factorio}/bin/factorio";
    });

    packages = [
      pkgs.lua52Packages.busted # busted pinned to Lua 5.2 (the game's Lua)
      pkgs.lua5_2
      pkgs.luaPackages.luacheck
      pkgs.stylua
      pkgs.lua-language-server
      pkgs.jq
      pkgs.git
    ];

    # --- internal helper: channel resolution, headless paths, sandbox setup ---
    scripts.fct.exec = ''
      cmd="''${1:-}"; shift || true
      case "$cmd" in
        resolve)
          a="''${1:-}"
          if [ -n "$a" ]; then c="$a"
          elif [ -n "''${FACTORIO_CHANNEL:-}" ]; then c="$FACTORIO_CHANNEL"
          else c="experimental"; fi
          case "$c" in
            stable|experimental) echo "$c" ;;
            *) echo "unknown channel '$c' (expected: stable | experimental)" >&2; exit 1 ;;
          esac
          ;;
        paths)
          case "$1" in
            experimental) echo "${if config.withGame then headlessPaths "experimental" else "GAME_DISABLED"}" ;;
            stable)       echo "${if config.withGame then headlessPaths "stable" else "GAME_DISABLED"}" ;;
            *) echo "unknown channel '$1' (expected: stable | experimental)" >&2; exit 1 ;;
          esac
          ;;
        sandbox)
          # $1=channel  $2=read-data dir for the active binary
          data="$2"
          name=$(jq -r .name info.json); ver=$(jq -r .version info.json)
          mkdir -p .factorio/mods .factorio/saves
          cat > .factorio/config.ini <<INI
[path]
read-data=$data
write-data=$PWD/.factorio
INI
          [ -f .factorio/mods/mod-list.json ] || \
            jq -nc --arg n "$name" '{mods:[{name:"base",enabled:true},{name:$n,enabled:true}]}' > .factorio/mods/mod-list.json
          ln -sfn "$PWD" ".factorio/mods/''${name}_''${ver}"
          ;;
        *) echo "fct: unknown subcommand '$cmd'" >&2; exit 1 ;;
      esac
    '';

    # --- test: busted (channel-agnostic) + headless load-smoke on the channel ---
    scripts.modtest.exec = ''
      chan=$(fct resolve "''${1:-}")
      echo "== busted (lua 5.2) =="
      busted
      if [ "$HAS_GAME" = "1" ]; then
        echo "== load-smoke ($chan) =="
        set -- $(fct paths "$chan"); bin="$1"; data="$2"
        fct sandbox "$chan" "$data"
        save=.factorio/saves/smoke.zip
        "$bin" --config .factorio/config.ini --mod-directory .factorio/mods \
               --create "$save" --map-gen-seed 1
        "$bin" --config .factorio/config.ini --mod-directory .factorio/mods \
               --benchmark "$save" --benchmark-ticks 1
      else
        echo "== load-smoke skipped (withGame=false) =="
      fi
    '';

    scripts.bench.exec = ''
      chan=$(fct resolve "''${1:-}")
      [ "$HAS_GAME" = "1" ] || { echo "bench requires withGame=true" >&2; exit 1; }
      ticks="''${BENCH_TICKS:-1000}"
      save="''${BENCH_SAVE:-}"
      set -- $(fct paths "$chan"); bin="$1"; data="$2"
      fct sandbox "$chan" "$data"
      if [ -z "$save" ]; then
        save=.factorio/saves/bench.zip
        echo "== creating fixed-seed save ($chan) =="
        "$bin" --config .factorio/config.ini --mod-directory .factorio/mods \
               --create "$save" --map-gen-seed 1
      fi
      "$bin" --config .factorio/config.ini --mod-directory .factorio/mods \
             --benchmark "$save" --benchmark-ticks "$ticks"
    '';

    scripts.play.exec = ''
      chan=$(fct resolve "''${1:-}")
      var="FACTORIO_CLIENT_''${chan^^}"
      client="''${!var:-}"
      if [ -z "$client" ] || [ ! -x "$client" ]; then
        echo "Full Factorio client is opt-in (needs your account token at build time)." >&2
        echo "Enable: set withClient = true; in devenv.nix, export FACTORIO_USERNAME and FACTORIO_TOKEN, then 'direnv allow'." >&2
        exit 1
      fi
      data="$(dirname "$(dirname "$client")")/share/factorio/data"
      fct sandbox "$chan" "$data"
      exec "$client" --config .factorio/config.ini --mod-directory .factorio/mods
    '';

    scripts.lint.exec = ''
      # Explicit mod paths: avoid walking .factorio/ (dev sandbox with a
      # symlink back to the repo root). Add your own lua roots here as the mod grows.
      exec luacheck lib data.lua control.lua
    '';

    scripts.fmt.exec = ''
      exec stylua lib data.lua control.lua spec
    '';

    scripts.package.exec = ''
      name=$(jq -r .name info.json); version=$(jq -r .version info.json)
      out="''${name}_''${version}.zip"
      git archive --format zip --prefix "''${name}/" --worktree-attributes --output "$out" HEAD
      echo "Packaged $out"
    '';

    enterShell = ''
      echo "Factorio mod dev env — channel: ''${FACTORIO_CHANNEL:-experimental}"
      echo "  modtest [chan]   busted + headless load-smoke   (canonical: devenv test)"
      echo "  bench  [chan]    headless benchmark  (env: BENCH_TICKS=, BENCH_SAVE=)"
      echo "  play   [chan]    full client (opt-in: withClient=true in devenv.nix)"
      echo "  lint | fmt | package"
      echo "  channels: stable | experimental   (export FACTORIO_CHANNEL to pin a shell)"
      echo "  note: the test command is 'modtest' — 'test' is the bash builtin."
    '';

    # devenv's CI gate — same command CI runs.
    enterTest = ''
      modtest
    '';

    git-hooks = {
      enable = true;
      hooks = {
        stylua = {
          enable = true;
          entry = "${pkgs.stylua}/bin/stylua";
          files = "\\.lua$";
          language = "system";
        };
        luacheck = {
          enable = true;
          entry = "${pkgs.luaPackages.luacheck}/bin/luacheck";
          files = "\\.lua$";
          language = "system";
        };
        busted = {
          enable = true;
          name = "busted";
          entry = "${pkgs.lua52Packages.busted}/bin/busted";
          language = "system";
          stages = [ "pre-push" ];
          pass_filenames = false;
        };
        convcommit = {
          enable = true;
          name = "conventional-commits";
          entry = "${pkgs.bash}/bin/bash ${./scripts/commit-msg.sh}";
          language = "system";
          stages = [ "commit-msg" ];
          pass_filenames = true;
        };
      };
    };
  };
}
