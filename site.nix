# Facts shared by the server and the machines that use it. A plain attrset,
# not a module: the hosts are separate nixosSystem evals, so nothing else can
# stop them desyncing. Same reason keys.nix exists.
{
  baseDomain = "wheezertbts.duckdns.org";
  lanCIDR = "192.168.1.0/24";
  lanIP = "192.168.1.239";
  ntfySubdomain = "ntfy";
  ntfyTopic = "homelab";
  timeZone = "America/Chicago";
}
