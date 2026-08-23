# aurral — Lidarr companion: per-user music discovery and request UI
# (lklynet/aurral). Not in nixpkgs.
#
# Upstream ships Docker only, so everything here is a translation of its
# Dockerfile into a store path. Four things in that Dockerfile do NOT come
# across, deliberately:
#
#   1. docker-entrypoint.sh is pure PUID/PGID shuffling — it useradds a
#      runtime user, chowns /config, then drops privileges. systemd already
#      owns all of that (DynamicUser + StateDirectory), so the entrypoint is
#      skipped and `node backend/server.js` is exec'd directly.
#   2. yt-dlp is ADDed from a GitHub release at a pinned sha256. Here it is
#      nixpkgs' yt-dlp on the wrapper's PATH — backend/services/ytdlpClient.js
#      resolves DEFAULT_BINARY = "yt-dlp" by walking PATH, and the UI can
#      still override it with an absolute path.
#   3. LD_PRELOAD=libjemalloc.so.2. An allocator swap for a long-lived
#      image, not a correctness fix; glibc malloc is fine at this scale and
#      an LD_PRELOAD would be inherited by every yt-dlp/ffmpeg child.
#   4. The bundled fonts (fonts-dejavu-core, noto-color-emoji). sharp only
#      needs them for text rendering, which this app never does — it resizes
#      and re-encodes cover art.
#
# nodejs_22 is not a default-version accident: .nvmrc pins 22.23.2, root
# package.json declares `engines.node = "22.23.x"`, and .npmrc sets
# engine-strict=true, so npm hard-fails on any other major. nixpkgs'
# nodejs_22 happens to be exactly 22.23.2. (Upstream's own Dockerfile builds
# on node 26, which contradicts its own engines field — follow the manifest,
# not the image.)
#
# Of the four native modules, three load fine from the prebuilds npm ships
# (bcrypt and better-sqlite3 carry glibc .node files; honker is a NAPI blob
# needing only a patchelf and libsqlite3). sharp is the exception and gets
# built from source — see the preBuild note.
{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  python3,
  node-gyp,
  pkg-config,
  sqlite,
  vips,
  autoPatchelfHook,
  makeWrapper,
  ffmpeg-headless,
  yt-dlp,
}:

buildNpmPackage (finalAttrs: {
  pname = "aurral";
  version = "2.5.1";

  src = fetchFromGitHub {
    owner = "lklynet";
    repo = "aurral";
    tag = "v${finalAttrs.version}";
    hash = "sha256-TUSww/he02qzcqJEMEljpOEFyfjWngyMfqopUHzU0uk=";
  };

  npmDepsHash = "sha256-QhDSrcdB22jhpnThNpJVUOAr93gsN3f+XvisAXmVfp8=";

  nodejs = nodejs_22;

  nativeBuildInputs = [
    # node-gyp shells out to python3 to configure sharp's binding
    python3
    node-gyp
    # sharp's build.js locates libvips with `pkg-config --modversion vips-cpp`
    pkg-config
    # bcrypt/better-sqlite3/honker ship prebuilt .node blobs linked against a
    # generic-linux loader; they are unrunnable here until patchelfed
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    # libstdc++/libgcc for those same prebuilt blobs — nothing on NixOS puts
    # them on a default search path
    stdenv.cc.cc.lib
    # honker.linux-x64-gnu.node links libsqlite3 dynamically (unlike
    # better-sqlite3, which statically links its own copy)
    sqlite
    # sharp links this at build time; nixpkgs' 8.18.3 is the same libvips
    # version sharp 0.35.3 vendors, so no feature drift
    vips
  ];

  env = {
    # sharp's npm-shipped binding segfaults the moment node dlopen()s it, even
    # once autoPatchelfHook has resolved every soname it asks for — the
    # prebuilt libvips is built against a different libc than the one it ends
    # up running on. Force the source build against nixpkgs' vips instead;
    # this is the same route nixpkgs takes for immich.
    SHARP_FORCE_GLOBAL_LIBVIPS = "1";

    # The frontend reads these at build time (Vite inlines them) and the UI
    # shows the result in its update banner. Left unset they render as
    # "unknown", which makes the version check in the UI useless.
    VITE_APP_VERSION = finalAttrs.version;
    VITE_GITHUB_REPO = "lklynet/aurral";
    VITE_RELEASE_CHANNEL = "stable";
  };

  # sharp 0.35 dropped its npm `install` script — the source build is now an
  # explicit `node install/build.js`, so buildNpmPackage's `npm ci
  # --ignore-scripts` is not what suppresses it; nothing would ever run it.
  # That script require()s node-gyp AND shells out to it, and node-gyp is
  # absent from the lockfile because npm normally supplies its own copy, so
  # both the module path and PATH have to be satisfied here.
  preBuild = ''
    ln -s ${node-gyp}/lib/node_modules/node-gyp node_modules/node-gyp
    ( cd node_modules/sharp && node install/build.js )
  '';

  # Upstream's root package.json is `private: true` with a workspaces array
  # and no `files`, so npmInstallHook's `npm pack` has nothing meaningful to
  # install. Lay the runtime tree out by hand instead, matching the paths the
  # code actually resolves: server.js:241 joins __dirname/../frontend/dist,
  # so backend/ and frontend/ must stay siblings.
  installPhase = ''
    runHook preInstall

    # devDependencies (vite, eslint, the whole React toolchain) are build-only
    # — the frontend is already compiled to frontend/dist by this point.
    # --omit=dev keeps optionalDependencies, which is where honker's platform
    # binary lives; --omit=optional would break it.
    npm prune --omit=dev

    # Drop the sharp prebuilds now that src/build/Release holds a real one.
    # dist/sharp.mjs tries the source build first and dist/utility.mjs skips
    # the @img/* lookups entirely when libvips is global, so nothing reaches
    # for these — leaving them would only keep a segfaulting binding and a
    # second libvips in the closure. @img/colour is a plain JS dependency and
    # stays.
    rm -rf node_modules/@img/sharp-*

    # bcrypt and better-sqlite3 ship musl prebuilds alongside their glibc
    # ones. Nothing loads them here, but autoPatchelfHook inspects every ELF
    # it finds and fails the build on the libc.musl-x86_64.so.1 it cannot
    # resolve. (npm delivered them at all only because the sandbox gives it no
    # libc family to filter on; upstream's Debian image never receives them.)
    find node_modules -name '*musl*' -prune -exec rm -rf {} +

    mkdir -p $out/lib/aurral/frontend
    cp -r backend lib node_modules package.json $out/lib/aurral/
    cp -r frontend/dist $out/lib/aurral/frontend/dist

    # PATH, not a patched-in store path: the download clients are optional
    # features, and ytdlpClient.js already treats a missing binary as a
    # disabled feature rather than an error.
    makeWrapper ${lib.getExe nodejs_22} $out/bin/aurral \
      --add-flags $out/lib/aurral/backend/server.js \
      --prefix PATH : ${
        lib.makeBinPath [
          yt-dlp
          ffmpeg-headless
        ]
      } \
      --set-default APP_VERSION ${finalAttrs.version}

    runHook postInstall
  '';

  meta = {
    description = "Self-hosted music discovery and request manager for Lidarr";
    homepage = "https://aurral.org";
    changelog = "https://github.com/lklynet/aurral/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "aurral";
    platforms = lib.platforms.linux;
  };
})
