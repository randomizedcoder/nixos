#!/etc/profiles/per-user/das/bin/bash
#
# generate_service_certificates.bash - Generate service certificates for a node
#
# This script generates service certificates (etcd, kube-apiserver, kubelet, etc.)
# for a specific node using its intermediate CA.
#
# Usage: ./generate_service_certificates.bash [node_name] [output_directory]
#
# Arguments:
#   node_name        - Name of the node (e.g., chromebox1)
#   output_directory - Directory containing intermediate CA files (default: ./pki)
#
# Exit codes:
#   0 - Success
#   1 - Error
#

set -euo pipefail

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <node_name> [output_directory]"
    echo "Example: $0 chromebox1 ./pki"
    exit 1
fi

NODE_NAME="$1"
OUTPUT_DIR="${2:-./pki}"

# Check if intermediate CA files exist
if [ ! -f "$OUTPUT_DIR/${NODE_NAME}-intermediate-ca.pem" ] || [ ! -f "$OUTPUT_DIR/${NODE_NAME}-intermediate-ca-key.pem" ]; then
    echo "Error: Intermediate CA files not found for $NODE_NAME"
    echo "Please run generate_intermediate_cas.bash first"
    exit 1
fi

# Change to output directory
cd "$OUTPUT_DIR"

echo "Generating service certificates for $NODE_NAME..."
echo "Output directory: $OUTPUT_DIR"
echo

# Service certificate configuration
# 336h ~= 14 days
cat > service-config.json << 'EOF'
{
  "signing": {
    "default": {
      "expiry": "336h"
    },
    "profiles": {
      "etcd-server": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "ext_key_usage": ["server auth", "client auth"]
      },
      "etcd-peer": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "ext_key_usage": ["server auth", "client auth"]
      },
      "etcd-client": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "client auth"],
        "ext_key_usage": ["client auth"]
      },
      "kube-apiserver": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "ext_key_usage": ["server auth", "client auth"]
      },
      "kube-apiserver-etcd-client": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "client auth"],
        "ext_key_usage": ["client auth"]
      },
      "kube-apiserver-kubelet-client": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "client auth"],
        "ext_key_usage": ["client auth"]
      },
      "kube-controller-manager": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "client auth"],
        "ext_key_usage": ["client auth"]
      },
      "kube-scheduler": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "client auth"],
        "ext_key_usage": ["client auth"]
      },
      "kube-proxy": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "client auth"],
        "ext_key_usage": ["client auth"]
      },
      "kubelet": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "ext_key_usage": ["server auth", "client auth"]
      },
      "kubelet-client": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "client auth"],
        "ext_key_usage": ["client auth"]
      }
    }
  }
}
EOF

# Function to generate service certificate
generate_service_cert() {
    local service_name="$1"
    local profile="$2"
    local cn="$3"
    local san="$4"

    echo "Generating $service_name certificate..."

    # Create certificate request
    cat > "${service_name}.json" << EOF
{
  "CN": "$cn",
  "key": {
    "algo": "ecdsa",
    "size": 521
  },
  "names": [
    {
      "C": "US",
      "L": "Los Angeles",
      "O": "Kubernetes",
      "OU": "Service",
      "ST": "CA"
    }
  ],
  "hosts": [$san]
}
EOF

    # Generate certificate
    if cfssl gencert -ca "${NODE_NAME}-intermediate-ca.pem" -ca-key "${NODE_NAME}-intermediate-ca-key.pem" -config service-config.json -profile "$profile" "${service_name}.json" | cfssljson -bare "$service_name"; then
        echo "  ✓ $service_name certificate generated"

        # Set proper permissions
        chmod 600 "${service_name}-key.pem"
        chmod 644 "${service_name}.pem" "${service_name}.csr"

        # Clean up
        rm "${service_name}.json"

        return 0
    else
        echo "  ✗ Failed to generate $service_name certificate"
        rm -f "${service_name}.json"
        return 1
    fi
}

# Get node IP address from hosts.nix or use default
# This should be updated to match your actual node IPs
case "$NODE_NAME" in
    chromebox1) NODE_IP="172.16.40.61" ;;
    chromebox2) NODE_IP="172.16.40.62" ;;
    chromebox3) NODE_IP="172.16.40.63" ;;
    *) NODE_IP="127.0.0.1" ;;
esac

# Generate service certificates
echo "Generating etcd certificates..."
generate_service_cert "etcd-server" "etcd-server" "etcd-server-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
generate_service_cert "etcd-peer" "etcd-peer" "etcd-peer-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
generate_service_cert "etcd-client" "etcd-client" "etcd-client-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""

echo "Generating Kubernetes API server certificates..."
generate_service_cert "kube-apiserver" "kube-apiserver" "kube-apiserver-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\", \"kubernetes\", \"kubernetes.default\", \"kubernetes.default.svc\", \"kubernetes.default.svc.cluster.local\", \"10.96.0.1\""
generate_service_cert "kube-apiserver-etcd-client" "kube-apiserver-etcd-client" "kube-apiserver-etcd-client-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
generate_service_cert "kube-apiserver-kubelet-client" "kube-apiserver-kubelet-client" "kube-apiserver-kubelet-client-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""

echo "Generating control plane certificates..."
generate_service_cert "kube-controller-manager" "kube-controller-manager" "system:kube-controller-manager" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
generate_service_cert "kube-scheduler" "kube-scheduler" "system:kube-scheduler" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""

echo "Generating node certificates..."
generate_service_cert "kubelet" "kubelet" "system:node:$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
generate_service_cert "kubelet-client" "kubelet-client" "system:node:$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
generate_service_cert "kube-proxy" "kube-proxy" "system:kube-proxy" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""

echo
echo "✓ All service certificates generated successfully for $NODE_NAME"
echo "Each certificate has 2-week validity and is signed by the intermediate CA"
