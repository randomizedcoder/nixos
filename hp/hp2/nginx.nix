{ config, pkgs, ... }:

{
  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."localhost" = {
      root = "/home/das/hls";
      locations."/" = {
        index = "index.html";
        extraConfig = ''
          types {
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
          }

          # Allow CORS (for external players)
          add_header Access-Control-Allow-Origin *;
          add_header Access-Control-Allow-Methods 'GET, OPTIONS';
          add_header Access-Control-Allow-Headers 'Range';
          add_header Access-Control-Expose-Headers 'Content-Length,Content-Range';
          add_header Access-Control-Max-Age 345600 always;  # 4 days (345600 seconds)

          # Cache settings for HLS playlists
          location ~* \.m3u8$ {
            expires 30s;
            add_header Cache-Control "public, max-age=30, stale-while-revalidate=60, stale-if-error=600";
          }

          # Cache settings for HLS segments (TS files)
          location ~* \.ts$ {
            expires 24h;
            add_header Cache-Control "public, max-age=86400, stale-while-revalidate=3600, stale-if-error=86400";
          }
        '';
      };
    };
  };

  systemd.services.nginx.serviceConfig = {
    LimitNOFILE = 100000;  # Increase file descriptor limit for better performance
  };
}