{
  # Per-node identity. networking.nix / routing.nix derive this node's IP,
  # router-id, etc. from the hostname; ZFS requires a UNIQUE hostId per machine.
  networking.hostName = "super-a";
  networking.hostId = "0a51a001";   # unique per node (8 hex) — required by ZFS
}
