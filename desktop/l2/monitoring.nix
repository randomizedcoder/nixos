# Monitoring Configuration for L2 WiFi Access Point
# Performance monitoring and logging for CPU/IRQ optimizations

{ config, lib, pkgs, ... }:

let
  # Monitoring script for IRQ and CPU performance
  monitoringScript = pkgs.writeShellScript "network-monitoring" ''
    #!/bin/bash
    set -euo pipefail

    LOG_DIR="/var/log/network-performance"
    mkdir -p "$LOG_DIR"

    # Function to log with timestamp
    log() {
      echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_DIR/performance.log"
    }

    # Function to monitor IRQ distribution
    monitor_irqs() {
      log "=== IRQ Distribution ==="
      cat /proc/interrupts | grep -E "(enp1s0|iwlwifi)" | while read line; do
        log "IRQ: $line"
      done
    }

    # Function to monitor CPU utilization
    monitor_cpu() {
      log "=== CPU Utilization ==="
      mpstat -P ALL 1 1 | grep -E "(CPU|Average)" | while read line; do
        log "CPU: $line"
      done
    }

    # Function to monitor network statistics
    monitor_network() {
      log "=== Network Statistics ==="
      for interface in enp1s0 wlp35s0 wlp65s0 wlp66s0 wlp97s0; do
        if [[ -e "/sys/class/net/$interface/statistics/rx_packets" ]]; then
          rx_packets=$(cat "/sys/class/net/$interface/statistics/rx_packets")
          tx_packets=$(cat "/sys/class/net/$interface/statistics/tx_packets")
          rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes")
          tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes")
          log "Interface $interface: RX=$rx_packets pkts ($rx_bytes bytes), TX=$tx_packets pkts ($tx_bytes bytes)"
        fi
      done
    }

    # Function to monitor memory usage
    monitor_memory() {
      log "=== Memory Usage ==="
      free -h | while read line; do
        log "Memory: $line"
      done
    }

    # Function to monitor cache performance
    monitor_cache() {
      log "=== Cache Performance ==="
      if command -v perf >/dev/null 2>&1; then
        # Monitor cache misses for network processes
        for pid in $(pgrep -f "hostapd|nftables"); do
          if [[ -n "$pid" ]]; then
            cache_stats=$(perf stat -e cache-misses,cache-references -p "$pid" sleep 1 2>&1 | grep -E "(cache-misses|cache-references)" || true)
            log "PID $pid cache stats: $cache_stats"
          fi
        done
      fi
    }

    # Function to monitor system load
    monitor_load() {
      log "=== System Load ==="
      uptime | while read line; do
        log "Load: $line"
      done
    }

    # Function to monitor network optimization status
    monitor_optimization() {
      log "=== Network Optimization Status ==="

      # Check IRQ affinity
      log "IRQ Affinity Check:"
      for irq in 168 169 170 171 172 173 174 175; do
        if [[ -e "/proc/irq/$irq/smp_affinity_list" ]]; then
          affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
          log "  IRQ $irq -> CPU $affinity"
        fi
      done

      # Check CPU frequency
      log "CPU Frequency Check:"
      for cpu in {0..7}; do
        if [[ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]]; then
          freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
          governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
          log "  CPU $cpu: \$freq kHz (\$governor)"
        fi
      done

      # Check network optimization log
      if [[ -e "/tmp/network-optimization.log" ]]; then
        log "Network optimization log (last 10 lines):"
        tail -10 "/tmp/network-optimization.log" | while read line; do
          log "  $line"
        done
      fi
    }

    # Main monitoring function
    main() {
      log "Starting network performance monitoring"

      monitor_irqs
      monitor_cpu
      monitor_network
      monitor_memory
      monitor_cache
      monitor_load
      monitor_optimization

      log "Monitoring complete"
    }

    # Run monitoring
    main "$@"
  '';

  # Performance testing script
  performanceTestScript = pkgs.writeShellScript "performance-test" ''
    #!/bin/bash
    set -euo pipefail

    LOG_DIR="/var/log/network-performance"
    mkdir -p "$LOG_DIR"

    log() {
      echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_DIR/performance-test.log"
    }

    # Function to test network throughput
    test_throughput() {
      log "=== Network Throughput Test ==="

      # Start iperf3 server if not running
      if ! pgrep -f "iperf3 -s" >/dev/null; then
        log "Starting iperf3 server"
        iperf3 -s -D
        sleep 2
      fi

      # Test localhost throughput
      log "Testing localhost throughput..."
      iperf3 -c localhost -t 10 -J | jq -r '.end.sum_received.bits_per_second' | while read throughput; do
        log "Localhost throughput: $throughput bps"
      done
    }

    # Function to test latency
    test_latency() {
      log "=== Latency Test ==="

      # Test ping to localhost
      log "Testing ping latency to localhost..."
      ping -c 10 localhost | grep -E "(min|avg|max)" | while read line; do
        log "Ping: $line"
      done
    }

    # Function to test IRQ distribution
    test_irq_distribution() {
      log "=== IRQ Distribution Test ==="

      # Generate some network traffic
      log "Generating network traffic for IRQ testing..."

      # Start background ping
      ping -i 0.1 localhost >/dev/null 2>&1 &
      ping_pid=$!

      # Wait and check IRQ distribution
      sleep 5

      log "IRQ distribution during traffic:"
      cat /proc/interrupts | grep -E "(enp1s0|iwlwifi)" | head -10 | while read line; do
        log "  $line"
      done

      # Stop ping
      kill $ping_pid 2>/dev/null || true
    }

    # Function to test CPU utilization
    test_cpu_utilization() {
      log "=== CPU Utilization Test ==="

      # Monitor CPU usage during network activity
      log "Monitoring CPU usage for 10 seconds..."
      mpstat -P ALL 1 10 | grep -E "(CPU|Average)" | while read line; do
        log "CPU: $line"
      done
    }

    # Main test function
    main() {
      log "Starting performance tests"

      test_throughput
      test_latency
      test_irq_distribution
      test_cpu_utilization

      log "Performance tests complete"
    }

    main "$@"
  '';

in {
  # Monitoring service
  systemd.services.network-monitoring = {
    description = "Network performance monitoring";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "irq-affinity.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${monitoringScript}";
      StandardOutput = "journal";
      StandardError = "journal";
      Environment = "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.procps pkgs.sysstat pkgs.perf-tools pkgs.jq pkgs.gawk pkgs.gnugrep pkgs.gnused ]}";
    };
  };

  # Periodic monitoring timer
  systemd.timers.network-monitoring = {
    description = "Periodic network performance monitoring";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };

  # Performance testing service
  systemd.services.performance-test = {
    description = "Network performance testing";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "irq-affinity.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${performanceTestScript}";
      StandardOutput = "journal";
      StandardError = "journal";
      Environment = "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.procps pkgs.iperf3 pkgs.jq pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.iputils pkgs.sysstat ]}";
    };
  };

  # Periodic performance testing timer
  systemd.timers.performance-test = {
    description = "Periodic network performance testing";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };

  # Real-time monitoring service
  systemd.services.realtime-monitoring = {
    description = "Real-time network performance monitoring";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "irq-affinity.service" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "realtime-monitoring" ''
        #!/bin/bash
        set -euo pipefail

        LOG_DIR="/var/log/network-performance"
        mkdir -p "$LOG_DIR"

        log() {
          echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_DIR/realtime.log"
        }

        # Monitor IRQ distribution every 30 seconds
        while true; do
          log "=== IRQ Distribution ==="
          cat /proc/interrupts | grep -E "(enp1s0|iwlwifi)" | while read line; do
            log "$line"
          done

          log "=== CPU Utilization ==="
          mpstat -P ALL 1 1 | grep -E "(CPU|Average)" | while read line; do
            log "$line"
          done

          sleep 30
        done
      '';
      Restart = "always";
      RestartSec = "10";
      Environment = "PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.sysstat pkgs.gnugrep ]}";
    };
  };

  # Log rotation for monitoring logs
  services.logrotate.settings."network-performance" = {
    files = "/var/log/network-performance/*.log";
    rotate = 7;
    daily = true;
    compress = true;
    missingok = true;
    notifempty = true;
    postrotate = "systemctl reload rsyslog";
  };

  # Additional monitoring tools
  environment.systemPackages = with pkgs; [
    # Performance monitoring tools
    htop
    iotop
    iftop
    nethogs
    nload
    nmon
    sysstat
    perf-tools
    bpftrace

    # Network testing tools
    iperf3
    netperf
    wrk

    # System analysis tools
    strace
    ltrace
    valgrind
    gdb

    # JSON processing for logs
    jq

    # Additional monitoring
    glances
    s-tui
    stress-ng
  ];

  # Enable sysstat for historical monitoring
  services.sysstat = {
    enable = true;
  };

  # Configure rsyslog for monitoring
  services.rsyslogd = {
    enable = true;
    extraConfig = ''
      # Network performance monitoring
      if $programname == 'network-monitoring' then /var/log/network-performance/monitoring.log
      if $programname == 'performance-test' then /var/log/network-performance/test.log
      if $programname == 'realtime-monitoring' then /var/log/network-performance/realtime.log
    '';
  };
}