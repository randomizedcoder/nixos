#
# lan-access.nix — open l2 service ports to the lab LAN so `l` can reach them
#
# Companion to ./agent-seam.nix (which opens :50100 for the remote seam fleet).
# The default NixOS firewall is ON here (./firewall.nix is NOT imported), so a
# port is unreachable from l until it is listed below.
#
{ config, lib, pkgs, ... }:

{
  # ── SECURITY: unauthenticated, private-lab-LAN ONLY ──────────────────────────
  #
  # 8090/8091 are the Envoy grpc-web proxies that front `agent --serve-all`
  # (:50100) and `agent --serve-sessions` (:50080). `--serve-all` includes the
  # `sandbox`/`tools`/bash seams, so reaching :8090 is equivalent to CODE
  # EXECUTION on l2 — the same caveat ./agent-seam.nix states for :50100, now
  # over grpc-web. Only ever expose these on a private lab interface, never a
  # routable one.
  #
  #   8090  Envoy grpc-web  -> agent --serve-all      (:50100, loopback on l2)
  #   8091  Envoy grpc-web  -> agent --serve-sessions (:50080, loopback on l2)
  #   8092  Flutter web portal (static-web-server; serve with PORTAL_WEB_HOST=0.0.0.0
  #         and PORTAL_GRPC_WEB_URL/PORTAL_SESSIONS_GRPC_WEB_URL pointed at l2's IP)
  #   8095  llama.cpp MI50 (qwen3) — already 0.0.0.0-bound in ./llama-service.nix
  #   3000  Grafana — INERT until ./grafana.nix is imported and the container runs
  #
  # PORT OVERLAP: ./llama-service.nix reserves 8091-8094 for its (currently
  # unwired) CPU llama instances (port = 8090 + i). If those are ever enabled,
  # move the portal proxy/web ports off that range with the GRPC_WEB_*_PORT /
  # PORTAL_WEB_PORT env overrides (nix/portal/default.nix) — they are
  # configurable for exactly this reason.
  networking.firewall.allowedTCPPorts = [
    8090
    8091
    8092
    8095
    3000
  ];

  # ── Tighter alternative (recommended) ────────────────────────────────────────
  # LAN-open is convenient but broad. To admit only l (or the whole lab subnet),
  # drop `allowedTCPPorts` above and scope an nftables rule to the source address
  # (the default firewall uses the nftables backend, so extraInputRules applies):
  #
  #   networking.firewall.extraInputRules = ''
  #     ip saddr 172.16.50.0/24 tcp dport { 8090, 8091, 8092, 8095, 3000 } accept
  #   '';
  #
  # Replace 172.16.50.0/24 with l's exact address (e.g. 172.16.50.NN/32) to admit
  # only that one host.
}
