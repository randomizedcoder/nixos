{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix   # per-node (disks, kernel modules)
    ./host.nix                     # per-node hostname
    ./networking.nix               # LACP bond0 + VLAN401 (bond0.401), keyed off hostname
    ./routing.nix                  # BIRD BGP/ECMP/RTBH + multipath fallback default
    ./sysctl.nix                   # kernel network/TCP tuning (synced from desktop/l)
    ./nix-settings.nix             # nix daemon tuning + GC (auto-optimise, cores, gc)
    ./cpu-tuning.nix               # CPU core dedication: isolcpus + systemd slices + numa (tuning.md)
    ./nic-tune.nix                 # ixgbe channels/rings + NIC-IRQ pinning (tuning.md)
    ./nginx-anycast.nix            # TEMP: anycast smoke-test (nginx on 160.72.197.238, self-signed)
    ./firewall.nix                 # nftables host firewall: default-drop + ASA-matrix services + SSH knock + WG plumbing
    ./bogon-refresh.nix            # fills firewall.nix bogon sets from Team-Cymru (weekly timer)
    ./monitoring.nix               # diagnostic/monitoring tools (netstat, ifconfig, btop) + monitoring svc
  ];

  # Serial console over IPMI SOL (ttyS1) + local VGA. systemd auto-starts
  # serial-getty@ttyS1 from this.
  boot.kernelParams = [ "console=tty0" "console=ttyS1,115200" ];

  # Bootloader (UEFI).
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 15;   # keep the last 15 generations in the boot menu
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "America/Los_Angeles";
  services.timesyncd.enable = true;

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  users.users.das = {
    isNormalUser = true;
    description = "das";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  nixpkgs.config.allowUnfree = true;


  environment.systemPackages = with pkgs; [
    # shell ergonomics
    vim
    gnumake          # `make` — run the node's Makefile targets (make local / make dns)
    psmisc           # killall, pstree, fuser
    git
    # network debug
    curl
    wget
    iproute2         # ip, ss  (basic IP utilities)
    tcpdump
    ethtool          # NIC / bond diagnostics
    pciutils         # lspci
    usbutils         # lsusb
    nftables
    # storage controller (megaraid_sas on these SYS-2028TP nodes). NOTE: storcli, NOT
    # storcli2 — these are older LSI/MegaRAID cards; storcli2 is only for newer tri-mode
    # controllers.
    storcli
    # (birdc comes from services.bird; lldpctl from services.lldpd)
  ];

  services.openssh.enable = true;

  # Node lives behind the ASA/fabric; host firewall off (matches the current live config).
  networking.firewall.enable = false;

  # Keep at the release the nodes were first installed from — do NOT bump casually.
  system.stateVersion = "25.05";
}
