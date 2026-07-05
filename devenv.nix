{ pkgs, lib, config, ... }:

let
  # The headless package for a channel. Lazy: only forced when withGame is true
  # (the fct-paths case interpolates it conditionally), so a busted-only shell
  # never downloads the ~150 MB game binary.
  # nixpkgs (stable + rolling) still packages 2.0.76 for BOTH channels, so the
  # experimental headless comes straight from factorio.com (free, no token). Same
  # tarball layout as 2.0 -- only src/version change.
  # ponytail: pinned to 2.1.9; bump these two lines per experimental release, and
  # drop the override once nixpkgs ships factorio-headless-experimental >= 2.1.
  headlessExperimental = pkgs.factorio-headless-experimental.overrideAttrs (old: rec {
    version = "2.1.9";
    src = pkgs.fetchurl {
      name = "factorio_headless_x64-${version}.tar.xz";
      url = "https://factorio.com/get-download/${version}/headless/linux64";
      sha256 = "102r2ryp0igkjb4ya29cpm5338blyqlpcvrmaxcbk4kwhwkl7y9c";
    };
  });

  headlessFor = channel:
    if channel == "experimental"
    then headlessExperimental
    else pkgs.factorio-headless;

  # "bin data" pair for the headless server of a channel.
  headlessPaths = channel:
    "${headlessFor channel}/bin/factorio ${headlessFor channel}/share/factorio/data";

  # The unfree client needs the account username + token passed into the
  # derivation (nixpkgs factorio does NOT read env vars at runtime). builtins.getEnv
  # reads them at eval time, so they must be exported BEFORE nix evaluates -- e.g.
  # via direnv `dotenv .env` in .envrc, or `export $(grep -v '^#' .env | xargs)`
  # before `devenv shell`. .env-via-dotenv.enable is too late for the build.
  clientFor = channel:
    (if channel == "experimental" then pkgs.factorio-experimental else pkgs.factorio).override {
      username = builtins.getEnv "FACTORIO_USERNAME";
      token = builtins.getEnv "FACTORIO_TOKEN";
    };

  # nixpkgs also packages only 2.0.76 for the experimental CLIENT, so `play
  # experimental` can't load a factorio_version 2.1 mod. Same override as
  # headlessExperimental, but the full (alpha) client is auth-gated, so the token
  # goes in the URL (same getEnv posture clientFor already uses; it lands in the
  # .drv -- fine for a single-user dev env). sha256 from factorio.com/download/
  # sha256sums (cross-checked against the headless hash).
  # ponytail: pinned to 2.1.9; bump alongside headlessExperimental per release, and
  # drop once nixpkgs ships factorio-experimental >= 2.1.
  clientExperimental = (clientFor "experimental").overrideAttrs (old: rec {
    version = "2.1.9";
    src = pkgs.fetchurl {
      name = "factorio_alpha_x64-${version}.tar.xz";
      url = "https://factorio.com/get-download/${version}/alpha/linux64"
        + "?username=${builtins.getEnv "FACTORIO_USERNAME"}&token=${builtins.getEnv "FACTORIO_TOKEN"}";
      sha256 = "sha256-ni09mm8yPC00IV8mR1FZnZyah6mvLHxL3L7o+418ckU=";
    };
  });
in
{
  options.withGame = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Pull the free headless server and enable the load-smoke / bench commands. Disable for a busted-only lightweight shell.";
  };

  options.withClient = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Build the full (unfree) game client for `play`. Requires FACTORIO_USERNAME / FACTORIO_TOKEN at build time.";
  };

  config = {
    # Load FACTORIO_USERNAME / FACTORIO_TOKEN (and anything else) from a
    # gitignored .env, so the unfree client build can authenticate without
    # exporting secrets by hand. See .env.example.
    dotenv.enable = true;

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
      FACTORIO_CLIENT_EXPERIMENTAL = "${clientExperimental}/bin/factorio";
      FACTORIO_CLIENT_STABLE = "${clientFor "stable"}/bin/factorio";
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
        echo "== in-game tests ($chan) =="
        # instrument-control.lua runs only under --instrument-mod: it exercises the
        # mod in the engine's own Lua VM and the live in-world entity path, erroring
        # (non-zero exit, no PASSED line) on any failure. Gate on the PASS sentinel.
        "$bin" --config .factorio/config.ini --mod-directory .factorio/mods \
               --benchmark "$save" --benchmark-ticks 100 --instrument-mod lamented-cpu \
          | tee .factorio/ingame.log
        grep -qF "PASSED: example programs" .factorio/ingame.log \
          || { echo "in-game tests FAILED (see .factorio/ingame.log)"; exit 1; }
      else
        echo "== load-smoke + in-game tests skipped (withGame=false) =="
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
      exec luacheck lib data.lua control.lua instrument-control.lua scripts/render-wiki.lua
    '';

    scripts.fmt.exec = ''
      exec stylua lib data.lua control.lua spec scripts/render-wiki.lua
    '';

    scripts.package.exec = ''
      name=$(jq -r .name info.json); version=$(jq -r .version info.json)
      out="''${name}_''${version}.zip"
      git archive --format zip --prefix "''${name}/" --worktree-attributes --output "$out" HEAD
      echo "Packaged $out"
    '';

    # Regenerate the committed riscv-tests .s fixtures (ADR-0004). The Hart runs
    # assembly, not binaries: clone riscv-tests at a pinned rev and expand each
    # test source with cpp against our custom minimal M-mode env (spec/riscv-env)
    # into flat, self-contained assembly. No RISC-V toolchain and no machine code;
    # only cpp, pulled via nix shell so it never touches the `devenv test` CI gate.
    # ponytail: cpp + a custom env at vendor time instead of reimplementing
    # cpp+gas+ld; rv32mi lands here once the env gains M-mode encoding consts (#7).
    scripts.gen-riscv-tests.exec = ''
      set -euo pipefail
      rev="34e6b6d1e7936b526075432fb730d89148623484" # pinned riscv-tests
      export GEN_ENV="$PWD/spec/riscv-env"
      export GEN_OUT="$PWD/spec/fixtures/riscv-tests"
      work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
      echo "== clone riscv-tests @ $rev =="
      git clone --quiet https://github.com/riscv-software-src/riscv-tests "$work"
      git -C "$work" checkout --quiet "$rev"
      export GEN_ISA="$work/isa"
      echo "== expand rv32ui/rv32um sources to flat .s (cpp + custom M-mode env) =="
      find "$GEN_OUT" -name '*.s' -delete 2>/dev/null || true
      mkdir -p "$GEN_OUT"
      # rv32mi is vendored selectively: the M-mode tests our RV32IM_Zicsr core
      # can pass. The rest (misalign-trap variants conflict with rv32ui ma_data;
      # pmpaddr/breakpoint/instret_overflow/zicntr need out-of-scope extensions)
      # are deliberately omitted -- see ADR-0004 and the slice #7 note.
      mi_tests="csr mcsr scall sbreak shamt"
      nix shell nixpkgs#gcc -c bash -c '
        set -e
        for fam in rv32ui rv32um; do
          for src in "$GEN_ISA/$fam"/*.S; do
            name=$(basename "$src" .S)
            cpp -E -P -nostdinc -D__riscv_xlen=32 \
              -I "$GEN_ENV" -I "$GEN_ISA/macros/scalar" \
              "$src" > "$GEN_OUT/$fam-p-$name.s"
          done
        done
        for name in '"$mi_tests"'; do
          cpp -E -P -nostdinc -D__riscv_xlen=32 \
            -I "$GEN_ENV" -I "$GEN_ISA/macros/scalar" \
            "$GEN_ISA/rv32mi/$name.S" > "$GEN_OUT/rv32mi-p-$name.s"
        done
      '
      echo "wrote $(ls "$GEN_OUT"/*.s | wc -l) .s fixtures (riscv-tests @ $rev)"
    '';

    # Regenerate the committed riscv-vector-tests .s fixtures: the full zve32x
    # preset at VLEN=128 / XLEN=32 (ADR-0012). Pipeline per instruction: the
    # pinned Go generator emits a stage-1 source; a bare-metal RISC-V gcc
    # compiles it; pspike (the pinned Spike + the generator's magic custom-0
    # instruction) prints the golden TEST_CASE patches; the generator's merger
    # splices them into a self-checking stage-2 source, which is verified under
    # stock pinned Spike and then flattened with cpp against our Test env
    # (spec/riscv-env) into a plain committed .s. Go/Spike/gcc/cpp are pulled
    # via nix shell at vendor time only -- the `devenv test` CI gate never sees
    # them. Reproducible: the generator's randomness is input-seeded, and both
    # revisions are pinned here (Spike's is the generator CI's own pin).
    scripts.gen-riscv-vector-tests.exec = ''
      set -euo pipefail
      gen_rev="f76bff121dce91b6b23e1d37be77a5e44af914c3" # pinned riscv-vector-tests
      spike_rev="20feb9c2bf2a7deab964d8190b0cbd4b4131bec3" # pinned riscv-isa-sim
      export GEN_ENV="$PWD/spec/riscv-env"
      export GEN_OUT="$PWD/spec/fixtures/riscv-vector-tests"
      work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
      echo "== clone riscv-vector-tests @ $gen_rev =="
      git clone --quiet https://github.com/chipsalliance/riscv-vector-tests "$work/gen"
      git -C "$work/gen" checkout --quiet "$gen_rev"
      git -C "$work/gen" submodule update --init --quiet env/riscv-test-env
      echo "== clone riscv-isa-sim @ $spike_rev =="
      git clone --quiet https://github.com/riscv-software-src/riscv-isa-sim "$work/spike"
      git -C "$work/spike" checkout --quiet "$spike_rev"
      export GEN_WORK="$work"
      nix shell nixpkgs#go nixpkgs#gcc nixpkgs#dtc nixpkgs#gnumake \
        nixpkgs#pkgsCross.riscv64-embedded.buildPackages.gcc -c bash -c '
        set -euo pipefail
        cd "$GEN_WORK/gen"
        echo "== build spike (golden model) =="
        mkdir -p "$GEN_WORK/spike/build"
        ( cd "$GEN_WORK/spike/build" && ../configure --prefix="$GEN_WORK/spike-install" \
            >/dev/null && make -j"$(nproc)" >/dev/null && make install >/dev/null )
        echo "== build generator, merger, pspike =="
        export GOFLAGS=-mod=mod GOPATH="$GEN_WORK/go" GOCACHE="$GEN_WORK/gocache"
        go build -o build/generator .
        go build -o build/merger merger/merger.go
        g++ -std=c++17 -I"$GEN_WORK/spike-install/include" -L"$GEN_WORK/spike-install/lib" \
          pspike/pspike.cc -lriscv -lfesvr -o build/pspike
        export ISA=rv32gcv_zvl128b_zve32f_zfh_zfhmin_zvfh
        out="$GEN_WORK/out"
        mkdir -p "$out/stage1" "$out/bin1" "$out/patch" "$out/stage2" "$out/bin2"
        echo "== stage 1: generate (zve32x preset: VLEN=128 XLEN=32 INTEGER=1) =="
        ./build/generator -VLEN 128 -XLEN 32 -split=10000 -integer=1 -pattern=".*" \
          -testfloat3level=2 -repeat=1 -stage1output "$out/stage1/" -configs configs/ \
          -march rv32gcv
        echo "== stage 1: compile + pspike golden patches =="
        cc() {
          riscv64-none-elf-gcc -march=rv32gcv -mabi=ilp32f -static -mcmodel=medany \
            -fvisibility=hidden -nostdlib -nostartfiles -DENTROPY=0xdeadbeef \
            -DLFSR_BITS=9 -fno-tree-loop-distribute-patterns \
            -Ienv/riscv-test-env/p -Imacros/general -Tenv/riscv-test-env/p/link.ld "$@"
        }
        export -f cc
        patch_one() {
          set -e
          t=$(basename "$1" .S)
          cc "$1" -o "$GEN_WORK/out/bin1/$t"
          LD_LIBRARY_PATH="$GEN_WORK/spike-install/lib" ./build/pspike --isa="$ISA" \
            "$GEN_WORK/out/bin1/$t" > "$GEN_WORK/out/patch/$t.patch"
        }
        export -f patch_one
        find "$out/stage1" -name "*.S" -print0 \
          | xargs -0 -P"$(nproc)" -I{} bash -c "patch_one \"\$@\"" _ {}
        echo "== stage 2: merge golden values =="
        ./build/merger -stage1output "$out/stage1/" -stage2output "$out/stage2/" \
          -stage2patch "$out/patch/"
        echo "== stage 2: verify every test under stock spike =="
        verify_one() {
          set -e
          t=$(basename "$1" .S)
          cc "$1" -o "$GEN_WORK/out/bin2/$t"
          "$GEN_WORK/spike-install/bin/spike" --isa="$ISA" "$GEN_WORK/out/bin2/$t" \
            >/dev/null || { echo "SPIKE-FAIL $t" >&2; exit 1; }
        }
        export -f verify_one
        find "$out/stage2" -name "*.S" -print0 \
          | xargs -0 -P"$(nproc)" -I{} bash -c "verify_one \"\$@\"" _ {}
        echo "== flatten with cpp against the Test env =="
        find "$GEN_OUT" -name "*.s" -delete 2>/dev/null || true
        mkdir -p "$GEN_OUT"
        for s in "$out/stage2/"*.S; do
          t=$(basename "$s" .S)
          cpp -E -P -nostdinc -D__riscv_xlen=32 -I "$GEN_ENV" -I macros/general \
            "$s" > "$GEN_OUT/$t.s"
        done
      '
      echo "wrote $(ls "$GEN_OUT"/*.s | wc -l) .s fixtures (riscv-vector-tests @ $gen_rev, spike @ $spike_rev)"
    '';

    enterShell = ''
      echo "Factorio mod dev env — channel: ''${FACTORIO_CHANNEL:-experimental}"
      echo "  modtest [chan]   busted + headless load-smoke   (canonical: devenv test)"
      echo "  bench  [chan]    headless benchmark  (env: BENCH_TICKS=, BENCH_SAVE=)"
      echo "  play   [chan]    full client (opt-in: withClient=true in devenv.nix)"
      echo "  lint | fmt | package"
      echo "  gen-riscv-tests  rebuild committed riscv-tests .s fixtures (dev-only, pinned)"
      echo "  gen-riscv-vector-tests  rebuild the zve32x fixture set (dev-only, pinned; slow)"
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
