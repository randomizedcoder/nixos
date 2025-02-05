#
# sudo systemctl start ffmpeg-hls
# sudo systemctl enable ffmpeg-hls
# journalctl -u ffmpeg-hls -f
#

{ config, lib, pkgs, ... }:

let

  streamManifest = pkgs.writeText "stream.m3u8"
  ''
  #EXTM3U
  #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360
  stream_1.m3u8
  #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1280x720
  stream_5.m3u8
  #EXT-X-STREAM-INF:BANDWIDTH=10000000,RESOLUTION=1920x1080
  stream_10.m3u8
  '';

  sdpFile = pkgs.writeText "stream.sdp"
  ''
    v=0
    o=- 0 0 IN IP4 172.16.40.142
    s=MPEG-TS Over RTP Stream
    c=IN IP4 239.0.0.1/32
    t=0 0
    a=recvonly
    m=video 6000 RTP/AVP 33
    a=rtpmap:33 MP2T/90000
  '';

  # sdpContent = ''
  #   v=0
  #   o=- 0 0 IN IP4 172.16.40.142
  #   s=MPEG-TS Over RTP Stream
  #   c=IN IP4 239.0.0.1/32
  #   t=0 0
  #   a=recvonly
  #   m=video 6000 RTP/AVP 33
  #   a=rtpmap:33 MP2T/90000
  # '';

  ffmpegCmd = ''
    ${pkgs.ffmpeg-full}/bin/ffmpeg \
      -hwaccel cuda -hwaccel_output_format cuda \
      -protocol_whitelist "file,udp,rtp" \
      -analyzeduration 100000000 -probesize 500M -fflags +genpts -max_delay 5000000 \
      -i /hls/stream.sdp \
      -filter_complex "[0:v]split=3[v10][v5][v1]; \
                       [v10]scale_cuda=1920:1080[v10_scaled]; \
                       [v5]scale_cuda=1280:720[v5_scaled]; \
                       [v1]scale_cuda=640:360[v1_scaled]" \
      -map "[v10_scaled]" -map a:0 -c:v h264_nvenc -b:v 10M -bufsize 20M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
      -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
      -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
      -strftime 1 -hls_segment_filename "/hls/hls_10Mbps/stream-%Y%m%d%H%M%S.ts" \
      "/hls/hls_10Mbps/stream_10.m3u8" \
      -map "[v5_scaled]" -map a:0 -c:v h264_nvenc -b:v 5M -bufsize 10M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
      -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
      -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
      -strftime 1 -hls_segment_filename "/hls/hls_5Mbps/stream-%Y%m%d%H%M%S.ts" \
      "/hls/hls_5Mbps/stream_5.m3u8" \
      -map "[v1_scaled]" -map a:0 -c:v h264_nvenc -b:v 1M -bufsize 2M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
      -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
      -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
      -strftime 1 -hls_segment_filename "/hls/hls_1Mbps/stream-%Y%m%d%H%M%S.ts" \
      "/hls/hls_1Mbps/stream_1.m3u8"
  '';

  # ffmpegCmd = ''
  #   ${pkgs.ffmpeg-full}/bin/ffmpeg \
  #     -protocol_whitelist "file,udp,rtp" \
  #     -analyzeduration 100000000 -probesize 500M -fflags +genpts -max_delay 5000000 \
  #     -i /hls/stream.sdp \
  #     -filter_complex "[0:v]split=3[v10][v5][v1]; \
  #                      [v10]scale=1920:1080[v10_scaled]; \
  #                      [v5]scale=1280:720[v5_scaled]; \
  #                      [v1]scale=640:360[v1_scaled]" \
  #     -map "[v10_scaled]" -map a:0 -c:v h264_nvenc -b:v 10M -bufsize 20M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
  #     -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -strftime 1 -hls_segment_filename "/hls/hls_10Mbps/stream-%Y%m%d%H%M%S.ts" \
  #     "/hls/hls_10Mbps/stream_10.m3u8" \
  #     -map "[v5_scaled]" -map a:0 -c:v h264_nvenc -b:v 5M -bufsize 10M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
  #     -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -strftime 1 -hls_segment_filename "/hls/hls_5Mbps/stream-%Y%m%d%H%M%S.ts" \
  #     "/hls/hls_5Mbps/stream_5.m3u8" \
  #     -map "[v1_scaled]" -map a:0 -c:v h264_nvenc -b:v 1M -bufsize 2M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
  #     -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -strftime 1 -hls_segment_filename "/hls/hls_1Mbps/stream-%Y%m%d%H%M%S.ts" \
  #     "/hls/hls_1Mbps/stream_1.m3u8"
  # '';

  # ffmpegCmd = ''
  #   ${pkgs.ffmpeg-full}/bin/ffmpeg \
  #     -protocol_whitelist "file,udp,rtp" \
  #     -analyzeduration 100000000 -probesize 500M -fflags +genpts -max_delay 5000000 \
  #     -i /hls/stream.sdp \
  #     -filter_complex "[0:v]split=3[v10][v5][v1]; \
  #                      [v10]scale=1920:1080[v10_scaled]; \
  #                      [v5]scale=1280:720[v5_scaled]; \
  #                      [v1]scale=640:360[v1_scaled]" \
  #     -map "[v10_scaled]" -map a:0 -c:v h264_nvenc -b:v 10M -bufsize 20M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -hls_segment_filename "$FFMPEG_OUTPUT_DIR/hls_10Mbps/stream-%Y%m%d%H%M%S.ts" -strftime 1 \
  #     "$FFMPEG_OUTPUT_DIR/hls_10Mbps/stream_10.m3u8" \
  #     -map "[v5_scaled]" -map a:0 -c:v h264_nvenc -b:v 5M -bufsize 10M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -hls_segment_filename "$FFMPEG_OUTPUT_DIR/hls_5Mbps/stream-%Y%m%d%H%M%S.ts" -strftime 1 \
  #     "$FFMPEG_OUTPUT_DIR/hls_5Mbps/stream_5.m3u8" \
  #     -map "[v1_scaled]" -map a:0 -c:v h264_nvenc -b:v 1M -bufsize 2M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -hls_segment_filename "$FFMPEG_OUTPUT_DIR/hls_1Mbps/stream-%Y%m%d%H%M%S.ts" -strftime 1 \
  #     "$FFMPEG_OUTPUT_DIR/hls_1Mbps/stream_1.m3u8"
  # '';
  # -hls_segment_filename \"/hls/hls_1Mbps/%Y%m%d%H/stream-%Y%m%d%H%M%S.ts\" -strftime 1 -strftime_mkdir 1 /hls/hls_1Mbps/stream_1.m3u8

in
{
  fileSystems."/hls" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=1G" "mode=0770" "uid=nginx" "gid=nginx" "noatime" ];
  };
  # systemd.tmpfiles.rules = [
  #   "d /hls 0770 nginx nginx -"
  #   "v /hls - tmpfs rw,nosuid,nodev,noexec,noatime,size=1G,mode=0770,uid=nginx,gid=nginx"
  # ];
  # systemd.services.create-hls-tmpfs = {
  #   description = "Ensure /hls tmpfs is mounted";
  #   wantedBy = [ "multi-user.target" ];
  #   after = [ "network.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "/run/current-system/sw/bin/mkdir -p /hls";
  #     ExecStartPost = "/run/current-system/sw/bin/mount -o size=1G,mode=0770,uid=nginx,gid=nginx,noatime -t tmpfs tmpfs /hls";
  #     RemainAfterExit = true;
  #   };
  # };

  # sudo systemctl restart create-stream-sdp.service
  systemd.services.create-stream-sdp = {
    description = "Generate RTP stream SDP file in /hls";
    after = [ "local-fs.target" ];
    wantedBy = [ "nginx.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -m 644 -o nginx -g nginx ${sdpFile} /hls/stream.sdp";
    };
  };

  # sudo systemctl restart create-stream-m3u8.service
  systemd.services.create-stream-m3u8 = {
    description = "Generate stream.m3u8 file in /hls";
    after = [ "local-fs.target" ];
    wantedBy = [ "nginx.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -m 644 -o nginx -g nginx ${streamManifest} /hls/stream.m3u8";
    };
  };

  # sudo systemctl restart ffmpeg-hls.service
  # sudo systemctl status ffmpeg-hls.service
  # sudo journalctl -u ffmpeg-hls -f
  systemd.services.ffmpeg-hls = {
    description = "FFmpeg RTP to HLS Streaming Service";
    after = [ "network.target" "nginx.service" "create-hls-tmpfs.service" ];
    #after = [ "network.target" "nginx.service" ];
    #requires = [ "create-hls-tmpfs.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      WorkingDirectory = "/hls";
      RuntimeDirectory = "/hls";
      ExecStart = ffmpegCmd;
      Restart = "always";
      RestartSec = 2;
      User = "nginx";
      Group = "nginx";
      StandardOutput = "journal";
      StandardError = "journal";
      LimitNOFILE = 1048576;  # Increase file descriptor limits for high concurrency

      Environment = [
        "CUDA_PATH=${pkgs.linuxPackages.nvidia_x11}/lib"
        "EXTRA_LDFLAGS=-L/lib -L${pkgs.linuxPackages.nvidia_x11}/lib"
        "EXTRA_CCFLAGS=-I/usr/include"
        "LD_LIBRARY_PATH=/run/opengl-driver/lib:${pkgs.linuxPackages.nvidia_x11}/lib"
        "NVIDIA_DRIVER_CAPABILITIES=all"
        "CUDA_VISIBLE_DEVICES=0"  # Ensure it sees the first GPU
        "FFMPEG_OUTPUT_DIR=/hls"
      ];

      # GPU Access
      SupplementaryGroups = [ "video" "render" ];  # Ensures FFmpeg can access GPU
      DeviceAllow = [ "/dev/nvidia0 rw" "/dev/nvidiactl rw" "/dev/nvidia-uvm rw" "/dev/dri/card0 rw" ];
      UMask = "0002";

      NoNewPrivileges = false;
      ProtectSystem = "full";
      ProtectKernelModules = false;
      MemoryDenyWriteExecute = false;
      #RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];  # Allow IPv4 and IPv6
      #IPAddressAllow = "239.0.0.1";  # Allow access to the multicast address

      # ### 🔒 Security Hardening
      # NoNewPrivileges = true;
      # PrivateTmp = true;
      # ProtectSystem = "full";
      # #ProtectSystem = "strict";
      # ProtectHome = "yes";
      # ProtectKernelModules = false;
      # #ProtectKernelModules = true;
      # ProtectKernelLogs = true;
      # ProtectControlGroups = true;
      # # stops errors like "CUDA_ERROR_OPERATING_SYSTEM: OS call failed or operation not supported on this OS"
      # MemoryDenyWriteExecute = false;
      # #MemoryDenyWriteExecute = true;
      # RestrictRealtime = true;
      # RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ]; # or do "~AF_INET";
      # SystemCallFilter = [ "~@mount" "~@privileged" "~@resources" ];
      # LockPersonality = true;
      # ReadOnlyPaths = "/etc /usr /var";
      # ProtectClock = true;
    };
  };
}
