#
# nixos/hp/hp1/ffmpeg_systemd_service.nix
#
# systemctl --user restart ffmpeg-stream
# systemctl --user status ffmpeg-stream
#
# [das@hp1:~/nixos/hp/hp1]$ systemctl --user restart ffmpeg-stream

# [das@hp1:~/nixos/hp/hp1]$ systemctl --user status ffmpeg-stream
# ● ffmpeg-stream.service
#      Loaded: loaded (/home/das/.config/systemd/user/ffmpeg-stream.service; enabled; preset: ignored)
#      Active: active (running) since Sun 2025-02-02 15:16:54 PST; 3min 41s ago
#  Invocation: ac9c5b7820cd40fe85f95d610a184c46
#    Main PID: 394915 (ffmpeg)
#       Tasks: 37 (limit: 37129)
#      Memory: 230.4M (peak: 230.9M)
#         CPU: 2min 13.669s
#      CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/ffmpeg-stream.service
#              └─394915 /nix/store/hk1a30i7a4nhc16sc407z0fi1yxgfgjp-ffmpeg-7.1-bin/bin/ffmpeg -f lavfi -re -i testsrc2=rate=30:size=1920x1080 -codec:v libx264 -b:v 10240k -maxrate:v 10000k -bu>

# [das@hp1:~/nixos/hp/hp1]$ journalctl --user -u ffmpeg-stream -f
# Feb 02 15:16:54 hp1 ffmpeg[394915]: [libx264 @ 0x352394c0] using cpu capabilities: MMX2 SSE2Fast SSSE3 SSE4.2 AVX FMA3 BMI2 AVX2
# Feb 02 15:16:54 hp1 ffmpeg[394915]: [libx264 @ 0x352394c0] profile Constrained Baseline, level 4.0, 4:2:0, 8-bit
# Feb 02 15:16:54 hp1 ffmpeg[394915]: Output #0, mpegts, to 'udp://239.0.0.1:6000?ttl=4&pkt_size=1326&localddr=172.16.40.142':
# Feb 02 15:16:54 hp1 ffmpeg[394915]:   Metadata:
# Feb 02 15:16:54 hp1 ffmpeg[394915]:     encoder         : Lavf61.7.100
# Feb 02 15:16:54 hp1 ffmpeg[394915]:   Stream #0:0: Video: h264, yuv420p(tv, progressive), 1920x1080 [SAR 1:1 DAR 16:9], q=2-31, 10240 kb/s, 25 fps, 90k tbn
# Feb 02 15:16:54 hp1 ffmpeg[394915]:       Metadata:
# Feb 02 15:16:54 hp1 ffmpeg[394915]:         encoder         : Lavc61.19.100 libx264
# Feb 02 15:16:54 hp1 ffmpeg[394915]:       Side data:
# Feb 02 15:16:54 hp1 ffmpeg[394915]:         cpb: bitrate max/min/avg: 10000000/0/10240000 buffer size: 10240000 vbv_delay: N/A

# [das@hp1:~/nixos/hp/hp1]$ sudo tcpdump -ni eno1 -c 5 host 239.0.0.1
# tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
# listening on eno1, link-type EN10MB (Ethernet), snapshot length 262144 bytes
# 15:21:39.577834 IP 172.16.40.142.4032 > 239.0.0.1.6000: UDP, length 1326
# 15:21:39.577866 IP 172.16.40.142.4032 > 239.0.0.1.6000: UDP, length 1326
# 15:21:39.577885 IP 172.16.40.142.4032 > 239.0.0.1.6000: UDP, length 1326
# 15:21:39.577907 IP 172.16.40.142.4032 > 239.0.0.1.6000: UDP, length 1326
# 15:21:39.577927 IP 172.16.40.142.4032 > 239.0.0.1.6000: UDP, length 1326
# 5 packets captured
# 35 packets received by filter
# 0 packets dropped by kernel

{
  config,
  lib,
  pkgs,
  ...
}:

# ${pkgs.ffmpeg}/bin/ffmpeg \
# ${home.packages.ffmpeg-full}/bin/ffmpeg \
# ffmpeg -f lavfi -i "sine=frequency=1000:duration=10" -c:a aac -b:a 128k /home/das/test_audio.aac
let
  ffmpegCmd =
  ''
    ${pkgs.ffmpeg-full}/bin/ffmpeg -f lavfi -re -i testsrc2=rate=30:size=1920x1080 \
      -f lavfi -i "sine=frequency=1000" \
      -c:v libx264 -b:v 10000k -preset ultrafast -r 25 \
      -x264-params "nal-hrd=cbr:force-cfr=1:aud=1:intra-refresh=1" \
      -tune zerolatency \
      -bsf:v h264_mp4toannexb \
      -c:a aac -b:a 128k -ac 2 \
      -max_delay 500000 -bufsize 2000000 -fflags +genpts \
      -f rtp_mpegts "rtp://239.0.0.2:6000?pkt_size=1326&ttl=4&localaddr=172.16.40.142"
  '';
  # Ensures SPS/PPS is sent in every keyframe (prevents decoder from losing parameter sets).
  # Forces constant frame rate (force-cfr=1), improving stream stability.

  # ''
  #   ${pkgs.ffmpeg-full}/bin/ffmpeg \
  #     -f lavfi -re -i testsrc2=rate=30:size=1920x1080 \
  #     -f lavfi -i "sine=frequency=1000" \
  #     -c:v libx264 -b:v 10000k -preset ultrafast -r 25 \
  #     -c:a aac -b:a 128k -ac 2 \
  #     -x264opts "keyint=50:min-keyint=50:no-scenecut" \
  #     -bsf:v h264_mp4toannexb \
  #     -max_delay 500000 -bufsize 2000000 -fflags +genpts \
  #     -f rtp_mpegts "rtp://239.0.0.1:6000?pkt_size=1326&ttl=4&localaddr=172.16.40.142"
  # '';
  #-x264opts "keyint=50:min-keyint=50:no-scenecut" ensures regular keyframes.
  #-bsf:v h264_mp4toannexb converts H.264 to Annex B format, which is better for streaming.

  # ''
  #   ${pkgs.ffmpeg-full}/bin/ffmpeg \
  #     -f lavfi -re -i testsrc2=rate=30:size=1920x1080 \
  #     -f lavfi -i "sine=frequency=1000" \
  #     -c:v libx264 -b:v 10000k -preset ultrafast -r 25 \
  #     -c:a aac -b:a 128k -ac 2 \
  #     -max_delay 500000 -bufsize 2000000 -fflags +genpts \
  #     -f rtp_mpegts \
  #     "rtp://239.0.0.1:6000?pkt_size=1326&ttl=4&localaddr=172.16.40.142"
  # '';

  # ''
  #   ${pkgs.ffmpeg-full}/bin/ffmpeg \
  #   -f lavfi -re -i testsrc2=rate=30:size=1920x1080 \
  #   -re -i /home/das/test_audio/test_audio.aac \
  #   -c:v libx264 -b:v 10240k -maxrate:v 10000k -bufsize:v 10240k -preset ultrafast -r 25 -g 50 -pix_fmt yuv420p -flags2 local_header \
  #   -c:a aac -b:a 128k -ac 2 \
  #   -max_delay 500000 -bufsize 2000000 -fflags +genpts \
  #   -f rtp_mpegts \
  #   "rtp://239.0.0.1:6000?ttl=4&pkt_size=1326&localaddr=172.16.40.142"
  # '';
  # ''
  #   ${pkgs.ffmpeg}/bin/ffmpeg \
  #   -f lavfi \
  #   -re \
  #   -i testsrc2=rate=30:size=1920x1080 \
  #   -codec:v libx264 \
  #   -b:v 10240k \
  #   -maxrate:v 10000k \
  #   -bufsize:v 10240k \
  #   -preset ultrafast \
  #   -r 25 \
  #   -g 50 \
  #   -pix_fmt yuv420p \
  #   -flags2 local_header \
  #   -f mpegts \
  #   -transtype live \
  #   "rtp://239.0.0.1:6000?ttl=4&pkt_size=1326&localddr=172.16.40.142"
  # '';
in
{
  # sudo systemctl status ffmpeg-stream.service
  # sudo journalctl -u ffmpeg-stream.service
  # cat /etc/systemd/system/ffmpeg-stream.service
  systemd.services.ffmpeg-stream = {

    description = "FFmpeg Multicast Service";
    after = [ "network.target" ];

    serviceConfig = {
      ExecStart = "${ffmpegCmd}";
      Restart = "always";
      RestartSec = 10;
      StandardOutput = "journal";
      StandardError = "journal";

      # https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#Scheduling
      Nice = "-20";
      #CPUSchedulingPriority = "99";

      ### 🔐 Security Hardening Options ###
      NoNewPrivileges = true;             # Prevents privilege escalation
      PrivateTmp = true;                  # Isolates service temporary files
      ProtectSystem = "full";           # Restricts access to system files
      #ProtectSystem = "strict";           # Restricts access to system files
      #ProtectHome = "read-only";          # Readonly access to home directory
      ProtectHome = "yes";               # Blocks access to home directory
      ProtectKernelModules = true;        # Blocks module loading
      ProtectKernelLogs = true;           # Prevents access to kernel logs
      ProtectControlGroups = true;        # Restricts cgroup modifications
      MemoryDenyWriteExecute = true;      # Prevents memory exploits
      RestrictRealtime = true;            # Blocks real-time priority settings
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ]; # Restricts network access
      SystemCallFilter = [ "~@mount" "~@privileged" "~@resources" ]; # Blocks dangerous system calls
      LockPersonality = true;             # Prevents personality changes (defense against exploits)
      ReadOnlyPaths = "/usr";        # Makes important paths read-only
      #ReadOnlyPaths = "/etc /usr /home/das/test_audio/";        # Makes important paths read-only
      #wReadWritePaths = "/var/www/html";   # Only allow writing in this directory
      ProtectClock = true;                # Blocks modification of system clock
    };

  # # systemctl list-units --type target
  #   Install = {
  #     after = [ "network.target" ];
  #     #WantedBy = [ "default.target" ];
  #   };
  };
}
