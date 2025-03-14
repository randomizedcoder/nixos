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
    o=- 0 0 IN IP4 239.0.0.1
    s=MPEG-TS Over RTP Stream
    c=IN IP4 239.0.0.1
    t=0 0
    a=recvonly
    m=video 6000 RTP/AVP 33
    a=rtpmap:33 MP2T/90000
  '';

  # sdpFile = pkgs.writeText "stream.sdp"
  # ''
  #   v=0
  #   o=- 0 0 IN IP4 239.0.0.1
  #   s=RTP Stream
  #   c=IN IP4 239.0.0.1
  #   t=0 0
  #   m=video 6000 RTP/AVP 96
  #   a=rtpmap:96 H264/90000
  #   a=fmtp:96 packetization-mode=1; profile-level-id=42E01F; sprop-parameter-sets=Z0IAH5WoFAFuQA==,aM48gA==
  #   m=audio 6002 RTP/AVP 97
  #   a=rtpmap:97 MP4A-LATM/44100/2
  # '';

  # ''
  #   v=0
  #   o=- 0 0 IN IP4 239.0.0.1
  #   s=RTP Stream
  #   c=IN IP4 239.0.0.1
  #   t=0 0
  #   m=video 6000 RTP/AVP 96
  #   a=rtpmap:96 H264/90000
  #   m=audio 6002 RTP/AVP 97
  #   a=rtpmap:97 MP4A-LATM/44100/2
  # '';

  # ''
  #   v=0
  #   o=- 0 0 IN IP4 172.16.40.142
  #   s=MPEG-TS Over RTP Stream
  #   c=IN IP4 239.0.0.1/32
  #   t=0 0
  #   a=recvonly
  #   m=video 6000 RTP/AVP 33
  #   a=rtpmap:33 MP2T/90000
  # '';

  # https://developer.nvidia.com/blog/nvidia-ffmpeg-transcoding-guide/#processing_filters
  ffmpegCmd = ''
    ${pkgs.ffmpeg-full}/bin/ffmpeg \
      -vsync 0 \
      -hwaccel cuda \
      -hwaccel_output_format cuda \
      -protocol_whitelist "file,udp,rtp" \
      -analyzeduration 200000000 \
      -probesize 150M \
      -fflags +genpts -max_delay 5000000 \
      -f mpegts \
      -i /hls/stream.sdp \
      -filter_complex "[0:v]split=2[v2][v3]; \
                      [v2]scale_npp=1280:720:interp_algo=super[vout2]; \
                      [v3]scale_npp=640:360:interp_algo=super[vout3]" \
      -map 0:v -c:v hevc_nvenc -b:v 10M -preset p1 -tune hq -rc cbr -maxrate 10M -bufsize 20M -g 50 -pix_fmt yuv420p \
          -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
          -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
          -strftime 1 -hls_segment_filename "/hls/hls_10Mbps/stream-%Y%m%d%H%M%S.ts" \
          "/hls/hls_10Mbps/stream_10.m3u8" \
      -map "[vout2]" -c:v hevc_nvenc -b:v 5M  -preset p1 -tune hq -rc cbr -maxrate 5M -bufsize 10M -g 50 -pix_fmt yuv420p \
          -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
          -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
          -strftime 1 -hls_segment_filename "/hls/hls_5Mbps/stream-%Y%m%d%H%M%S.ts" \
          "/hls/hls_5Mbps/stream_5.m3u8" \
      -map "[vout3]" -c:v hevc_nvenc -b:v 1M  -preset p1 -tune hq -rc cbr -maxrate 1M -bufsize 2M -g 50 -pix_fmt yuv420p \
          -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
          -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
          -strftime 1 -hls_segment_filename "/hls/hls_1Mbps/stream-%Y%m%d%H%M%S.ts" \
          "/hls/hls_1Mbps/stream_1.m3u8" \
      -map a:0 -c:a aac -b:a 128k -ac 2 -f hls -hls_time 4 -hls_list_size 20 \
          -hls_segment_filename "/hls/audio/stream-%Y%m%d%H%M%S.ts" "/hls/audio/stream_audio.m3u8" \
      -master_pl_name "/hls/master.m3u8"
  '';

  # ffmpegCmd = ''
  #   ${pkgs.ffmpeg-full}/bin/ffmpeg \
  #     -vsync 0 \
  #     -hwaccel cuda -hwaccel_output_format cuda \
  #     -protocol_whitelist "file,udp,rtp" \
  #     -analyzeduration 200000000 \
  #     -probesize 150M \
  #     -fflags +genpts -max_delay 5000000 \
  #     -f mpegts \
  #     -i /hls/stream.sdp \
  #     -filter_complex "[0:v]hwupload_cuda,split=3[v10_in][v5_in][v1_in]; \
  #                       [v10_in]scale_cuda=w=1920:h=1080,hwdownload,format=yuv420p[v10_scaled]; \
  #                       [v5_in]scale_cuda=w=1280:h=720,hwdownload,format=yuv420p[v5_scaled]; \
  #                       [v1_in]scale_cuda=w=640:h=360,hwdownload,format=yuv420p[v1_scaled]" \
  #     -map "[v10_scaled]" -map 0:a:0 -c:v h264_nvenc -pix_fmt nv12 -b:v 10M -bufsize 20M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
  #     -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -strftime 1 -hls_segment_filename "/hls/hls_10Mbps/stream-%Y%m%d%H%M%S.ts" \
  #     "/hls/hls_10Mbps/stream_10.m3u8" \
  #     -map "[v5_scaled]" -map 0:a:0 -c:v h264_nvenc -pix_fmt nv12 -b:v 5M -bufsize 10M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
  #     -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -strftime 1 -hls_segment_filename "/hls/hls_5Mbps/stream-%Y%m%d%H%M%S.ts" \
  #     "/hls/hls_5Mbps/stream_5.m3u8" \
  #     -map "[v1_scaled]" -map 0:a:0 -c:v h264_nvenc -pix_fmt nv12 -b:v 1M -bufsize 2M -preset p5 -g 50 -keyint_min 50 -c:a aac -b:a 128k -ac 2 \
  #     -f hls -hls_time 4 -hls_list_size 20 -hls_delete_threshold 2 \
  #     -hls_flags delete_segments+independent_segments+temp_file+discont_start+omit_endlist \
  #     -strftime 1 -hls_segment_filename "/hls/hls_1Mbps/stream-%Y%m%d%H%M%S.ts" \
  #     "/hls/hls_1Mbps/stream_1.m3u8 \
  #     -master_pl_name /hls/master.m3u8"
  # '';
      # -i "rtp://239.0.0.1:6000" \
      # -i /hls/stream.sdp \
      # -filter_complex "[0:v]split=3[v10][v5][v1]; \
      #                  [v10]scale_cuda=1920:1080[v10_scaled]; \
      #                  [v5]scale_cuda=1280:720[v5_scaled]; \
      #                  [v1]scale_cuda=640:360[v1_scaled]" \

in
{
  # fileSystems."/hls" = {
  #   device = "tmpfs";
  #   fsType = "tmpfs";
  #   options = [ "size=1G" "mode=0770" "uid=nginx" "gid=nginx" "noatime" ];
  # };
  systemd.mounts = [
    {
      what = "tmpfs";
      where = "/hls";
      type = "tmpfs";
      options = "size=1G,mode=0770,uid=nginx,gid=nginx,noatime";
    }
  ];

  # https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html
  systemd.tmpfiles.rules = [
    #Type Path        Mode User Group Age Argument…
    "d /hls 0770 nginx nginx -"
    "d /hls/hls_10Mbps 0770 nginx nginx 5m"
    "d /hls/hls_5Mbps 0770 nginx nginx 5m"
    "d /hls/hls_1Mbps 0770 nginx nginx 5m"
  ];

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

  # cat /etc/systemd/system/ffmpeg-hls.service
  # sudo systemctl restart ffmpeg-hls.service
  # sudo systemctl status ffmpeg-hls.service
  # sudo journalctl -u ffmpeg-hls -f
  systemd.services.ffmpeg-hls = {
    description = "FFmpeg RTP to HLS Streaming Service";
    after = [ "network.target" "create-stream-sdp.service" "create-stream-m3u8.service" "nginx.service" ];
    #after = [ "network.target" "nginx.service" ];
    #requires = [ "create-hls-tmpfs.service" ];
    requires = [ "create-stream-sdp.service" "create-stream-m3u8.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      WorkingDirectory = "/hls";
      RuntimeDirectory = "/hls";
      ExecStart = ffmpegCmd;
      Restart = "always";
      RestartSec = 10;
      #ExecStartPre = "/bin/sleep 5"; # this is wrong.  needs path to the nix package.
      User = "nginx";
      Group = "nginx";
      StandardOutput = "journal";
      StandardError = "journal";
      LimitNOFILE = 1048576;

      # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#Scheduling
      Nice = "-20";
      #CPUSchedulingPriority = "99";
      # https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/managing_monitoring_and_updating_the_kernel/assembly_configuring-cpu-affinity-and-numa-policies-using-systemd_managing-monitoring-and-updating-the-kernel#assembly_configuring-cpu-affinity-and-numa-policies-using-systemd_managing-monitoring-and-updating-the-kernel
      #CPUAffinity=
      #NUMAMask=

      Environment = [
        "CUDA_PATH=${pkgs.linuxPackages.nvidia_x11}/lib"
        "EXTRA_LDFLAGS=-L/lib -L${pkgs.linuxPackages.nvidia_x11}/lib"
        "EXTRA_CCFLAGS=-I/usr/include"
        "LD_LIBRARY_PATH=/run/opengl-driver/lib:${pkgs.linuxPackages.nvidia_x11}/lib"
        "NVIDIA_DRIVER_CAPABILITIES=all"
        "CUDA_VISIBLE_DEVICES=0"
        ##"FFMPEG_OUTPUT_DIR=/hls"
      ];

      SupplementaryGroups = [ "video" "render" ];
      DeviceAllow = [ "/dev/nvidia0 rw" "/dev/nvidiactl rw" "/dev/nvidia-uvm rw" "/dev/dri/card0 rw" ];
      UMask = "0002";

      NoNewPrivileges = false;
      ProtectSystem = "full";
      ProtectKernelModules = false;
      MemoryDenyWriteExecute = false;

    };
  };
}
