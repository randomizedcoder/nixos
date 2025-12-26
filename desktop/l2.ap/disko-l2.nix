#
# nixos/desktop/l2
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
        device = "/dev/nvme0n1";
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
            #size = "10%"; # --vm-test
            size = "128G";
            content = {
              type ="swap";
              #discardPolicy = "both";
              resumeDevice = true; # resume from hiberation from this device
            };
          };
          root = {
            size = "90%";
            content = {
              type = "filesystem";
              format = "xfs";            # <---------- xfs!
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

# [das@l2:~]$ lsblk
# NAME                                          MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
# sda                                             8:0    1     0B  0 disk
# sdb                                             8:16   1     0B  0 disk
# sdc                                             8:32   1     0B  0 disk
# nvme0n1                                       259:0    0   1.9T  0 disk
# ├─nvme0n1p1                                   259:1    0   512M  0 part  /boot
# ├─nvme0n1p2                                   259:2    0   1.7T  0 part
# │ └─luks-6fd137fa-aa82-4200-9ca1-cd049de90418 254:0    0   1.7T  0 crypt /nix/store
# │                                                                        /
# └─nvme0n1p3                                   259:3    0 138.2G  0 part
# nvme1n1                                       259:4    0   1.8T  0 disk

# [das@l2:~]$