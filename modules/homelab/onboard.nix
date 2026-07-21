# `homelab-onboard <handle>` — the admin half of member onboarding, run
# once per roommate AFTER adding the handle to homelab.household.members
# and rebuilding. Provisions everything only root can do (samba
# credential, FileBrowser account jailed to Private/<handle> — scope set
# atomically with creation, enforcing the scope-before-credentials rule
# by construction — and a headscale user + pre-auth key), then prints a
# one-page credential sheet. The welcome vhost (services/welcome.nix)
# guides the member through the rest themselves.
#
# Media-app accounts (Jellyfin/Navidrome/Audiobookshelf) stay manual:
# their admin API tokens only exist after each first-run wizard.
{ config, lib, pkgs, ... }:
let
  homelab = config.homelab;
  services = homelab.services;
  fb = config.services.filebrowser;

  script = pkgs.writeShellApplication {
    name = "homelab-onboard";
    runtimeInputs = [
      pkgs.jq
      pkgs.util-linux # runuser
      config.systemd.package
    ]
    ++ lib.optional services.samba.enable config.services.samba.package
    ++ lib.optional services.headscale.enable config.services.headscale.package;
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "run as root: sudo homelab-onboard <handle>" >&2
        exit 1
      fi
      if [ $# -ne 1 ]; then
        echo "usage: homelab-onboard <handle>" >&2
        exit 1
      fi
      handle="$1"

      if ! id "$handle" >/dev/null 2>&1 \
         || ! id -nG "$handle" | tr ' ' '\n' | grep -qx household; then
        echo "error: '$handle' is not a household member —" >&2
        echo "  add it to homelab.household.members and rebuild first" >&2
        exit 1
      fi

      genpw() { head -c 512 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20; }

      ${lib.optionalString services.samba.enable ''
        samba_pw="(already enrolled — unchanged)"
        if pdbedit -u "$handle" >/dev/null 2>&1; then
          echo "samba: $handle already enrolled, password unchanged" >&2
        else
          samba_pw="$(genpw)"
          printf '%s\n%s\n' "$samba_pw" "$samba_pw" | smbpasswd -s -a "$handle" >/dev/null
          echo "samba: enrolled $handle" >&2
        fi
      ''}

      ${lib.optionalString services.filebrowser.enable ''
        # the Bolt DB is single-writer, so the daemon pauses for the CLI;
        # the password briefly appears in local argv — fine on this box
        # (members are shell-less), never leaves the machine
        fb_pw="(already exists — unchanged)"
        systemctl stop filebrowser
        trap 'systemctl start filebrowser' EXIT
        fbcli() { runuser -u ${fb.user} -- ${lib.getExe fb.package} "$@" -d ${fb.settings.database}; }
        if fbcli users find "$handle" >/dev/null 2>&1; then
          echo "filebrowser: $handle already exists, unchanged" >&2
        else
          fb_pw="$(genpw)"
          fbcli users add "$handle" "$fb_pw" --scope "/Private/$handle" >/dev/null
          echo "filebrowser: created $handle jailed to Private/$handle" >&2
        fi
        systemctl start filebrowser
        trap - EXIT
      ''}

      ${lib.optionalString services.headscale.enable ''
        if ! headscale users list -o json \
             | jq -e --arg u "$handle" 'map(select(.name == $u)) | length > 0' >/dev/null; then
          headscale users create "$handle" >/dev/null
          echo "headscale: created user $handle" >&2
        fi
        hs_uid="$(headscale users list -o json \
          | jq -r --arg u "$handle" 'map(select(.name == $u)) | .[0].id')"
        hs_key="$(headscale preauthkeys create --user "$hs_uid" -e 24h -o json | jq -r '.key')"
        echo "headscale: pre-auth key issued (valid 24h)" >&2
      ''}

      cat <<SHEET

      ━━━ credential sheet — $handle ━━━━━━━━━━━━━━━━━━━━━━━━━━
      Start here:       https://welcome.${homelab.baseDomain}
      ${lib.optionalString services.samba.enable ''
      Network drive:    user $handle / $samba_pw''}
      ${lib.optionalString services.filebrowser.enable ''
      FileBrowser:      user $handle / $fb_pw''}
      ${lib.optionalString services.headscale.enable ''
      Tailnet key:      $hs_key''}
      ${lib.optionalString services.vaultwarden.enable ''
      Save everything in Vaultwarden (step 1 on the welcome page),
      then destroy this sheet.''}
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      SHEET

      ${lib.optionalString
        (services.jellyfin.enable || services.navidrome.enable || services.audiobookshelf.enable)
        ''echo "still manual: create '$handle' in the Jellyfin / Navidrome / Audiobookshelf admin UIs" >&2''}
    '';
  };
in
{
  config = lib.mkIf homelab.household.enable {
    environment.systemPackages = [ script ];
  };
}
