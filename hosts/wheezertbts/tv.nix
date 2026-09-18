# Living-room TV seat: the GTX 1650's HDMI port drives the TV, and this file
# turns that into "the box boots straight into Jellyfin". sway on tty1 as the
# locked user `tv`, running two Jellyfin clients — Jellyfin Desktop in its
# 10-foot layout for browsing, and jellyfin-mpv-shim as the HDR playback
# target a phone casts to.
#
# WHY SWAY AND NOT CAGE, which this was until 2026-09-17: cage cannot output
# HDR. Its source carries no colour-management or image-description code at
# all, so no client under it reaches PQ/BT2020 no matter what mpv is told.
# sway 1.12 enables HDR per output on the Vulkan renderer, and that is the
# link the README's spike called unproven on the proprietary NVIDIA driver.
# It was proven on this box first (595.71.05, GTX 1650): `swaymsg -t
# get_outputs` reported the output both HDR-capable and HDR-enabled, and a 4K
# HDR10 remux played correctly. Nothing here was written before that.
#
# WHY TWO CLIENTS: Jellyfin Desktop cannot output HDR either — its mpv is
# composited through Qt Quick (upstream #523, open since 2023; the branch that
# would have fixed it is abandoned and the CEF rewrite left the Jellyfin org).
# It stays because it is the only thing here that browses the library ON the
# TV and carries the Bonfire profile gate. mpv-shim adds a second, headless
# Jellyfin client that opens a window only when a phone casts to it, and that
# window is plain mpv with vo=gpu-next — the combination that does HDR.
#
# WHY HDR IS NOT SIMPLY LEFT ON: this TV's input carries 600 MHz (and only
# once Samsung's per-port "Input Signal Plus" is on — README). 10-bit 4K needs
# 371 MHz at 24/30 Hz but 743 MHz at 60 Hz, so an always-HDR seat would mean a
# 30 Hz user interface. Instead the seat idles at 4K60 SDR and mpv-shim's own
# event hooks drop the output to 4K24 + HDR for the length of a film. The
# hooks are synchronous and fire before playback starts (event_handler.py) and
# from both stop() and end-of-file, so every exit reverts.
#
# Host-local, and the reason is not "it registers with no homelab registry" —
# wireguard-netns registers with none either and is a first-class service
# module. It is that there is one TV. A modules/homelab/services/ module would
# have to parameterise the user, the clients, the sink ranking, the output
# name, both modes and the VT for zero second consumers, and would hand anyone
# who enabled it a unit that seizes tty1 and flips systemd.defaultUnit to
# graphical.target. NOT modules/workstation either: that is SDDM + Plasma +
# Steam for a person at a desk, and a live server roommates can now reach
# should not offer them a desktop to wander into.
#
# The operator runbook — first-run steps, the mpv-shim login that is not
# declarable, and what to try if the compositor will not start — is README,
# "Living-room TV". It is not repeated here.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # One TV, one output. `swaymsg -t get_outputs` names it, and the hooks below
  # address it explicitly rather than with `*` so a stray second sink (the
  # onboard HDA's own HDMI, if it ever appears) cannot be switched instead.
  tvOutput = "HDMI-A-1";
  # 4K60 for the browsing UI (594 MHz, 8-bit, inside the link's 600) and 4K24
  # for films (371 MHz at 10 bits, and the rate the material is mastered at).
  uiMode = "3840x2160@60Hz";
  filmMode = "3840x2160@24Hz";

  swaymsg = "${pkgs.sway}/bin/swaymsg";
  # `sleep` lets the TV finish re-syncing to the new mode before mpv maps its
  # window — a mode switch is not instant on the panel, and mpv reads the
  # output's colourimetry when it starts.
  toHdr = "${swaymsg} output ${tvOutput} mode ${filmMode}; ${swaymsg} output ${tvOutput} hdr on; ${pkgs.coreutils}/bin/sleep 1";
  toSdr = "${swaymsg} output ${tvOutput} hdr off; ${swaymsg} output ${tvOutput} mode ${uiMode}";

  # Both clients are started by the compositor, not by systemd: they are
  # Wayland clients of THIS session, and a separate unit would only have to
  # rediscover the socket. Every window goes fullscreen because sway tiles by
  # default, and a kiosk that splits the screen between the browser UI and the
  # film is not a kiosk; the newest window (mpv) lands on top and Jellyfin
  # Desktop is uncovered again when it closes.
  swayConfig = pkgs.writeText "tv-sway.conf" ''
    output ${tvOutput} mode ${uiMode}

    for_window [app_id=".*"] fullscreen enable
    for_window [class=".*"] fullscreen enable

    exec ${lib.getExe pkgs.jellyfin-mpv-shim}
    exec ${lib.getExe pkgs.jellyfin-desktop} --tv --fullscreen
  '';

  # mpv-shim passes this directory to libmpv as its config dir, so this is an
  # ordinary mpv.conf. vo=gpu-next is the half that can signal HDR at all;
  # target-colorspace-hint hands the source's PQ metadata to the compositor
  # instead of tone-mapping it away. nvdec keeps 10-bit HEVC off the CPU.
  mpvConf = pkgs.writeText "tv-mpv.conf" ''
    vo=gpu-next
    target-colorspace-hint=yes
    target-colorspace-hint-mode=source
    hwdec=nvdec
  '';

  # A PARTIAL settings file on purpose: mpv-shim validates what it finds and
  # leaves every key absent here at its own default, so this stays a statement
  # of what we mean rather than a copy of upstream's schema that would rot.
  # enable_gui=false is required, not cosmetic — with it true the shim imports
  # its tray and preferences window, which on a server with no X display take
  # the login prompt down with them.
  shimConf = (pkgs.formats.json { }).generate "tv-jellyfin-mpv-shim.json" {
    enable_gui = false;
    player_name = "Living Room TV";
    pre_media_cmd = toHdr;
    stop_cmd = toSdr;
    media_ended_cmd = toSdr;
  };
in

{
  # Imported here rather than from the host's default.nix so that deleting this
  # one file takes PipeWire back off the server with it: the TV seat is the
  # only thing on this box that wants sound.
  imports = [ ../../modules/common/audio.nix ];

  # The seat is a Jellyfin client of this same box, and nothing else ties the
  # two together — without this, turning the server off would leave the TV
  # booting to a server-address prompt with no build-time complaint.
  assertions = [
    {
      assertion = config.homelab.services.jellyfin.enable;
      message = "hosts/wheezertbts/tv.nix: the living-room TV is a Jellyfin client of this host — enable homelab.services.jellyfin, or drop the ./tv.nix import";
    }
  ];

  # Modelled on the cage module's own unit (services/wayland/cage.nix), which
  # this replaces: same ordering, same VT handling, same getty conflict. What
  # changes is the compositor and that the clients come from the config file.
  systemd.services.tv-seat = {
    enable = true;
    after = [
      "systemd-user-sessions.service"
      "systemd-logind.service"
      "getty@tty1.service"
    ];
    before = [ "graphical.target" ];
    wants = [
      "dbus.socket"
      "systemd-logind.service"
    ];
    wantedBy = [ "graphical.target" ];
    conflicts = [ "getty@tty1.service" ];

    # A switch never kills a viewing session. New clients arrive with
    # `systemctl restart tv-seat` (when nobody is watching) or the next reboot.
    restartIfChanged = false;
    unitConfig.ConditionPathExists = "/dev/tty1";

    # The start limit is the other half of Restart=always: without it a broken
    # seat retries forever, the unit never reaches `failed`, and the ntfy hook
    # below never fires — a dead TV stays silent. systemd gives a RATE limit,
    # not a total, so the window has to be wide enough to catch a SLOW flap:
    # at ten tries an hour, anything dying faster than once every six minutes
    # trips it, while a person quitting the app a few times does not.
    startLimitIntervalSec = 3600;
    startLimitBurst = 10;

    # sway spawns swaynag and swaymsg BY NAME, and mpv-shim's HDR hooks shell
    # out to swaymsg the same way. `path` rather than an environment override
    # because NixOS composes this with systemd's own minimal default
    # (coreutils, findutils, gnugrep, gnused, systemd) instead of replacing
    # it — setting environment.PATH directly collides with that and needs a
    # mkForce to win, which would also drop the default.
    path = [ pkgs.sway ];

    environment = {
      # wlroots' Vulkan renderer is what carries HDR; the GLES2 default does
      # not implement output colour transforms, and sway then refuses `hdr on`
      # with "renderer doesn't support output color transforms".
      WLR_RENDERER = "vulkan";
      # wlroots refuses to start with zero input devices, and this box normally
      # boots with no keyboard attached — the phone is the remote.
      WLR_LIBINPUT_NO_DEVICES = "1";
      # Qt's default on Linux is xcb, which here would mean sway's XWayland —
      # one layer more than video wants. (Jellyfin Desktop still starts
      # XWayland on its own: its Linux display-mode helper opens an X
      # connection for XRandR. Harmless; the window itself stays Wayland.)
      QT_QPA_PLATFORM = "wayland";
    };

    serviceConfig = {
      # Refreshed on every start so the repo, not /home/tv, is the source of
      # truth. Runs as `tv` (User= applies to ExecStartPre too), and touches
      # only these two names — cred.json sits beside them and is the one piece
      # of this seat that cannot be declared: it is written by an interactive
      # login (README).
      ExecStartPre = [
        "${pkgs.coreutils}/bin/install -Dm0644 ${shimConf} /home/tv/.config/jellyfin-mpv-shim/conf.json"
        "${pkgs.coreutils}/bin/install -Dm0644 ${mpvConf} /home/tv/.config/jellyfin-mpv-shim/mpv.conf"
      ];
      ExecStart = "${lib.getExe pkgs.sway} -c ${swayConfig}";
      User = "tv";

      Restart = "always";
      RestartSec = "5s";

      IgnoreSIGPIPE = "no";

      # Log this user with utmp, letting it show up with 'w' and 'who'. Needed
      # since this replaces (a)getty on tty1.
      UtmpIdentifier = "%n";
      UtmpMode = "user";
      # A virtual terminal is needed, and the seat must fail rather than run
      # blind if something else already holds it.
      TTYPath = "/dev/tty1";
      TTYReset = "yes";
      TTYVHangup = "yes";
      TTYVTDisallocate = "yes";
      StandardInput = "tty-fail";
      StandardOutput = "journal";
      StandardError = "journal";
      # Opens a full login session for `tv`, which is what gives the
      # compositor its seat (logind) and the user its runtime dir.
      PAMName = "tv-seat";
    };
  };

  # The PAM service the unit names. cage shipped its own; replacing cage means
  # replacing that too. allowNullPassword is the point: `tv` has no password
  # and must not acquire one (see users.users.tv below).
  security.pam.services.tv-seat = {
    allowNullPassword = true;
    startSession = true;
  };

  # All three were defaults the cage module set for us and the seat still
  # needs: a graphical default target so the TV comes up at boot, the GPU
  # userspace, and polkit for the logind session.
  systemd.defaultUnit = "graphical.target";
  systemd.targets.graphical.wants = [ "tv-seat.service" ];
  hardware.graphics.enable = true;
  security.polkit.enable = true;

  # ...and once it has given up, say so. A dead TV is otherwise silent: nobody
  # opens an ssh session to check on a television, so the failure would reach
  # Thomas as a roommate's complaint. Same registry the scrub and the backups
  # use, registered from a host-local file exactly as filesystems.nix does.
  homelab.services.ntfy.notifyOnFailure = [ "tv-seat" ];

  # Owner of the seat and nothing more: no password (PAMName= opens a session
  # without authenticating, so a locked account is exactly right), no keys, no
  # media/household/wheel, not a household member. The Jellyfin logins it
  # holds — Jellyfin Desktop's and mpv-shim's cred.json — are a separate
  # non-admin account with its own password (README). Do NOT `passwd tv`. The
  # name is reserved in modules/homelab/household.nix so a roommate handle
  # cannot collide with it.
  users.users.tv = {
    isNormalUser = true;
    description = "Living-room TV";
    # nologin. isNormalUser would otherwise hand it the default login shell,
    # and nothing here needs one — the unit execs sway directly.
    shell = pkgs.shadow;
  };

  # A server has zero fonts (fonts.enableDefaultPackages defaults to false),
  # and a web client with no fonts renders as boxes. Kept beyond the web UI's
  # own bundled woff2 files because mpv's libass resolves subtitle fonts
  # through fontconfig and has no bundled fallback.
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
  ];

  # Two sound cards — the onboard Intel HDA and the GPU's HDMI audio — and no
  # desktop to pick between them. Rank every HDMI sink above the analog
  # default so the TV wins. The HDMI node only exists while the TV is on; if
  # the Intel HDA turns out to expose an HDMI sink of its own, both match —
  # confirm the node name with `wpctl status` as the tv user and narrow this.
  services.pipewire.wireplumber.extraConfig."51-tv-hdmi-default" = {
    "monitor.alsa.rules" = [
      {
        matches = [ { "node.name" = "~alsa_output.*hdmi.*"; } ];
        actions.update-props."priority.session" = 2000;
      }
    ];
  };

  # Roommates are within reach of the box now. A stray press on its power
  # button must not shut down the server: logind ignores it, the TV's own
  # remote is the off switch, and the server is administered over ssh.
  services.logind.settings.Login.HandlePowerKey = "ignore";
}
