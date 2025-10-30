#
# nixos/qotom/nfb/nginx.nix
#
{ pkgs, config, ... }:

{
  # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/http/nginx/generic.nix
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/web-servers/nginx/default.nix
  # acme: https://github.com/lovesegfault/nix-config/blob/f32ab485a45bf60c3d86aa4485254b087d8e0187/services/nginx.nix#L28
  # https://github.com/NixOS/nixpkgs/blob/47457869d5b12bdd72303d6d2ba4bfcc26fe8531/nixos/modules/services/security/oauth2-proxy-nginx.nix
  # https://blog.matejc.com/blogs/myblog/nixos-hydra-nginx
  # https://github.com/nixinator/cardano-ops/blob/8a7be334a476a80829e17c8a0ca6ec374347a937/roles/explorer.nix#L313
  # grep ExecStartPre /etc/systemd/system/nginx.service
  services.nginx = {
    enable = true;
    defaultHTTPListenPort = 8080;
    statusPage = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    # recommendedZstdSettings = true; # option has been removed
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedBrotliSettings = true;

    # Minimal configuration for serving files
    virtualHosts."_" = {
      serverName = "_";
      root = "/var/www/html";
      default = true;

      locations."/" = {
        extraConfig = ''
          autoindex on;
          autoindex_exact_size on;
          autoindex_localtime on;
          #index index.html;
        '';
      };

      locations."/nginx_status" = {
        extraConfig = ''
          stub_status on;
          access_log off;
          allow 127.0.0.1;
          allow ::1;
          allow 172.16.50.0/24;
          deny all;
        '';
      };

      # Add smokeping to the default virtual host
      locations."/smokeping/" = {
        extraConfig = ''
          root /var/lib;
          index smokeping.fcgi;
        '';
      };

      locations."/smokeping/smokeping.fcgi" = {
        extraConfig = ''
          include ${pkgs.nginx}/conf/fastcgi_params;
          fastcgi_pass unix:/run/fcgiwrap-smokeping.sock;
          fastcgi_param SCRIPT_FILENAME /var/lib/smokeping/smokeping.fcgi;
          fastcgi_param DOCUMENT_ROOT /var/lib/smokeping;
        '';
      };

      locations."/smokeping/cache/" = {
        extraConfig = ''
          root /var/lib;
          autoindex off;
        '';
      };
    };
  };

  # Ensure the docRoot directory exists and has correct permissions
  systemd.tmpfiles.rules = [
    "d /var/www/html 0755 nginx nginx - -"
  ];

  # journalctl --follow --namespace nginx

  systemd.services.nginx.serviceConfig.LogNamespace = "nginx";

  services.prometheus.exporters.nginx = {
    enable = true;
    openFirewall = true;
    # statusUrl = "http://localhost/stub_status"; # Default, should work with statusPage = true
    # listenAddress = "0.0.0.0"; # Default
    # port = 9113; # Default
  };

  # Enable fcgiwrap for smokeping
  services.fcgiwrap.instances.smokeping = {
    process.user = "smokeping";
    process.group = "smokeping";
    socket = { inherit (config.services.nginx) user group; };
  };

  # Systemd service configuration for nginx with resource limits
  systemd.services.nginx = {
    serviceConfig = {
      # Resource limits - moderate for web server
      MemoryMax = "300M";
      MemoryHigh = "250M";
      CPUQuota = "20%";
      TasksMax = 200;

      # Process limits
      LimitNOFILE = 65536;
      LimitNPROC = 100;

      # Nice priority
      Nice = 10;
    };
  };
}
# {
#   # https://nixos.wiki/wiki/Nginx
#   # https://mynixos.com/options/services.nginx
#   # https://search.nixos.org/options?channel=24.11&from=0&size=50&sort=relevance&type=packages&query=services.nginx
#   services.nginx = {
#     enable = true;
#     statusPage = true;

#     listen = 8080;

#     resolver.addresses = [ "1.1.1.1" "8.8.8.8" ]

#     recommendedZstdSettings = true;
#     recommendedGzipSettings = true;
#     recommendedOptimisation = true;
#     recommendedProxySettings = true;
#     recommendedBrotliSettings = true;

#     virtualHosts = {
#       default = {
#           serverName = "_";
#           default = true;
#           rejectSSL = true;
#           locations = {
#             "/" = {
#               resolver 1.1.1.1;
#               proxyPass = "http://127.0.0.1:12345";
#             }
#           }
#       };
#     };
#   };
# };