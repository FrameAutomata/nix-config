# headroom — context-compression proxy for LLM agents (headroomlabs-ai/headroom).
#
# Not in nixpkgs (yet — see draft PR NixOS/nixpkgs#529964). The dependency gap
# is smaller than it looks: of the 164 distributions the [all] extra installs,
# nixpkgs already has all but ast-grep-cli and headroom-ai itself (the other
# apparent misses are nvidia-* CUDA wheels, which nixpkgs supplies via
# cudaPackages and a CPU build does not need). The real friction is version
# skew and release cadence: headroom wants litellm >=1.86.2 where nixpkgs
# carries 1.86.0, and it is a fast-moving 0.x that ships its own
# `headroom update`.
#
# So this derivation is deliberately a *provisioner*, not a build: it owns a
# venv under $XDG_STATE_HOME and makes the generic-linux wheels inside it
# actually run on NixOS. Trade-off accepted knowingly — it tracks upstream
# directly instead of waiting on a nixpkgs bump.
#
# Three things break a plain `pip install headroom-ai[all]` on NixOS, all fixed
# below:
#
#   1. uv downloads its own CPython, which is dynamically linked against a
#      loader we don't have. Pinned to nixpkgs python instead
#      (UV_PYTHON_DOWNLOADS=never).
#   2. Extension modules (onnxruntime, numpy, …) need libstdc++/libgcc/zlib,
#      which are not on any default search path here. Fixed by stamping an
#      RPATH into every .so at provision time rather than exporting
#      LD_LIBRARY_PATH — an exported path would be inherited by `claude` and
#      every other child process `headroom wrap` spawns, and Nix binaries use
#      DT_RUNPATH (searched *after* LD_LIBRARY_PATH), so it could shadow their
#      own libstdc++ with this one.
#   3. headroom ships/downloads generic-linux CLI binaries (ast-grep, difft,
#      scc) that cannot exec here. nixpkgs builds of all three are put on PATH
#      and symlinked over the broken ones in the venv.
#
# Known-not-our-problem: /health reports kompress (the ML *prose* compressor)
# as unhealthy with a null backend. That is an upstream bug, not a NixOS one —
# 0.33.0 asks HuggingFace for chopratejas/kompress-v2-base/onnx/kompress-int8.onnx,
# which 404s; the repo only publishes kompress-fp32.onnx and kompress-int8-wo.onnx.
# Verified here that onnxruntime loads kompress-int8-wo.onnx and builds an
# InferenceSession fine, so this fixes itself upstream with no change below.
# Everything else (JSON/code compression, proxy, routing) is unaffected.
#
# Upgrades: bump `version`, rebuild. The stamp file records the version and the
# native-lib paths, so a nixpkgs bump that moves libstdc++ also forces a clean
# reprovision. `headroom update` still works and will move the venv ahead of
# this pin until the next rebuild notices the stamp is stale.
{
  lib,
  writeShellApplication,
  python313,
  uv,
  ast-grep,
  difftastic,
  scc,
  patchelf,
  cacert,
  stdenv,
  zlib,
  coreutils,
  findutils,
}:

let
  version = "0.33.0";

  # Everything the wheels' .so files need beyond libc.
  nativeLibs = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    zlib
  ];
in
writeShellApplication {
  name = "headroom";

  runtimeInputs = [
    python313
    uv
    patchelf
    coreutils
    findutils
    # Working replacements for the binaries headroom would otherwise fetch.
    ast-grep
    difftastic
    scc
  ];

  text = ''
    venv="''${XDG_STATE_HOME:-$HOME/.local/state}/headroom/venv"
    stamp="$venv/.nix-provisioned"

    # Any change to the pinned version OR to the native library paths (i.e. a
    # nixpkgs bump) invalidates the venv — a stale RPATH points into a garbage
    # collected store path and fails at import time, not at rebuild time.
    want="${version} ${nativeLibs}"

    if [ "$(cat "$stamp" 2>/dev/null || true)" != "$want" ]; then
      echo "headroom: provisioning venv for ${version} (one-off, ~1-2 min)..." >&2

      rm -rf "$venv"
      mkdir -p "$(dirname "$venv")"

      export UV_PYTHON_DOWNLOADS=never
      export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"

      uv venv --python "${python313}/bin/python3.13" "$venv" >&2
      # --link-mode=copy is load-bearing, not a preference: uv's default is to
      # hardlink wheel contents out of ~/.cache/uv, so the RPATH rewriting below
      # would edit the *cache* in place and poison every future venv on this
      # machine (including non-headroom ones) with store paths that a GC can
      # delete out from under them.
      uv pip install --link-mode=copy --python "$venv/bin/python" \
        "headroom-ai[all]==${version}" >&2

      # Stamp an RPATH into every extension module so imports resolve without
      # leaking LD_LIBRARY_PATH into child processes.
      patched=0
      while IFS= read -r -d "" so; do
        head -c4 "$so" | grep -q ELF || continue
        old="$(patchelf --print-rpath "$so" 2>/dev/null)" || continue
        case ":$old:" in
          *"${nativeLibs}"*) continue ;;
        esac
        patchelf --set-rpath "''${old:+$old:}${nativeLibs}" "$so" 2>/dev/null && patched=$((patched + 1))
      done < <(find "$venv/lib" -type f \( -name "*.so" -o -name "*.so.*" \) -print0)
      echo "headroom: patched $patched shared objects" >&2

      # The wheels' own ast-grep/sg cannot exec here; point them at the
      # nixpkgs build, which is also what PATH resolution below will find.
      ln -sf "${ast-grep}/bin/ast-grep" "$venv/bin/ast-grep"
      ln -sf "${ast-grep}/bin/ast-grep" "$venv/bin/sg"
      ln -sf "${difftastic}/bin/difft" "$venv/bin/difft"
      ln -sf "${scc}/bin/scc" "$venv/bin/scc"

      echo "$want" > "$stamp"
      echo "headroom: ready." >&2
    fi

    exec "$venv/bin/headroom" "$@"
  '';
}
