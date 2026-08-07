# home-ssh-config-nfb.nix
#
# SSH config for the NFB Consulting LADC network, reached through the nfb-vpn
# sandbox container (see desktop/l/nfb-vpn-sandbox.nix). Split out of
# home-ssh-config.nix so the NFB device/serial aliases live on their own.
#
# Contributes its Host blocks to `local.sshExtraConfig` (defined in
# home-ssh-config.nix). Bring the tunnel up first with:
#   expect ~/.ssh/nfb-vpn-connect.exp
# Device inventory + Opengear port map: ~/Downloads/nfb-ladc-asa01/.

{ config, pkgs, lib, ... }:

{
  local.sshExtraConfig = lib.mkAfter ''
    # -- NFB Consulting LADC VPN (see desktop/l/nfb-vpn-sandbox.nix) ----------
    # Jump into the nfb-vpn sandbox container over the host-container veth at
    # 10.98.0.2:22, then reach NFB devices through the openconnect tunnel.
    Host nfb-vpn
      Hostname 10.98.0.2
      User vpn
      IdentityFile ~/.ssh/id_ed25519
      StrictHostKeyChecking accept-new
      UserKnownHostsFile ~/.ssh/known_hosts.d/nfb-vpn
      ServerAliveInterval 30
      ControlMaster no
      ControlPath none

    # One ProxyJump rule for by-IP access AND every named alias below. ssh matches
    # Host patterns against the name typed on the command line (e.g. "con01"), not
    # the resolved Hostname, so the aliases must be listed here explicitly -- they do
    # NOT inherit the jump from the 10.201.10.* glob. Keep on ONE line (the login
    # heredoc is unquoted; a trailing backslash would be eaten by bash).
    Host 10.220.10.* 10.10.250.* 10.201.10.* 10.204.10.* 10.207.10.* 10.208.10.* 10.241.10.* con01 spine01 spine02 mgmt-lf01 lf03 lf07 lf08 fpr01 fpr02 super-a super-b super-c super-d a b c d nfb-ladc-* *-serial
      ProxyJump nfb-vpn

    # In-band mgmt IPs (from devices.txt).
    Host con01 nfb-ladc-con01
      Hostname 10.201.10.134
    Host spine01 nfb-ladc-spine01
      Hostname 10.201.10.14
    Host spine02 nfb-ladc-spine02
      Hostname 10.201.10.15
    Host mgmt-lf01 nfb-ladc-mgmt-lf01
      Hostname 10.201.10.30
    Host lf03 nfb-ladc-lf03
      Hostname 10.201.10.22
    Host lf07 nfb-ladc-lf07
      Hostname 10.201.10.26
    Host lf08 nfb-ladc-lf08
      Hostname 10.201.10.27
    Host fpr01 nfb-ladc-fpr01
      Hostname 10.201.10.12
    Host fpr02 nfb-ladc-fpr02
      Hostname 10.201.10.13

    # Supermicro server DATA ports (Dave's VLAN 401). Machine a/b/c/d = nodeA-D =
    # ~/nixos/super/<x>. BMC/IPMI is separate on the mgmt LAN (VLAN 201,
    # 10.201.10.87-90, paired by MAC -- NOT sequential to the letters) -- reach
    # those via "nix run .#sol -- a" or "nix run .#bmc" (web iKVM). Needs
    # 10.241.10.0/24 routed in the container. Data IPs are PLANNED (servers still
    # on DHCP). See ~/Downloads/nfb-ladc-asa01/dave-servers.md.
    Host super-a a
      Hostname 10.241.10.10
    Host super-b b
      Hostname 10.241.10.11
    Host super-c c
      Hostname 10.241.10.12
    Host super-d d
      Hostname 10.241.10.13

    # Opengear IM7248 serial lines: ssh <dev>-serial -> con01 TCP (3000+port).
    # Set User to the real Opengear account. Exit a serial session with ~. .
    Host *-serial
      Hostname 10.201.10.134
      User root
    Host fpr01-serial
      Port 3001
    Host fpr02-serial
      Port 3002
    Host spine01-serial
      Port 3003
    Host spine02-serial
      Port 3004
    Host mgmt-lf01-serial
      Port 3005
    Host mgmt-lf02-serial
      Port 3006
    Host asa01-serial
      Port 3009
    Host lf01-serial
      Port 3011
    Host lf02-serial
      Port 3012
    Host lf03-serial
      Port 3013
    Host lf04-serial
      Port 3014
    Host lf05-serial
      Port 3015
    Host lf06-serial
      Port 3016
    Host lf07-serial
      Port 3017
    Host lf08-serial
      Port 3018
  '';
}
