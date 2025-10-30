#!/etc/profiles/per-user/das/bin/bash
#
# rotate_service_certificates.bash - Rotate service certificates on a node
#
# This script rotates service certificates on a specific node using its
# intermediate CA. It includes node index-based jitter to prevent simultaneous
# rotation across nodes.
#
# Usage: ./rotate_service_certificates.bash [node_name] [output_directory]
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

# Extract node index from hostname using built-in regex
if [[ $NODE_NAME =~ ([0-9]+)$ ]]; then
    NODE_INDEX="${BASH_REMATCH[1]}"
else
    echo "Error: Could not extract node index from hostname: $NODE_NAME"
    exit 1
fi

# Calculate jitter window for this node
# Node 1: 0-1 hour (0-3600 seconds)
# Node 2: 1-2 hours (3600-7200 seconds)
# Node 3: 2-3 hours (7200-10800 seconds)
# etc.

# Base delay = (NODE_INDEX - 1) * 3600 seconds
BASE_DELAY=$(( (NODE_INDEX - 1) * 3600 ))

# Random jitter within the hour (5 minutes safety margin = 300 seconds)
# Jitter range: 300-3300 seconds (5-55 minutes)
JITTER=$(( RANDOM % 3000 + 300 ))

# Total delay = base delay + jitter
TOTAL_DELAY=$(( BASE_DELAY + JITTER ))

echo "Node $NODE_INDEX: Waiting $TOTAL_DELAY seconds ($((TOTAL_DELAY/60)) minutes)"
sleep $TOTAL_DELAY

echo "Starting certificate rotation for node $NODE_NAME..."

# Check if intermediate CA files exist
if [ ! -f "$OUTPUT_DIR/${NODE_NAME}-intermediate-ca.pem" ] || [ ! -f "$OUTPUT_DIR/${NODE_NAME}-intermediate-ca-key.pem" ]; then
    echo "Error: Intermediate CA files not found for $NODE_NAME"
    exit 1
fi

# Change to output directory
cd "$OUTPUT_DIR"

# Service certificate configuration
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

# Function to rotate service certificate
rotate_service_cert() {
    local service_name="$1"
    local profile="$2"
    local cn="$3"
    local san="$4"

    echo "Rotating $service_name certificate..."

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

    # Generate new certificate
    if cfssl gencert -ca "${NODE_NAME}-intermediate-ca.pem" -ca-key "${NODE_NAME}-intermediate-ca-key.pem" -config service-config.json -profile "$profile" "${service_name}.json" | cfssljson -bare "${service_name}-new"; then
        echo "  ✓ New $service_name certificate generated"

        # Set proper permissions
        chmod 600 "${service_name}-new-key.pem"
        chmod 644 "${service_name}-new.pem" "${service_name}-new.csr"

        # Clean up
        rm "${service_name}.json"

        return 0
    else
        echo "  ✗ Failed to generate new $service_name certificate"
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

# Rotate service certificates
echo "Rotating etcd certificates..."
rotate_service_cert "etcd-server" "etcd-server" "etcd-server-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
rotate_service_cert "etcd-peer" "etcd-peer" "etcd-peer-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
rotate_service_cert "etcd-client" "etcd-client" "etcd-client-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""

echo "Rotating Kubernetes API server certificates..."
rotate_service_cert "kube-apiserver" "kube-apiserver" "kube-apiserver-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\", \"kubernetes\", \"kubernetes.default\", \"kubernetes.default.svc\", \"kubernetes.default.svc.cluster.local\", \"10.96.0.1\""
rotate_service_cert "kube-apiserver-etcd-client" "kube-apiserver-etcd-client" "kube-apiserver-etcd-client-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
rotate_service_cert "kube-apiserver-kubelet-client" "kube-apiserver-kubelet-client" "kube-apiserver-kubelet-client-$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""

echo "Rotating control plane certificates..."
rotate_service_cert "kube-controller-manager" "kube-controller-manager" "system:kube-controller-manager" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
rotate_service_cert "kube-scheduler" "kube-scheduler" "system:kube-scheduler" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""

echo "Rotating node certificates..."
rotate_service_cert "kubelet" "kubelet" "system:node:$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
rotate_service_cert "kubelet-client" "kubelet-client" "system:node:$NODE_NAME" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""
rotate_service_cert "kube-proxy" "kube-proxy" "system:kube-proxy" "\"$NODE_NAME\", \"$NODE_IP\", \"127.0.0.1\""

echo
echo "✓ All service certificates rotated successfully for $NODE_NAME"
echo "New certificates have 2-week validity and are signed by the intermediate CA"
