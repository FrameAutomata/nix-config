# Surfshark as a NetworkManager WireGuard profile, so the profile is the
# toggle: every workstation user is in the networkmanager group, and the NM
# module's polkit rule lets that group bring it up and down without a password.
#
# Not the official app: nixpkgs carries no Surfshark package, so that is a
# closed-source Electron .deb to repackage and keep moving. The server already
# runs Surfshark's manual WireGuard (modules/homelab/services/wireguard-netns.nix)
# and this is the same thing on a machine with a desktop.
#
# Not `nmcli connection import` of the .conf the dashboard hands out, either:
# that file is `AllowedIPs = 0.0.0.0/0` and nothing else, which on a
# dual-stack network leaves IPv6 going out the Wi-Fi with the tunnel "up".
# The [ipv6] block below is the difference.
#
# Coexists with the tailnet rather than swallowing it: NM puts its two
# full-tunnel rules at priority 30766-31766, behind Tailscale's 5210-5270, so
# tailnet peers and accepted subnet routes still resolve to tailscale0 and
# tailscaled's own fwmarked packets still leave by the physical NIC. DNS
# follows from the same ordering: tailscaled registers with resolvconf as
# exclusive, so while the tailnet is up names keep resolving through AdGuard
# at home, and Surfshark's resolvers below only take over when it is not.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Dallas, like the server's tunnel. A location is this PAIR: the `pubKey`
  # beside the matching `connectionName` in
  # https://api.surfshark.com/v4/server/clusters/generic, and the `PublicKey`
  # in the .conf the dashboard hands out for it.
  endpoint = "us-dal.prod.surfshark.com:51820";
  publicKey = "0iwHQpV+rsOg38ogv4g4XMLJa51YqWY/yKWR9UEUMDk=";
in
{
  options.surfshark.environmentFile = lib.mkOption {
    # `str`, not `path`: a path literal here would copy the key into the
    # world-readable store. Same reason homelabClient.mounts.credentialsFile is.
    #
    # No default, so a host states where its key comes from: one with an
    # agenix identity cannot end up on a hand-placed file by omission.
    type = lib.types.str;
    example = "/etc/surfshark/wireguard.env";
    description = ''
      Root-only file holding one line, `SURFSHARK_PRIVATE_KEY=<base64>`: this
      machine's WireGuard private key, whose public half is registered in the
      Surfshark dashboard. One key pair PER MACHINE — two machines sharing one
      fight over the same peer slot on the server, and a lost laptop is then
      revoked by deleting its key alone.

      A hand-placed file on a host with no agenix identity; the decrypted
      secret's path on a host that has one.
    '';
  };

  config = {
    # NM drives the kernel module directly and needs none of this. It is here
    # for `sudo wg show surfshark`, whose "latest handshake" line is the only
    # proof the far end answered.
    environment.systemPackages = [ pkgs.wireguard-tools ];

    # envsubst renders an unset variable as an empty key and exits 0, so a file
    # that exists but misnames the variable would leave a profile that can
    # never connect behind a green unit.
    systemd.services.NetworkManager-ensure-profiles.preStart = ''
      if [ -z "''${SURFSHARK_PRIVATE_KEY:-}" ]; then
        echo "${config.surfshark.environmentFile} does not define SURFSHARK_PRIVATE_KEY" >&2
        exit 1
      fi
    '';

    networking.networkmanager.ensureProfiles = {
      # A missing file FAILS the unit too ("Failed to load environment
      # files"), and that is left hard on purpose. The unit is upstream's and
      # writes every profile a host declares, so it takes those down with it.
      environmentFiles = [ config.surfshark.environmentFile ];

      # Rendered to /run on every boot and switch. Do not edit it in Plasma's
      # connection editor: NM then saves a copy under /etc that shadows this
      # one for good, and later changes here stop arriving.
      profiles.surfshark = {
        connection = {
          id = "Surfshark";
          # Pinned rather than left for NM to derive from the file name: NM
          # seeds the tunnel's fwmark, routing table and rule priority from it.
          uuid = "c54fb16b-2888-486e-a6b3-4eec594092bb";
          type = "wireguard";
          interface-name = "surfshark";
          autoconnect = false;
        };

        # In the profile, not agent-owned in KWallet: plasma-nm's secret agent
        # hands back whatever it has for a WireGuard profile and never opens a
        # prompt, so a key left to the agent has no way in.
        wireguard.private-key = "$SURFSHARK_PRIVATE_KEY";

        "wireguard-peer.${publicKey}" = {
          inherit endpoint;
          # v4 only, as Surfshark serves it. The /0 is what makes NM build
          # the policy-routed default route; the LAN stays reachable beside it.
          allowed-ips = "0.0.0.0/0;";
        };

        ipv4 = {
          method = "manual";
          # The same address for every Surfshark customer; the key is what
          # tells them apart. The server's netns states the same pair.
          address1 = "10.14.0.2/16";
          dns = "162.252.172.57;149.154.159.92;";
          # Negative = exclusive: the Wi-Fi's own resolver drops out of
          # resolv.conf while the tunnel is up, instead of being asked first.
          dns-priority = -50;
        };

        # Surfshark carries no IPv6, so v6 has to be refused, not tunnelled:
        # an unreachable default that exists only while the profile is up.
        # Each alternative was run and is worse — `::/0` in allowed-ips with
        # v6 disabled here installs no route at all and LEAKS; `::/0` with a
        # made-up address blackholes, so every v6 connect waits out its
        # timeout where this fails at once and falls back to v4.
        ipv6 = {
          # Routes need v6 alive on the interface; a link-local address is
          # the least that keeps it so. stable-privacy because a keyfile
          # defaults to eui64, WireGuard has no MAC to derive one from, and
          # NM then logs a warning every ten seconds while the tunnel is up.
          method = "link-local";
          addr-gen-mode = "stable-privacy";
          # Metric 1 so no interface's own default (NM: 100 wired, 600 Wi-Fi)
          # can undercut it.
          route1 = "::/0,::,1";
          route1_options = "type=unreachable";
        };
      };
    };
  };
}
