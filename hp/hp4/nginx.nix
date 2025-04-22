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

    # package = mkOption {
    # default = pkgs.nginxStable;

    defaultHTTPListenPort = 8080;
    defaultSSLListenPort = 8443;

    #openFirewall = true; # doesn't exist

    statusPage = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    recommendedZstdSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedBrotliSettings = true;

    resolver = {
      addresses = [ "127.0.0.1" ]; # Point to local pdns-recursor
      # valid = "30s"; # Optional: Override DNS cache TTL
      # ipv6 = false; # Optional: Disable IPv6 lookups if desired
    };

    # proxyCachePath = {
    #   "main_cache" = {
    #     # Path will be /var/cache/nginx/main_cache
    #     levels = "1:2";
    #     keysZoneName = "my_proxy_zone";
    #     keysZoneSize = "10m";
    #     maxSize = "10g";
    #     inactive = "60m";
    #     useTempPath = false;
    #   };
    # };

    eventsConfig = ''
      worker_connections 4096;
    '';

    appendHttpConfig = ''
      proxy_cache_path /var/cache/nginx/main_cache levels=1:2 keys_zone=my_proxy_zone:10m max_size=10g inactive=60m use_temp_path=off;
    '';

    virtualHosts."_" = {
      #listen = [{ addr = "0.0.0.0"; port = 3128; }];
      listen = [{ addr = "0.0.0.0"; port = 8080; }];

      extraConfig = ''
        #resolver 127.0.0.1;

        location / {
            proxy_http_version 1.1;
            proxy_pass $request_uri;
            #proxy_pass http://$host$uri$is_args$args;

            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Real-IP $remote_addr;

            proxy_cache my_proxy_zone;
            proxy_cache_key "$scheme$request_method$host$request_uri";
            proxy_cache_valid 200 302 10m;
            proxy_cache_valid 404 1m;
            proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
        }
      '';
    };
  };
  # journalctl --follow --namespace nginx

  systemd.services.nginx.serviceConfig.LogNamespace = "nginx";

  # systemd.tmpfiles.rules = [
  #   "d /var/cache/nginx 0700 nginx nginx - -"
  #   "d /var/log/nginx   0755 nginx nginx - -"
  # ];
  systemd.tmpfiles.settings."nginx-dirs" = {
    "/var/cache/nginx"."d" = {
      mode = "0700";
      user = "nginx";
      group = "nginx";
    };
    "/var/log/nginx"."d" = {
      mode = "0755";
      user = "nginx";
      group = "nginx";
    };
    "/run/nginx"."d" = {
      mode = "0755";
      user = "nginx";
      group = "nginx";
    };
  };

  services.prometheus.exporters.nginx = {
    enable = true;
    openFirewall = true;
    # statusUrl = "http://localhost/stub_status"; # Default, should work with statusPage = true
    # listenAddress = "0.0.0.0"; # Default
    # port = 9113; # Default
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