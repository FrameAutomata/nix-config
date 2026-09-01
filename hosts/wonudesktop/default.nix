# The repurposed AM4 desktop — Ryzen 7 5800X3D, RTX 2070 Super — running as
# someone else's daily driver. That is the fact that shapes this file: every
# other host in this repo is administered by the person sitting at it, and
# this one is not. Where a choice trades a little of Thomas's convenience for
# a machine that does not surprise its user, it is made that way here and the
# reason is written down.
{ config, pkgs, ... }:

let
  site = import ../../site.nix;
  keys = import ../../keys.nix;
in

{
  imports = [
    ./hardware-configuration.nix
    ./gpu.nix
    ../../modules/common
    ../../modules/common/nvidia.nix
    ../../modules/workstation
    ../../modules/homelab-client
  ];
  # No modules/workstation/dev-tools.nix: that is the editors/CLI/release-check layer
  # for the machines this repo is deployed from, and none of it is this user's.

  networking.hostName = "wonudesktop";
  time.timeZone = site.timeZone;

  # NOT linuxPackages_latest, which both of Thomas's machines run. Their GPUs
  # are driven by in-tree drivers, so tracking mainline is free there. Here the
  # NVIDIA kernel module is an out-of-tree build that has to catch up to each
  # kernel release, and the window where it has not is a machine that boots to
  # a black screen. pkgs.linuxPackages is the kernel nixpkgs builds the driver
  # against by default (6.18 here, against 7.2 for _latest).
  boot.kernelPackages = pkgs.linuxPackages;

  # Named for the person, not the host — the convention everywhere else in this
  # repo (user == hostname) exists because those accounts are all Thomas's.
  # CHECK THIS BEFORE THE INSTALL: a username is painful to change afterwards
  # (it owns the home directory, the Steam library and the Plasma config), and
  # if this person later gets a homelab share it is least confusing when the
  # handle here matches their homelab.household.members handle.
  #
  # wheel is not a formality: polkit's "administrator" identity on NixOS IS the
  # wheel group, so without it Plasma's own prompts — add a printer, set the
  # clock, install a Flatpak system-wide — fail with no path forward for the
  # person at the keyboard.
  users.users.wonu = {
    isNormalUser = true;
    description = "Wonu"; # GECOS, shown on the SDDM login screen
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # Thomas's account, for remote support. It exists because the support path
  # this repo has relied on so far ("walk over to the machine") does not apply
  # to a computer somebody else is using, and because their password is theirs
  # to change without breaking his access. Key-only: sshd below refuses
  # passwords, so this account is unreachable except through the admin key in
  # keys.nix. It still needs a password set once at install, for sudo (README).
  users.users.admin = {
    isNormalUser = true;
    description = "Thomas (remote support)";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.admin ];
  };

  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };

  # modules/common runs sshd and leaves reachability to the consuming host.
  # This is the first workstation in the estate that actually opens it, and it
  # opens on tailscale0 ONLY: the tailscale module does not add its interface
  # to trustedInterfaces, so nothing here is implied by having the tailnet up,
  # and :22 never appears on the LAN or on the wire this box is plugged into.
  # Derived from services.openssh.ports rather than hardcoded [ 22 ], the same
  # way hosts/wheezertbts does it, so a moved port cannot silently desync.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = config.services.openssh.ports;

  # Pin the apex to the LAN IP. A client not yet on the tailnet cannot use
  # AdGuard's split DNS, so it resolves this to the WAN address and depends on
  # router hairpin NAT — which is what hangs `tailscale up` on a first join.
  # The other three hosts pin the same name.
  networking.extraHosts = "${site.lanIP} ${site.baseDomain}";

  # Tailnet + ntfy failure alerts. The alerts are the point on this host: a
  # weekly upgrade that dies here has nobody watching a journal, so it pushes
  # to the same "homelab" topic Thomas already gets the server's failures on.
  #
  # No mounts. This host has no key in keys.nix, so it cannot decrypt a
  # samba-client secret of its own the way frame-automata does; enrolling one
  # is what that would take, and it is also what would give this machine a
  # place to keep documents that is backed up. See the README.
  homelabClient = {
    enable = true;
    notifyOnFailure = [ "nixos-upgrade" ];
  };

  # Compressed swap in RAM, and no swap partition or swapfile: this box is not
  # asked to hibernate, so the expensive kind of swap buys nothing here. What
  # it does buy is that a game or a browser session that overshoots RAM gets
  # its cold pages compressed (~3:1) instead of handing someone an OOM kill in
  # the middle of what they were doing.
  zramSwap.enable = true;

  # The escape hatch from "ask Thomas to add a package". Turning this on is
  # what makes Plasma ship Discover (its PackageKit backend has no Nix support,
  # so upstream only installs the store when flatpak or fwupd is enabled), and
  # the plasma6 module already enables the xdg portals flatpak asserts on.
  #
  # The trade, stated plainly: apps installed this way are NOT declarative and
  # NOT in this repo. They live in /var/lib/flatpak, survive rebuilds and
  # upgrades, and are the user's to manage. On a machine whose user cannot be
  # expected to open a pull request to get Spotify, that is the right trade —
  # the alternative is not a tidier config, it is a person who cannot install
  # anything.
  services.flatpak.enable = true;

  # Flatpak has no NixOS option for remotes, so the one thing a fresh install
  # needs — knowing where apps come from — has to be a unit. --if-not-exists
  # makes it idempotent, so it is a no-op on every boot after the first.
  #
  # Deliberately NOT ordered after network-online.target: that target is on the
  # path to multi-user.target and therefore to the login screen, so a slow or
  # absent network would delay SDDM to buy a remote nobody is waiting for.
  # Instead it fails fast without a network and retries on a timer, capped so a
  # permanently unreachable Flathub cannot spin in the journal forever. The
  # next boot tries again either way.
  systemd.services.flathub-remote = {
    description = "Register the Flathub remote for system Flatpak installs";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
    };
    unitConfig = {
      StartLimitIntervalSec = "1h";
      StartLimitBurst = 5;
    };
    script = ''
      flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };

  # This machine opens documents written on Windows and macOS. Without
  # metric-compatible substitutes a .docx laid out in Arial or Calibri reflows
  # — different line breaks, a different page count — which reads as "Linux
  # broke my document". These three are the substitutes that matter:
  # liberation_ttf for Arial/Times/Courier, carlito for Calibri and caladea
  # for Cambria (the Office defaults since 2007). Noto covers the rest of the
  # web, colour emoji included.
  #
  # Not corefonts (the real Arial/Times/Verdana): it is an unfree fetch of
  # Microsoft's old .exe bundles that cache.nixos.org cannot redistribute, so
  # it builds locally off SourceForge every time it is not already in the
  # store — a weekly unattended upgrade is a bad place to depend on that. The
  # metric substitutes above fix the layout, which is the part that matters.
  fonts.packages = with pkgs; [
    liberation_ttf
    carlito
    caladea
    noto-fonts
    noto-fonts-color-emoji
  ];

  # Printing, because "productivity machine" eventually means a printer.
  # Driverless (IPP Everywhere / AirPrint) covers most printers made in the
  # last decade and finds them over mDNS, which is what avahi + nssmdns4 are
  # for; Plasma adds its print-manager KCM by itself once printing is enabled.
  # An older USB-only printer may still want its driver in
  # services.printing.drivers (pkgs.gutenprint, pkgs.hplip, ...).
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    # This puts UDP 5353 in the GLOBAL allowedUDPPorts, so mDNS answers on
    # tailscale0 too. Same trade modules/workstation already makes for the
    # Steam ports, and the tailnet is household devices.
    openFirewall = true;
  };

  # Windows and macOS both open files on double-click; Plasma opens on single
  # click. For someone carrying that muscle memory it reads as the machine
  # doing things at random, and it is the first thing they hit, in the file
  # manager, on day one.
  #
  # /etc/xdg is the system layer of KConfig's search path, so this is a
  # DEFAULT and not a lock: the moment they touch the setting in System
  # Settings, ~/.config/kdeglobals wins and this stops mattering. That is the
  # only reason it is acceptable to state a personal preference in a system
  # config — this repo runs no home-manager, so the alternative is nothing.
  environment.etc."xdg/kdeglobals".text = ''
    [KDE]
    SingleClick=false
  '';

  # This host's own apps; the shared interactive set is in modules/workstation
  # (Plasma, Steam, gamemode, MangoHud, browsers, LibreOffice).
  environment.systemPackages = with pkgs; [
    # The two launchers that cover what Steam does not: Heroic for Epic/GOG/
    # Amazon libraries, Lutris for everything else — standalone installers,
    # emulators, old Windows games.
    heroic
    lutris
    # Installs GE-Proton into Steam and Heroic. Swapping the Proton version is
    # the fix for a game that will not launch about as often as anything else,
    # and doing it by hand means unpacking a tarball into a dot-directory.
    protonup-qt
    vlc
  ];

  # Weekly update from whatever is committed, so deploying is pushing — with
  # one difference from the other two hosts: "boot", not "switch".
  #
  # A switch that lands a new NVIDIA release swaps the userspace libraries
  # under a running session while the loaded kernel module stays at the old
  # version, and nothing can open a GL context until a reboot. On Thomas's
  # machines that is a recognisable annoyance he can name; here it is a
  # computer that broke itself mid-afternoon with nobody to explain why.
  # Applying at the next boot costs a desktop nothing.
  #
  # NOTE this resolves against the DEFAULT BRANCH, so this host's config has
  # to be merged before the weekly upgrade can find it.
  system.autoUpgrade = {
    enable = true;
    flake = "github:FrameAutomata/nix-config#wonudesktop";
    operation = "boot";
    upgrade = false;
    dates = "Mon 02:00";
    persistent = true;
    randomizedDelaySec = "45min";
    allowReboot = false;
  };

  system.stateVersion = "26.05"; # never change this
}
