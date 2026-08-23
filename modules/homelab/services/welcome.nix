# Self-guided onboarding page for household members: a static vhost that
# walks a new roommate through every account and app, so the admin only
# runs `homelab-onboard <handle>` (onboard.nix) and hands over the printed
# credential sheet — the page does the rest. Sections render only for
# services that are actually enabled. No secrets here: the repo is public
# and so is everything this page interpolates.
{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.services.welcome;
  homelab = config.homelab;
  services = homelab.services;
  subdomain = "welcome";
  url = name: "https://${name}.${homelab.baseDomain}";
  when = lib.optionalString;

  # Install links for the client apps a member puts on their own devices,
  # rendered as a row of chips under the prose that says what the app is for.
  # Store URLs verified 2026-08-01. Where a project has no single official
  # listing per platform (Navidrome, Audiobookshelf on iOS) the chip points at
  # the project's own client list instead of the admin picking for everyone.
  appRow = links: ''
    <p class="apps">${lib.concatMapStrings
      (l: ''<a class="app" href="${l.url}">${l.name}</a>'') links}</p>
  '';

  page = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Welcome to the house server</title>
    <style>
      :root { color-scheme: dark; }
      body { margin: 0 auto; max-width: 46rem; padding: 2rem 1.25rem 4rem;
             background: #101418; color: #d8dee6;
             font: 16px/1.6 system-ui, sans-serif; }
      h1 { font-size: 1.7rem; margin-bottom: .25rem; }
      h2 { font-size: 1.15rem; margin: 0 0 .5rem; color: #fff; }
      a { color: #7ab8f5; }
      .card { background: #181f26; border: 1px solid #232c35;
              border-radius: 10px; padding: 1rem 1.25rem; margin: 1rem 0; }
      .step { color: #7ab8f5; font-weight: 600; font-size: .8rem;
              text-transform: uppercase; letter-spacing: .08em; }
      code { background: #232c35; border-radius: 4px; padding: .1rem .35rem;
             font-size: .9em; }
      .muted { color: #8a949e; font-size: .9rem; }
      ul { padding-left: 1.2rem; } li { margin: .3rem 0; }
      .apps { display: flex; flex-wrap: wrap; gap: .4rem; margin: .6rem 0 0; }
      .app { background: #232c35; border: 1px solid #2f3a45; border-radius: 999px;
             padding: .2rem .7rem; font-size: .85rem; text-decoration: none;
             white-space: nowrap; }
      .app:hover { border-color: #7ab8f5; }
    </style>
    </head>
    <body>
    <h1>Welcome to the house server 👋</h1>
    <p class="muted">Work through these steps once, top to bottom. You'll need
    the credential sheet from the admin. Everything lives at
    <a href="${url "home"}">home.${homelab.baseDomain}</a> afterwards.</p>

    ${when services.vaultwarden.enable ''
      <div class="card">
        <div class="step">Step 1 — Password manager</div>
        <h2>Vaultwarden</h2>
        <p>Do this first: create an account at
        <a href="${url "vault"}">vault.${homelab.baseDomain}</a> and install the
        Bitwarden app/extension pointed at that URL (self-hosted server).
        As you go through the steps below, save every credential from your
        sheet in here — then shred the sheet.</p>
        ${appRow [
          { name = "iPhone / iPad"; url = "https://apps.apple.com/us/app/bitwarden-password-manager/id1137397744"; }
          { name = "Android"; url = "https://play.google.com/store/apps/details?id=com.x8bit.bitwarden"; }
          { name = "Browser &amp; desktop"; url = "https://bitwarden.com/download/"; }
        ]}
        <p class="muted">Point it at our server <b>before</b> you log in — the
        gear/settings icon on the login screen → self-hosted environment →
        server URL <code>${url "vault"}</code>. Otherwise it tries to log you
        in to bitwarden.com and your account won't exist there.</p>
      </div>
    ''}

    ${when services.samba.enable ''
      <div class="card">
        <div class="step">Step 2 — Your files</div>
        <h2>Network drive</h2>
        <p>Connect with your handle + the network-drive password from your sheet:</p>
        <ul>
          <li><b>Windows:</b> File Explorer address bar →
              <code>\\${homelab.baseDomain}\&lt;your handle&gt;</code></li>
          <li><b>macOS:</b> Finder → ⌘K →
              <code>smb://${homelab.baseDomain}</code></li>
          <li><b>iPhone / iPad:</b> nothing to install — the built-in Files
              app → ⋯ → Connect to Server →
              <code>smb://${homelab.baseDomain}</code></li>
          <li><b>Android:</b> a file manager with SMB support (e.g. Cx File
              Explorer) → host <code>${homelab.baseDomain}</code></li>
        </ul>
        ${appRow [
          { name = "Android — Cx File Explorer"; url = "https://play.google.com/store/apps/details?id=com.cxinventor.file.explorer"; }
        ]}
        <p>Shares: your <b>private share</b> is named after your handle
        (hidden — type the path), <code>shared</code> is the household drop
        zone, <code>media</code> is the communal library.
        If the name won't resolve, use <code>${homelab.lanIP}</code> instead.</p>
        ${when services.filebrowser.enable ''
          <p>Browser alternative for your private space:
          <a href="${url "files"}">files.${homelab.baseDomain}</a> — same
          handle, FileBrowser password from your sheet (change it in
          Settings after first login).</p>
        ''}
      </div>
    ''}

    <div class="card">
      <div class="step">Step 3 — Media</div>
      <h2>Watch, listen, request</h2>
      <p>The admin creates these accounts for you — same handle, ask if one
      is missing:</p>
      <p class="muted">In every app below, the server address is the same link
      as the one in the bullet, and you sign in with your handle.</p>
      <ul>
        ${when services.jellyfin.enable ''
          <li><a href="${url "jellyfin"}">Jellyfin</a> — movies &amp; TV.
              Server <code>${url "jellyfin"}</code>. Works in any browser too.
              ${appRow [
                { name = "iPhone / Apple TV — Swiftfin"; url = "https://apps.apple.com/us/app/swiftfin/id1604098728"; }
                { name = "Android"; url = "https://play.google.com/store/apps/details?id=org.jellyfin.mobile"; }
                { name = "Android TV / Fire TV"; url = "https://play.google.com/store/apps/details?id=org.jellyfin.androidtv"; }
                { name = "Other devices"; url = "https://jellyfin.org/downloads/"; }
              ]}</li>
        ''}
        ${when services.jellyseerr.enable ''
          <li><a href="${url "requests"}">Requests</a> — ask for new movies
              or shows; they download automatically (sign in with your
              Jellyfin account). No app needed — open it in your browser and
              add it to your home screen if you want an icon.</li>
        ''}
        ${when services.aurral.enable ''
          <li><a href="${url "music-requests"}">Music requests</a> — ask for
              an artist or album and it downloads automatically. Separate
              login from the one above: the admin makes you an Aurral account
              (Settings → Users), and it is the only place you request music
              — ${when services.jellyseerr.enable "the requests page above is movies and shows only, and "}the
              music player itself has no request button.</li>
        ''}
        ${when services.immich.enable ''
          <li><a href="${url "photos"}">Photos</a> — back up your phone's
              camera roll and browse it from anywhere. Server
              <code>${url "photos"}</code>. Immich signs you in with an
              <b>email + password</b> (not your handle) — the admin sets those
              up and passes them to you; you'll change the password on first
              login. Then turn on backup in the app (Settings → Backup). Your
              photos are private to your account — other members can't see them.
              ${appRow [
                { name = "iPhone / iPad"; url = "https://apps.apple.com/us/app/immich/id1613945652"; }
                { name = "Android"; url = "https://play.google.com/store/apps/details?id=app.alextran.immich"; }
                { name = "Other devices"; url = "https://immich.app/docs/features/mobile-app/"; }
              ]}</li>
        ''}
        ${when services.navidrome.enable ''
          <li><a href="${url "music"}">Music</a> — the shared library.
              Any Subsonic-compatible app works, but install one of these:
              they play albums <b>gaplessly</b> and auto-advance, which the
              in-browser player does not.
              ${appRow [
                { name = "iPhone / iPad / Mac — Amperfy"; url = "https://apps.apple.com/us/app/amperfy-music/id1530145038"; }
                { name = "Android — Tempo"; url = "https://cappielloantonio.github.io/tempo/"; }
                { name = "Windows / Mac / Linux — Supersonic"; url = "https://github.com/dweymouth/supersonic/releases"; }
                { name = "Other clients"; url = "https://www.navidrome.org/docs/overview/#apps"; }
              ]}
              <span class="muted">Set it up once: on the app's add-server / login
              screen enter server <code>${url "music"}</code>, username your
              handle, password the admin gave you. Then open the app's playback
              settings and turn <b>gapless on</b> (and crossfade off) so albums
              flow track-to-track. Play from the <b>album</b> view for the right
              order. No app? <a href="${url "music"}">music.${homelab.baseDomain}</a>
              runs in any browser — it just won't play gaplessly.</span></li>
        ''}
        ${when services.audiobookshelf.enable ''
          <li><a href="${url "abs"}">Audiobooks &amp; podcasts</a> —
              Audiobookshelf, server <code>${url "abs"}</code>.
              ${appRow [
                { name = "Android"; url = "https://play.google.com/store/apps/details?id=com.audiobookshelf.app"; }
                { name = "iPhone — ShelfPlayer"; url = "https://apps.apple.com/us/app/shelfplayer/id6475221163"; }
                { name = "iPhone — SoundLeaf"; url = "https://apps.apple.com/us/app/soundleaf/id6738635634"; }
              ]}
              <span class="muted">There is no official iPhone app yet — those
              two are third-party players (paid or paid-extras) that talk to
              our server. The website works fine on iPhone if you'd rather
              not buy one.</span></li>
        ''}
      </ul>
    </div>

    ${when services.ntfy.enable ''
      <div class="card">
        <div class="step">Step 4 — House notifications</div>
        <h2>ntfy</h2>
        <p>Install the ntfy app and subscribe to the house topic: use server
        <code>${url "ntfy"}</code>, topic
        <code>${services.ntfy.topic}</code>.</p>
        ${appRow [
          { name = "iPhone / iPad"; url = "https://apps.apple.com/us/app/ntfy/id1625396347"; }
          { name = "Android"; url = "https://play.google.com/store/apps/details?id=io.heckel.ntfy"; }
          { name = "Android — F-Droid"; url = "https://f-droid.org/packages/io.heckel.ntfy/"; }
        ]}
      </div>
    ''}

    ${when services.headscale.enable ''
      <div class="card">
        <div class="step">Step 5 — Away from home</div>
        <h2>Tailnet (VPN)</h2>
        <p>Everything above only works from home wifi — unless you join the
        house VPN. Install the Tailscale app, but sign in against
        <b>our</b> server, not Tailscale's:</p>
        ${appRow [
          { name = "iPhone / iPad"; url = "https://apps.apple.com/us/app/tailscale/id1470499037"; }
          { name = "Android"; url = "https://play.google.com/store/apps/details?id=com.tailscale.ipn"; }
          { name = "Windows / macOS / Linux"; url = "https://tailscale.com/download"; }
        ]}
        <ul>
          <li><b>iPhone:</b> account icon → "Log in…" → options menu →
              <b>Use custom coordination server</b>, enter
              <code>https://${homelab.baseDomain}</code>, then use the
              auth key from your sheet (menu → "Use auth key")</li>
          <li><b>Android:</b> settings → Accounts → <b>Use an alternate
              server</b>, enter <code>https://${homelab.baseDomain}</code>,
              dismiss the login prompt, then Accounts → "Use an auth key"
              with the key from your sheet</li>
          <li><b>Laptop:</b> <code>tailscale up
              --login-server https://${homelab.baseDomain}
              --auth-key &lt;key from your sheet&gt;</code></li>
        </ul>
        <p class="muted">The key on your sheet works for 24&nbsp;h — ask the
        admin for a fresh one per extra device. Step-by-step per platform:
        <a href="https://headscale.net/stable/usage/connect/apple/">Apple
        devices</a> ·
        <a href="https://headscale.net/stable/usage/connect/android/">Android</a>.</p>
      </div>
    ''}

    <div class="card">
      <h2>Privacy, honestly</h2>
      <p class="muted">Your private share is protected from other members at
      two independent layers (file permissions + share auth). But the server
      admin can technically read anything on this box except your
      Vaultwarden vault — if you need admin-proof storage, put a
      client-side-encrypted vault (e.g. Cryptomator) inside your private
      share.</p>
    </div>
    </body>
    </html>
  '';
in
{
  options.homelab.services.welcome.enable = lib.mkEnableOption "the household onboarding welcome page";

  config = lib.mkIf cfg.enable {
    homelab.nginx.internal.${subdomain} = {
      root = page;
      dashboard = {
        name = "Welcome";
        description = "New here? Start here";
        icon = "mdi-hand-wave";
        category = "Household";
      };
    };
  };
}
