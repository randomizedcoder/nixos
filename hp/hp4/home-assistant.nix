#
# home-assistant.nix
#
# https://nixos.wiki/wiki/Home_Assistant
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/home-assistant/default.nix
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/home-assistant/component-packages.nix
#
{ config, pkgs, ... }:
{
  services.home-assistant = {
    enable = true;

    package = (pkgs.home-assistant.override {
      extraPackages = py: with py; [ psycopg2 ];
    }).overrideAttrs (oldAttrs: {
      doInstallCheck = false;
    });

    extraComponents = [
      # Components required to complete the onboarding
      "esphome"
      "met"
      "radio_browser"
      "tuya"
      "wemo"
    ];

    configDir = /var/lib/hass;
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = {};
      recorder.db_url = "postgresql://@/hass";
    };
  };

  # https://nixos.wiki/wiki/Home_Assistant#Using_PostgreSQL
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "hass" ];
    ensureUsers = [{
      name = "hass";
      ensureDBOwnership = true;
    }];
  };

  systemd.tmpfiles.rules = [
    "C ${config.services.home-assistant.configDir}/custom_components/sonoff - - - - ${sources.sonoff-lan}/custom_components/sonoff"
    "Z ${config.services.home-assistant.configDir}/custom_components 770 hass hass - -"
    "f ${config.services.home-assistant.configDir}/automations.yaml 0755 hass hass"
  ];
}