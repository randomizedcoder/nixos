#
# tcp-prague-module.nix
#
# Build TCP Prague congestion control as an out-of-tree kernel module
# Source: https://github.com/L4STeam/linux
#

{ config, lib, pkgs, ... }:

let
  kernel = config.boot.kernelPackages.kernel;

  # TCP Prague module built from L4S kernel source
  tcpPragueModule = pkgs.stdenv.mkDerivation {
    pname = "tcp-prague";
    version = "0.1-${kernel.version}";

    src = pkgs.fetchFromGitHub {
      owner = "L4STeam";
      repo = "linux";
      # Use the testing branch which has all L4S patches
      rev = "testing";
      # Note: You'll need to update this hash after first build attempt
      sha256 = lib.fakeSha256;
    };

    nativeBuildInputs = kernel.moduleBuildDependencies;

    # Only build the tcp_prague module
    buildPhase = ''
      # Create a minimal Makefile for out-of-tree build
      cat > Makefile.prague <<EOF
      obj-m := tcp_prague.o

      KDIR := ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build

      all:
      	make -C \$(KDIR) M=\$(PWD) modules

      clean:
      	make -C \$(KDIR) M=\$(PWD) clean
      EOF

      # Copy the tcp_prague source file
      cp net/ipv4/tcp_prague.c .

      # Build the module
      make -f Makefile.prague
    '';

    installPhase = ''
      mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
      cp tcp_prague.ko $out/lib/modules/${kernel.modDirVersion}/extra/
    '';

    meta = with lib; {
      description = "TCP Prague - L4S-compatible congestion control";
      homepage = "https://github.com/L4STeam/linux";
      license = licenses.gpl2;
      platforms = platforms.linux;
    };
  };

in {
  # This module is experimental and may not build successfully
  # The L4S team's tcp_prague.c may have dependencies on other L4S patches

  # Uncomment to enable (after fixing the sha256):
  # boot.extraModulePackages = [ tcpPragueModule ];
  # boot.kernelModules = [ "tcp_prague" ];

  # For now, just make the derivation available for testing
  environment.systemPackages = [
    # Uncomment to test building:
    # tcpPragueModule
  ];
}

