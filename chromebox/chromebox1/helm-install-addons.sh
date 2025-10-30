#!/bin/bash
# Helmfile installation script for Cilium and Hubble
# This script installs Cilium and Hubble using Helmfile for declarative management

set -euo pipefail

# Configuration
CILIUM_VERSION="1.18.2"
NAMESPACE="kube-system"
HELMFILE_PATH="/home/das/nixos/chromebox/chromebox1/helmfile.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available and cluster is accessible
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    log_info "Kubernetes cluster is accessible"
}

# Check if Helm and Helmfile are available
check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed or not in PATH"
        exit 1
    fi

    if ! command -v helmfile &> /dev/null; then
        log_error "Helmfile is not installed or not in PATH"
        exit 1
    fi

    log_info "Helm is available: $(helm version --short)"
    log_info "Helmfile is available: $(helmfile version)"
}

# Install Cilium and Hubble using Helmfile
install_with_helmfile() {
    log_info "Installing Cilium and Hubble using Helmfile..."

    if [ ! -f "${HELMFILE_PATH}" ]; then
        log_error "Helmfile configuration not found at ${HELMFILE_PATH}"
        exit 1
    fi

    # Update repositories
    log_info "Updating Helm repositories..."
    helmfile -f "${HELMFILE_PATH}" repos

    # Apply the Helmfile configuration
    log_info "Applying Helmfile configuration..."
    helmfile -f "${HELMFILE_PATH}" apply

    log_info "Cilium and Hubble installation completed via Helmfile"
}

# Wait for Cilium to be ready
wait_for_cilium() {
    log_info "Waiting for Cilium to be ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=cilium -n ${NAMESPACE} --timeout=300s
    log_info "Cilium is ready"
}

# Main installation function
main() {
    log_info "Starting Cilium and Hubble installation via Helmfile"

    check_kubectl
    check_helm
    install_with_helmfile
    wait_for_cilium

    log_info "Cilium and Hubble installation completed successfully!"
    log_info "You can now use:"
    log_info "  - kubectl get pods -n ${NAMESPACE}  # Check Cilium pods"
    log_info "  - cilium status                    # Check Cilium status"
    log_info "  - kubectl port-forward -n ${NAMESPACE} svc/hubble-ui 12000:80  # Access Hubble UI"
    log_info "  - helmfile -f ${HELMFILE_PATH} status  # Check Helmfile status"
}

# Run main function
main "$@"
