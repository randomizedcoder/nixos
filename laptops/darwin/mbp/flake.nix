{
  description = "My system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager }:
    let
      configuration = { pkgs, ... }: {

        services.nix-daemon.enable = true;
        # Necessary for using flakes on this system.
        nix.settings.experimental-features = "nix-command flakes";

        system.configurationRevision = self.rev or self.dirtyRev or null;

        # Used for backwards compatibility. please read the changelog
        # before changing: `darwin-rebuild changelog`.
        system.stateVersion = 5;

        # The platform the configuration will be used on.
        # If you're on an older system, replace with "x86_64-darwin"
        nixpkgs.hostPlatform = "x86_64-darwin";

        # Declare the user that will be running `nix-darwin`.
        users.users.das = {
          name = "das";
          home = "/Users/das";
        };

        security.pam.enableSudoTouchIdAuth = true;

        # Create /etc/zshrc that loads the nix-darwin environment.
        programs.zsh.enable = true;
        environment.systemPackages = [ pkgs.neofetch ];

        # homebrew = {
        #   enable = true;
        #   # onActivation.cleanup = "uninstall";

        #   taps = [ ];
        #   brews = [ "cowsay" ];
        #   casks = [ ];
        # };
      };
      homeconfig = { pkgs, ... }: {
        # this is internal compatibility configuration for home-manager,
        # don't change this!
        home.stateVersion = "24.05";
        # Let home-manager install and manage itself.
        programs.home-manager.enable = true;

        home.packages = with pkgs; [
          gcc
          automake
          gnumake
          #cmake
          pkg-config
          git
          htop
          screen
          go
          tcpdump
        ];

        home.sessionVariables = {
          EDITOR = "vim";
        };

        #home.file.".vimrc".source = ./vim_configuration;

        programs.zsh = {
          enable = true;
          shellAliases = {
            switch = "darwin-rebuild switch --flake ~/.config/nix";
          };
        };

        programs.git = {
          enable = true;
          userEmail = "dave.seddon.ca@gmail.com";
          userName = "randomizedcoder ";
        };
      };
    in
    {
      darwinConfigurations.dass-MacBook-Pro = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.verbose = true;
            home-manager.users.das = homeconfig;
          }
        ];
      };
    };
}
