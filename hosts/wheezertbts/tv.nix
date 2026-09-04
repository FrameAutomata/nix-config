# Living-room TV seat: the GTX 1650's HDMI port drives the TV, and this file
# turns that into "the box boots straight into Jellyfin". cage — a Wayland
# compositor that shows exactly one window — on tty1, running Jellyfin Desktop
# in its 10-foot layout as a dedicated locked user.
#
# Host-local, and the reason is not "it registers with no homelab registry" —
# wireguard-netns registers with none either and is a first-class service
# module. It is that there is one TV. A modules/homelab/services/ module would
# have to parameterise the user, the program, the sink ranking and the VT for
# zero second consumers, and would hand anyone who enabled it a unit that
# seizes tty1 and flips systemd.defaultUnit to graphical.target. NOT
# modules/workstation either: that is SDDM + Plasma + Steam for a person at a
# desk, and a live server roommates can now reach should not offer them a
# desktop to wander into.
#
# The "Who's watching?" profiles are the Bonfire (JellyProfiles) plugin,
# installed in Jellyfin's dashboard — plugin state, not declarable. It works
# here because Jellyfin Desktop loads the web client FROM THE SERVER (its
# bundled page is only a server-address prompt), so a script the server injects
# into that client shows up on the TV exactly as it does in a browser. It also
# means the TV is an ordinary Jellyfin session that a phone's "Play on" can
# drive — a remote control with no hardware.
#
# The operator runbook — first-run steps, and the ordered list of knobs to try
# if the compositor will not start on this driver — is README, "Living-room
# TV". It is not repeated here.
{
  config,
  lib,
  pkgs,
  ...
}:

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

  services.cage = {
    enable = true;
    user = "tv";
    # cage runs one executable, so the flags need a wrapper; the environment
    # does not, hence `environment` below rather than exports in here.
    program = pkgs.writeShellScript "tv-session" ''
      exec ${lib.getExe pkgs.jellyfin-desktop} --tv --fullscreen
    '';
    # -s allows VT switching, so a keyboard plugged into the box still reaches
    # a console (Ctrl+Alt+F2 — getty leaves tty1 to cage). Not the hardened
    # kiosk default on purpose: this is a server first and a TV second.
    extraArguments = [ "-s" ];
    # Rendered as the unit's Environment=, so it is set before exec and cage's
    # child inherits it.
    environment = {
      # wlroots refuses to start with zero input devices, and this box normally
      # boots with no keyboard attached — the phone's "Play on" is the remote.
      WLR_LIBINPUT_NO_DEVICES = "1";
      # Qt's default on Linux is xcb, which here would mean cage's XWayland —
      # one layer more than video wants. Nothing else is needed: in this
      # nixpkgs the Wayland platform plugin lives in qtbase's own
      # plugins/platforms, already on the path the package's wrapper sets.
      QT_QPA_PLATFORM = "wayland";
    };
  };

  # An app exit or crash relaunches straight into Jellyfin. The module's own
  # restartIfChanged = false stays in force: a switch never kills a viewing
  # session, so a new jellyfin-desktop only arrives with
  # `systemctl restart cage-tty1` (when nobody is watching) or the next reboot.
  #
  # The start limit is the other half of Restart=always: without it a broken
  # kiosk retries forever, the unit never reaches `failed`, and the ntfy hook
  # below never fires — a dead TV stays silent. Note what systemd gives us is a
  # RATE limit, not a total, so the window has to be wide enough to catch a
  # SLOW flap: at ten tries an hour, anything dying faster than once every six
  # minutes trips it, while a person quitting the app a few times does not.
  # (A 5-minute window would only have caught instant crashes — a kiosk dying
  # after ~40s each time would have outrun it and looped forever.)
  #
  # Bounding the retries is safe here because the TV powering off does NOT
  # kill cage: cage only self-terminates on losing its last output when it is
  # nested inside another compositor (output.c, `was_nested_output`), and on
  # this box it owns the DRM backend directly.
  #
  # Once it does give up, `systemctl reset-failed cage-tty1` then `start` is
  # the un-stick — README, "Living-room TV".
  systemd.services.cage-tty1 = {
    startLimitIntervalSec = 3600;
    startLimitBurst = 10;
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # ...and once it has given up, say so. A dead TV is otherwise silent: nobody
  # opens an ssh session to check on a television, so the failure would reach
  # Thomas as a roommate's complaint. Same registry the scrub and the backups
  # use, registered from a host-local file exactly as filesystems.nix does.
  homelab.services.ntfy.notifyOnFailure = [ "cage-tty1" ];

  # Owner of the seat and nothing more: no password (cage's PAMName= opens a
  # session without authenticating, so a locked account is exactly right), no
  # keys, no media/household/wheel, not a household member. The Jellyfin login
  # it holds is a separate non-admin account with its own password (README).
  # Do NOT `passwd tv`. The name is reserved in modules/homelab/household.nix
  # so a roommate handle cannot collide with it.
  users.users.tv = {
    isNormalUser = true;
    description = "Living-room TV";
    # nologin. isNormalUser would otherwise hand it the default login shell,
    # and nothing here needs one — cage execs the program directly.
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
