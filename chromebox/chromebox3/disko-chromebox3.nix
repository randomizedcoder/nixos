#
# nixos/chromebox/chromebox3
#
# Starting point was:
# https://github.com/nix-community/disko/blob/master/example/lvm-sizes-sort.nix
#
# swap
# https://github.com/nix-community/disko/blob/master/example/swap.nix
#
# tmpfs
# https://github.com/nix-community/disko/blob/master/example/tmpfs.nix
#
# Other templates
# https://github.com/nix-community/disko-templates/blob/main/zfs-impermanence/disko-config.nix

{
  disko.devices = {
    disk = {
      one = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
            };
            ESP = {
              name = "ESP";
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            primary = {
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "pool";
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      pool = {
        type = "lvm_vg";
        lvs = {
          swap = {
            type ="swap";
            size = "32G";
            discardPolicy = "both";
            resumeDevice = true; # resume from hiberation from this device
          };
          atsCache = {
            size = "100G";
          };
          sftp = {
            size = "20G";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/tftp";
              mountOptions = [ "defaults" ];
            };
          };
          root = {
            end = "100%";
            content = {
              type = "filesystem";
              format = "xfs"; # <---------- xfs!
              mountpoint = "/";
              mountOptions = [ "defaults" ];
              #mountOptions = [ "defaults" "pquota" ];
            };
          };
        };
      };
    };
    # nodev = {
    #   "/tmp" = {
    #     fsType = "tmpfs";
    #     mountOptions = [ "size=200M" ];
    #   };
    # };
  };
}