{ pkgs, config, ... }:
{
  systemd.services.trafficserver = {
    # We would like to reload if any of the possible config modules are changed
    reloadIfChanged = true;
    serviceConfig.ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
  };
  # https://search.nixos.org/options?channel=24.11&size=50&sort=relevance&type=packages&query=trafficserver
  # https://github.com/NixOS/nixpkgs/blob/nixos-24.11/nixos/modules/services/web-servers/trafficserver/default.nix
  services.trafficserver = {
    enable = true;
    #volume = "volume=1 scheme=http size=20%";
    storage = "/var/cache/trafficserver 200G";
    # storage = "/var/cache/trafficserver 256M";

    records = {
      proxy = {
        config = {
          # Anonymize the forward proxy
          http = {
            anonymize_remove_from = 1;
            anonymize_remove_referer = 1;
            anonymize_remove_user_agent = 1;
            anonymize_remove_cookie = 1;
            anonymize_remove_client_ip = 1;

            cache.http = 0;
            insert_client_ip = 0;
            insert_squid_x_forwarded_for = 0;
            insert_request_via_str = 0;
            insert_response_via_str = 0;
            response_server_enabled = 0;
            #server_ports = toString cfg.proxyPort;
            server_ports = "3128 3128:ipv6";
          };

          # Set logging and disable reverse proxy
          log.logging_enabled = 3;
          reverse_proxy.enabled = 0;

          # Control access to the proxy via firewall and ip_allow rather than remap
          url_remap.remap_required = 0;
        };
      };
    };

    ipAllow = {
      ip_allow = [
        {
          apply = "in";
          ip_addrs = "127.0.0.1";
          action = "allow";
          methods = "ALL";
        }
        {
          apply = "in";
          ip_addrs = "::1";
          action = "allow";
          methods = "ALL";
        }
        {
          apply = "in";
          ip_addrs = "172.16.0.0/16";
          action = "allow";
          methods = "ALL";
        }
        {
          apply = "in";
          # 4x4x4=64
          # 2603:8000:9c01:3b00
          ip_addrs = "2603:8000:9c01:3b00/64";
          action = "allow";
          methods = "ALL";
        }
        {
          apply = "in";
          ip_addrs = "0/0";
          action = "deny";
          methods = "ALL";
        }
        {
          apply = "in";
          ip_addrs = "::/0";
          action = "deny";
          methods = "ALL";
        }
      ];
    };
  };
}
# https://github.com/input-output-hk/cardano-parts/blob/main/flake/nixosModules/profile-mithril-relay.nix
# https://github.com/HippocampusGirl/nixos/blob/b01f0359810cfdd040642e2e3bbea8683bc11aee/machines/laptop-wsl/trafficserver.nix#L2