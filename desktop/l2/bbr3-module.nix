#
# bbr3-module.nix
#
# Build BBRv3 congestion control from L4S kernel source as out-of-tree module
# Source: https://github.com/L4STeam/linux
#
# BBRv3 is an improved version of BBR with better fairness and L4S awareness
#

{ config, lib, pkgs, ... }:

let
  kernel = config.boot.kernelPackages.kernel;

  # L4S repo commit (testing branch)
  l4sRev = "48b3db6b4a7fd57e2d31db3bb46a3bc6af7bf3ad";

  # BBRv3 module built from L4S kernel source
  bbr3Module = pkgs.stdenv.mkDerivation rec {
    pname = "tcp-bbr3";
    version = "3.0-${kernel.version}";

    src = pkgs.fetchFromGitHub {
      owner = "L4STeam";
      repo = "linux";
      rev = l4sRev;
      hash = "sha256-fqv0xKajFFaVpDuN2B13BpeS6dkjObqAPCEVkJXYN6Q=";
    };

    nativeBuildInputs = kernel.moduleBuildDependencies;

    hardeningDisable = [ "pic" "format" ];

    makeFlags = kernel.makeFlags ++ [
      "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "M=$(PWD)"
    ];

    preBuild = ''
      # Copy BBRv3 source to build directory
      cp ${src}/net/ipv4/tcp_bbr.c tcp_bbr3.c

      # Rename the module to avoid conflict with in-kernel tcp_bbr
      sed -i 's/tcp_bbr_cong_ops/tcp_bbr3_cong_ops/g' tcp_bbr3.c
      sed -i 's/bbr_register/bbr3_register/g' tcp_bbr3.c
      sed -i 's/bbr_unregister/bbr3_unregister/g' tcp_bbr3.c
      sed -i 's/MODULE_DESCRIPTION("TCP BBR/MODULE_DESCRIPTION("TCP BBRv3/g' tcp_bbr3.c

      # Change the registered name to "bbr3"
      sed -i 's/\.name.*=.*"bbr"/.name = "bbr3"/g' tcp_bbr3.c

      # Create Makefile for out-of-tree build
      cat > Makefile <<EOF
      obj-m := tcp_bbr3.o

      all:
      	\$(MAKE) -C \$(KDIR) M=\$(PWD) modules

      clean:
      	\$(MAKE) -C \$(KDIR) M=\$(PWD) clean
      EOF
    '';

    buildPhase = ''
      runHook preBuild
      make KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) modules
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
      cp tcp_bbr3.ko $out/lib/modules/${kernel.modDirVersion}/extra/
      runHook postInstall
    '';

    meta = with lib; {
      description = "TCP BBRv3 - Bottleneck Bandwidth and RTT v3 from L4S team";
      homepage = "https://github.com/L4STeam/linux";
      license = licenses.gpl2;
      platforms = platforms.linux;
    };
  };

in {
  options.services.bbr3 = {
    enable = lib.mkEnableOption "BBRv3 congestion control module";
  };

  config = lib.mkIf config.services.bbr3.enable {
    boot.extraModulePackages = [ bbr3Module ];
    boot.kernelModules = [ "tcp_bbr3" ];
  };
}

#
# USAGE:
#
# 1. First, get the correct hash:
#    nix-prefetch-github L4STeam linux --rev 48b3db6b4a7fd57e2d31db3bb46a3bc6af7bf3ad
#
# 2. Replace the placeholder hash above with the actual hash
#
# 3. Add to configuration.nix:
#    imports = [ ./bbr3-module.nix ];
#    services.bbr3.enable = true;
#
# 4. Rebuild:
#    sudo nixos-rebuild switch
#
# 5. Verify:
#    lsmod | grep bbr3
#    cat /proc/sys/net/ipv4/tcp_available_congestion_control
#
# 6. To use BBRv3, add to sysctl.nix:
#    "net.ipv4.tcp_congestion_control" = "bbr3";
#

