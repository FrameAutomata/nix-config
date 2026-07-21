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
          <li><b>Android:</b> a file manager with SMB support (e.g. CX File
              Explorer) → host <code>${homelab.baseDomain}</code></li>
        </ul>
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
      <ul>
        ${when services.jellyfin.enable ''
          <li><a href="${url "jellyfin"}">Jellyfin</a> — movies &amp; TV
              (apps for TV/phone: server <code>${url "jellyfin"}</code>)</li>
        ''}
        ${when services.jellyseerr.enable ''
          <li><a href="${url "requests"}">Requests</a> — ask for new movies
              or shows; they download automatically (sign in with your
              Jellyfin account)</li>
        ''}
        ${when services.navidrome.enable ''
          <li><a href="${url "music"}">Music</a> — the shared library
              (any Subsonic-compatible app works)</li>
        ''}
        ${when services.audiobookshelf.enable ''
          <li><a href="${url "abs"}">Audiobooks &amp; podcasts</a>
              (Audiobookshelf app on mobile)</li>
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
      </div>
    ''}

    ${when services.headscale.enable ''
      <div class="card">
        <div class="step">Step 5 — Away from home</div>
        <h2>Tailnet (VPN)</h2>
        <p>Everything above only works from home wifi — unless you join the
        house VPN. Install the Tailscale app, but sign in against
        <b>our</b> server, not Tailscale's:</p>
        <ul>
          <li><b>Phone:</b> in Tailscale's settings choose the alternate /
              custom coordination server, enter
              <code>https://${homelab.baseDomain}</code>, then use the
              auth key from your sheet (menu → "Use auth key")</li>
          <li><b>Laptop:</b> <code>tailscale up
              --login-server https://${homelab.baseDomain}
              --auth-key &lt;key from your sheet&gt;</code></li>
        </ul>
        <p class="muted">The key on your sheet works for 24&nbsp;h — ask the
        admin for a fresh one per extra device.</p>
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
