# nix/network-setup.nix
#
# TAP/bridge/NAT setup and teardown for K8s MicroVM cluster.
# Creates k8sbr0 bridge with 4 TAP devices, dual-stack NAT, and
# haproxy for apiserver load balancing across control plane nodes.
#
{ pkgs }:
let
  constants = import ./constants.nix;
  nodes = (import ./nodes.nix { inherit constants; }).definitions;
  inherit (constants.network) bridge gateway4 gateway6 subnet4 subnet6;

  tapList = builtins.map (n: constants.network.taps.${n}) constants.nodeNames;

  # Control plane node IPs for haproxy backend
  cpNodes = builtins.filter (n: nodes.${n}.role == "control-plane") constants.nodeNames;
  cpIps = builtins.map (n: constants.network.ipv4.${n}) cpNodes;

  # haproxy config for apiserver load balancing
  haproxyConfig = pkgs.writeText "k8s-haproxy.cfg" ''
    global
      daemon
      pidfile /run/k8s-haproxy.pid
      maxconn 256

    defaults
      mode tcp
      timeout connect 5s
      timeout client 30s
      timeout server 30s

    frontend k8s-apiserver
      bind ${gateway4}:6443
      default_backend k8s-apiserver-backends

    backend k8s-apiserver-backends
      option tcp-check
      balance roundrobin
      ${builtins.concatStringsSep "\n    " (builtins.map (ip:
        "server ${ip} ${ip}:6443 check inter 5s fall 3 rise 2"
      ) cpIps)}
  '';
in
{
  check = pkgs.writeShellApplication {
    name = "k8s-check-host";
    runtimeInputs = with pkgs; [ kmod coreutils ];
    text = ''
      echo "=== K8s MicroVM Host Environment Check ==="
      errors=0

      if [[ -c /dev/net/tun ]]; then
        echo "OK /dev/net/tun exists"
      else
        echo "FAIL /dev/net/tun not found"
        echo "  Run: sudo modprobe tun"
        errors=$((errors + 1))
      fi

      if lsmod | grep -q vhost_net; then
        echo "OK vhost_net module loaded"
      elif [[ -c /dev/vhost-net ]]; then
        echo "OK /dev/vhost-net exists"
      else
        echo "FAIL vhost_net not available"
        echo "  Run: sudo modprobe vhost_net"
        errors=$((errors + 1))
      fi

      if lsmod | grep -q bridge; then
        echo "OK bridge module loaded"
      else
        echo "INFO bridge module not loaded (will be loaded during setup)"
      fi

      if sudo -n true 2>/dev/null; then
        echo "OK sudo access available"
      else
        echo "FAIL sudo access required for network setup"
        errors=$((errors + 1))
      fi

      if [[ $errors -gt 0 ]]; then
        echo ""
        echo "Host environment check failed with $errors error(s)"
        exit 1
      else
        echo ""
        echo "Host environment ready for K8s cluster"
      fi
    '';
  };

  setup = pkgs.writeShellApplication {
    name = "k8s-network-setup";
    runtimeInputs = with pkgs; [ iproute2 kmod nftables acl haproxy procps ];
    text = ''
      echo "=== K8s MicroVM Network Setup ==="

      if [[ $EUID -ne 0 ]]; then
        echo "ERROR: Run with sudo: sudo nix run .#k8s-network-setup"
        exit 1
      fi

      REAL_USER="''${SUDO_USER:-$USER}"
      if [[ "$REAL_USER" == "root" ]]; then
        echo "ERROR: Run via 'sudo nix run .#k8s-network-setup' as a regular user"
        exit 1
      fi
      echo "Setting up network for user: $REAL_USER"

      # Load required kernel modules
      modprobe tun
      modprobe vhost_net
      modprobe bridge

      # Create bridge with dual-stack
      if ! ip link show ${bridge} &>/dev/null; then
        echo "Creating bridge ${bridge}..."
        ip link add ${bridge} type bridge
        ip addr add ${gateway4}/24 dev ${bridge}
        ip -6 addr add ${gateway6}/64 dev ${bridge}
        ip link set ${bridge} up
      else
        echo "Bridge ${bridge} already exists"
      fi

      # Create TAP devices for each node
      ${builtins.concatStringsSep "\n" (builtins.map (tap: ''
      if ip link show ${tap} &>/dev/null; then
        echo "Removing existing TAP device ${tap}..."
        ip link del ${tap}
      fi
      echo "Creating TAP device ${tap} for user $REAL_USER..."
      ip tuntap add dev ${tap} mode tap multi_queue user "$REAL_USER"
      ip link set ${tap} master ${bridge}
      ip link set ${tap} up
      '') tapList)}

      # Enable vhost-net access
      if [[ -c /dev/vhost-net ]]; then
        if command -v setfacl &>/dev/null; then
          setfacl -m "u:$REAL_USER:rw" /dev/vhost-net
          echo "vhost-net enabled (ACL for $REAL_USER)"
        elif getent group kvm &>/dev/null; then
          chgrp kvm /dev/vhost-net
          chmod 660 /dev/vhost-net
          echo "vhost-net enabled (kvm group)"
        else
          echo "WARNING: Cannot set vhost-net permissions securely"
        fi
      fi

      # NAT for dual-stack internet access
      echo "Configuring NAT..."
      nft add table inet k8s-nat 2>/dev/null || true
      nft flush table inet k8s-nat 2>/dev/null || true
      nft -f - <<EOF
table inet k8s-nat {
  chain postrouting {
    type nat hook postrouting priority 100;
    # Skip NAT for VM-to-VM traffic (stays on bridge)
    ip saddr ${subnet4} ip daddr ${subnet4} accept
    ip6 saddr ${subnet6} ip6 daddr ${subnet6} accept
    # NAT only outbound traffic to the internet
    ip saddr ${subnet4} masquerade
    ip6 saddr ${subnet6} masquerade
  }
  chain forward {
    type filter hook forward priority 0;
    iifname "${bridge}" accept
    oifname "${bridge}" ct state related,established accept
  }
}
EOF

      # Enable IP forwarding (v4 + v6)
      sysctl -w net.ipv4.ip_forward=1 >/dev/null
      sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

      # Start haproxy for apiserver load balancing
      if [[ -f /run/k8s-haproxy.pid ]] && kill -0 "$(cat /run/k8s-haproxy.pid)" 2>/dev/null; then
        echo "Stopping existing haproxy..."
        kill "$(cat /run/k8s-haproxy.pid)" 2>/dev/null || true
        sleep 1
      fi
      echo "Starting haproxy for apiserver LB on ${gateway4}:6443..."
      haproxy -f ${haproxyConfig}
      echo "haproxy started (PID: $(cat /run/k8s-haproxy.pid))"

      echo ""
      echo "Network ready. Nodes:"
      ${builtins.concatStringsSep "\n" (builtins.map (n: ''
      echo "  ${n}: ${constants.network.ipv4.${n}} / ${constants.network.ipv6.${n}} (${constants.network.taps.${n}})"
      '') constants.nodeNames)}
    '';
  };

  teardown = pkgs.writeShellApplication {
    name = "k8s-network-teardown";
    runtimeInputs = with pkgs; [ iproute2 nftables ];
    text = ''
      echo "=== K8s MicroVM Network Teardown ==="

      if [[ $EUID -ne 0 ]]; then
        echo "ERROR: Run with sudo: sudo nix run .#k8s-network-teardown"
        exit 1
      fi

      # Stop haproxy
      if [[ -f /run/k8s-haproxy.pid ]]; then
        kill "$(cat /run/k8s-haproxy.pid)" 2>/dev/null && \
          echo "Stopped haproxy" || true
        rm -f /run/k8s-haproxy.pid
      fi

      # Remove TAP devices
      ${builtins.concatStringsSep "\n" (builtins.map (tap: ''
      if ip link show ${tap} &>/dev/null; then
        ip link del ${tap}
        echo "Removed TAP device ${tap}"
      fi
      '') tapList)}

      # Remove bridge
      if ip link show ${bridge} &>/dev/null; then
        ip link set ${bridge} down
        ip link del ${bridge}
        echo "Removed bridge ${bridge}"
      fi

      # Remove NAT rules
      nft delete table inet k8s-nat 2>/dev/null && \
        echo "Removed NAT rules" || true

      echo "Network teardown complete"
    '';
  };
}
