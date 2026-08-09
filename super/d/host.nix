{
  # The ONLY per-node .nix knob besides hardware-configuration.nix.
  # networking.nix / routing.nix derive this node's IP, router-id, etc. from the hostname.
  networking.hostName = "super-d";   # super-a | super-b | super-d
}
