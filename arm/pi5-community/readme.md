
pi5-1-os is the flake that was build on the pi5

pi5-community was used to build the sd card image

https://github.com/NixOS/nixpkgs/issues/260754#issuecomment-2322817130


nix build '.#nixosConfigurations.myrpi5.config.system.build.sdImage'