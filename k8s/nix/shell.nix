# nix/shell.nix
#
# Development shell for K8s cluster.
#
{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    kubectl
    kubernetes-helm
    cilium-cli
    argocd
    step-cli
    socat
    expect
    sshpass
    jq
    mariadb      # mysql CLI for TiDB benchmarking
    sysbench
    nftables
    iproute2
  ];
  shellHook = ''
    echo "K8s MicroVM Cluster Development Shell (3 CP + 1 Worker)"
    echo ""
    echo "Quick start:"
    echo "  nix run .#k8s-check-host              # Verify host prereqs"
    echo "  sudo nix run .#k8s-network-setup      # Create network + haproxy LB"
    echo "  nix run .#k8s-start-all               # Build + start all VMs"
    echo "  nix run .#k8s-vm-ssh -- --node=cp0    # SSH to cp0"
    echo "  nix run .#k8s-lifecycle-test-all      # Run lifecycle tests"
    echo ""
    echo "Certs are baked into VM images at build time (no injection needed)"
  '';
}
