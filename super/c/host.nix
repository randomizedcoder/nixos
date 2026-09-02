{
  # Per-node identity. networking.nix / routing.nix derive this node's IP,
  # router-id, etc. from the hostname; ZFS requires a UNIQUE hostId per machine.
  networking.hostName = "super-c";
  networking.hostId = "0c53c003";   # unique per node (8 hex) — required by ZFS
}
