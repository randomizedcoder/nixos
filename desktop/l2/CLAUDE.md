# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS configuration for a high-performance WiFi access point (L2 system) with:
- AMD Ryzen Threadripper PRO 3945WX (12 cores/24 threads)
- MediaTek MT7915e dual-band WiFi 6
- Multiple 10GbE NICs (Intel X710, 82599ES, Broadcom BCM57416, Aquantia Atlantic)
- NVIDIA RTX 3070 for LLM inference

## SSH Access

```bash
ssh l2
```

The `l2` host alias is configured in `~/.ssh/config`.

## Commands

```bash
# Rebuild and switch to new configuration
sudo nixos-rebuild switch

# Test configuration without switching
sudo nixos-rebuild test

# View service status
systemctl status hostapd kea-dhcp4-server pdns-recursor radvd nftables

# View firewall rules
sudo nft list ruleset

# Check service logs
journalctl -u hostapd -f
journalctl -u kea-dhcp4-server -f

# Network optimization results
cat /tmp/network-optimization.log

# IRQ distribution
cat /proc/interrupts | grep -E "(enp1s0|mt7915)"
```

## Architecture

```
Internet (enp1s0 - WAN, Aquantia Atlantic)
    ↓
[NAT/Firewall - nftables] ← cores 0-7
    ↓
[Bridge (br0)] ← 192.168.1.1/24, fd00::1/64
    ↓
[WiFi AP - MediaTek MT7915e]
    - wlan_2g: 2.4GHz, channel 6
    - wlan_5g: 5GHz, channel 36
    ↓
[Network Services] ← cores 8-15
    - Kea DHCP4 (192.168.1.100-200)
    - PowerDNS Recursor
    - radvd IPv6 RA
```

## CPU Core Allocation

| Cores | Purpose | Services |
|-------|---------|----------|
| 0-7 | Network processing (isolated, no ticks) | hostapd, nftables, CAKE QoS |
| 8-15 | Network services | Kea DHCP, PowerDNS, radvd |
| 16-23 | Userland | Monitoring, llama.cpp, user processes |

## Key Files

| File | Purpose |
|------|---------|
| `flake.nix` | Flake inputs, overlays, package configuration |
| `configuration.nix` | Main system config, imports all modules |
| `hostapd-multi.nix` | WiFi AP, DHCP (Kea), DNS (PowerDNS), IPv6 RA (radvd) |
| `firewall.nix` | nftables rules, NAT, connection tracking |
| `network-interfaces.nix` | Static IP config for 10GbE NICs |
| `ethtool-nics.nix` | Per-NIC hardware tuning (ring buffers, offloads, ntuple) |
| `sysctl.nix` | Kernel parameters, TCP/UDP buffers, conntrack |
| `bbr3-module.nix` | BBRv3 congestion control (out-of-tree L4S kernel) |
| `systemd-slices.nix` | CPU/memory isolation, service slices |
| `kernel-params.nix` | Boot params (isolcpus, nohz_full, rcu_nocbs) |
| `llama-service.nix` | llama.cpp inference server on RTX 3070 |

## Key Patterns

- **Modular design**: Each concern in separate `.nix` file
- **L4S networking**: DualPI2 AQM, BBRv3 congestion control (bleeding-edge)
- **Hardware-specific tuning**: Detailed ethtool config per NIC model with comments explaining why
- **CPU isolation**: `isolcpus=0-7 nohz_full=0-7 rcu_nocbs=0-7` for dedicated network cores
- **Service prioritization**: Real-time scheduling (-10 to -5 nice) for critical network services

## Testing Scripts

- `test-ntuple.sh` - n-tuple filter testing on Intel 82599ES
- `firewall-test.sh` - Firewall rule validation
- `wifi-aqm-tune.sh` - WiFi AQM tuning
- `verify-dualpi2.sh` - DualPI2 qdisc verification
- `irq-slice-analysis.sh` - IRQ distribution analysis

## Kernel Configuration

- **Kernel**: Stable `linuxPackages` (not latest) for NVIDIA driver compatibility
- **BBRv3**: Out-of-tree module built from L4STeam/linux repo (`bbr3-module.nix`)
  - Renamed to `tcp_bbr3` to avoid conflict with in-kernel `tcp_bbr`
  - Requires kernel API compatibility patches for 6.18+ (prandom_u32_max → get_random_u32_below, cong_control signature)
- **Key kernel modules**: `bnxt_en` (Broadcom NIC), `bnxt_re` (RoCEv2 RDMA), `sch_dualpi2` (L4S AQM), `nvidia`, `nvidia_uvm`
- **Blacklisted**: `nouveau`
- **Boot params** (`kernel-params.nix`):
  - `isolcpus=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19` - isolate network cores
  - `intel_pstate=performance`, `cpufreq.default_governor=performance`
  - `numa_balancing=0`, `elevator=bfq`
  - `cfg80211.ieee80211_regdom=US`, `iwlwifi.power_save=0`

```bash
# Verify BBRv3
lsmod | grep bbr3
cat /proc/sys/net/ipv4/tcp_available_congestion_control

# Update BBRv3 hash after L4S repo changes
nix-prefetch-github L4STeam linux --rev <commit>
```

## Graphics Setup

Dual GPU configuration (`hardware-graphics.nix`):
- **NVIDIA RTX 3070**: Headless compute only (CUDA/llama.cpp), open source kernel modules
- **AMD WX 2100**: Display output (handled by amdgpu in initrd)

```bash
# GPU monitoring
nvtop           # NVIDIA GPU
btop-rocm       # AMD GPU (via ROCm)
lact            # AMD GPU control daemon
rocm-smi        # AMD ROCm info
```

Configuration choices:
- `services.xserver.enable = false` - no X server
- `hardware.nvidia.open = true` - open source NVIDIA kernel modules (Ampere+)
- `hardware.nvidia.modesetting.enable = false` - headless, no display

## Local LLM Setup

llama.cpp service (`llama-service.nix`) running on RTX 3070:

| Setting | Value |
|---------|-------|
| Model | Qwen/Qwen2.5-3B-Instruct-GGUF (q4_k_m) |
| Port | 8090 |
| Context | 8192 tokens |
| Flash attention | enabled |
| Metrics | enabled (Prometheus) |

```bash
# Test LLM
curl http://localhost:8090/health
journalctl -u llama-cpp-rtx3070 -f

# Update local nixpkgs for llama-cpp changes
nix flake update nixpkgs-local
```

Uses `nixpkgs-local` input for latest llama-cpp module with CUDA support. The module is imported with `disabledModules` to override the default.

## Home Manager (home.nix)

User `das` configuration managed via home-manager (imported in flake.nix, not configuration.nix).

Key package groups:
- **Networking**: ethtool, tcpdump, wireshark, iperf2, netperf, flent, bpftools
- **Go development**: go, gopls, golint, golangci-lint, delve, gdlv
- **AMD GPU**: rocmPackages (rocminfo, rocm-smi, rccl), btop-rocm, lact, ollama-rocm
- **Build tools**: gcc, automake, gnumake, pkg-config, gdb
- **Media**: ffmpeg_7-full

Programs configured:
- `bash` with completion and aliases (`k = kubectl`)
- `vim` with vim-airline, mouse support
- `git` (user: randomizedcoder)

## Netlink Debugging

Monitor hostapd-kernel communication:
```bash
sudo modprobe nlmon
sudo ip link add nlmon0 type nlmon
sudo ip link set dev nlmon0 up
sudo tcpdump -i nlmon0 -w netlink.pcap
```
