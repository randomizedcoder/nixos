#
# nixos/hp/hp4/nginx.nix
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
    # statusPage = true;  # Disabled to avoid conflicting server blocks

    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    #recommendedZstdSettings = true; # The zstd module for Nginx has known bugs and is not maintained well.
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

      locations."/ollama/" = {
        extraConfig = ''
          # Strip the /ollama/ prefix from the request URI
          rewrite ^/ollama/(.*)$ /$1 break;

          # Handle preflight OPTIONS requests
          if ($request_method = OPTIONS) {
              add_header Allow "POST, OPTIONS";
              add_header Access-Control-Allow-Origin "*";
              add_header Access-Control-Allow-Headers "authorization, content-type";
              add_header Access-Control-Allow-Methods "POST, OPTIONS";
              add_header Access-Control-Max-Age 86400;
              return 204;
          }

          # Remove or modify the Origin header before forwarding the request
          proxy_set_header Origin "";

          # Forward other requests to backend server
          proxy_pass http://localhost:11434;

          # Include additional headers for CORS support in normal requests
          add_header Access-Control-Allow-Origin "*";
          add_header Access-Control-Allow-Headers "authorization, content-type";
          add_header Access-Control-Allow-Methods "POST, OPTIONS";
          add_header Access-Control-Max-Age 86400;
        '';
      };

      # # Add smokeping to the default virtual host
      # locations."/smokeping/" = {
      #   extraConfig = ''
      #     root /var/lib;
      #     index smokeping.fcgi;
      #   '';
      # };

      # locations."/smokeping/smokeping.fcgi" = {
      #   extraConfig = ''
      #     include ${pkgs.nginx}/conf/fastcgi_params;
      #     fastcgi_pass unix:/run/fcgiwrap-smokeping.sock;
      #     fastcgi_param SCRIPT_FILENAME /var/lib/smokeping/smokeping.fcgi;
      #     fastcgi_param DOCUMENT_ROOT /var/lib/smokeping;
      #   '';
      # };

      # locations."/smokeping/cache/" = {
      #   extraConfig = ''
      #     root /var/lib;
      #     autoindex off;
      #   '';
      # };
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

  # # Enable fcgiwrap for smokeping
  # services.fcgiwrap.instances.smokeping = {
  #   process.user = "smokeping";
  #   process.group = "smokeping";
  #   socket = { inherit (config.services.nginx) user group; };
  # };

  # Systemd service configuration for nginx with resource limits
  systemd.services.nginx = {
    serviceConfig = {
      # Resource limits - moderate for web server
      MemoryMax = "300M";
      MemoryHigh = "250M";
      CPUQuota = "50%";
      TasksMax = 200;

      # Process limits
      LimitNOFILE = 8192;
      LimitNPROC = 50;

      # Nice priority
      Nice = 10;

      # NoNewPrivileges = true;
      # ProtectSystem = "strict";
      # ProtectHome = true;
      # ProtectKernelTunables = true;
      # ProtectKernelModules = true;
      # ProtectControlGroups = true;
      # ProtectKernelLogs = true;
      # PrivateDevices = true;
      # PrivateTmp = true;
      # RestrictRealtime = true;
      # RestrictSUIDSGID = true;
      # RestrictNamespaces = true;
      # PrivateUsers = true;  # Create user namespace - service sees itself as root internally
      # LockPersonality = true;
      # ProtectHostname = true;
      # ProtectClock = true;

      # RemoveIPC = true;  # Clean up IPC objects
      # #ProtectProc = "default";  # Allow access to process info and /proc/net
      # ProcSubset = "pid";  # Only allow access to own process info

      # RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

      # DeviceAllow = [
      #   "/dev/null rw"
      #   "/dev/zero rw"
      #   "/dev/random r"
      #   "/dev/urandom r"
      # ];

      # # Keyring mode - ClickHouse doesn't need keyring access
      # KeyringMode = "private";

      # # Delegate - ClickHouse doesn't need cgroup delegation
      # Delegate = false;

      # # Notify access - Only main process can alter service state
      # NotifyAccess = "main";
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