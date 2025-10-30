#!/etc/profiles/per-user/das/bin/bash
#
# generate_intermediate_cas.bash - Generate intermediate CA certificates
#
# This script generates intermediate CA certificates for each chromebox node.
# Each intermediate CA is signed by the root CA and has 2-month validity.
#
# Usage: ./generate_intermediate_cas.bash [output_directory] [node_list]
#
# Arguments:
#   output_directory - Directory containing root CA files (default: ./pki)
#   node_list        - Comma-separated list of node names (default: chromebox1,chromebox2,chromebox3)
#
# Exit codes:
#   0 - Success
#   1 - Error
#

set -euo pipefail

# Default values
OUTPUT_DIR="${1:-./pki}"
NODE_LIST="${2:-chromebox1,chromebox2,chromebox3}"

# Check if root CA files exist
if [ ! -f "$OUTPUT_DIR/ca.pem" ] || [ ! -f "$OUTPUT_DIR/ca-key.pem" ]; then
    echo "Error: Root CA files not found in $OUTPUT_DIR"
    echo "Please run generate_root_ca.bash first"
    exit 1
fi

# Change to output directory
cd "$OUTPUT_DIR"

# Split node list into array
IFS=',' read -ra NODES <<< "$NODE_LIST"

echo "Generating intermediate CA certificates..."
echo "Output directory: $OUTPUT_DIR"
echo "Nodes: ${NODES[*]}"
echo

# CFSSL configuration for intermediate CAs
# 1460h ~= 60 days
cat > cfssl-config.json << 'EOF'
{
  "signing": {
    "default": {
      "expiry": "1460h"
    },
    "profiles": {
      "intermediate_ca": {
        "expiry": "1460h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "ca_constraint": {
          "is_ca": true,
          "max_pathlen": 0
        }
      }
    }
  }
}
EOF

# Generate intermediate CA for each node
for node in "${NODES[@]}"; do
    echo "Generating intermediate CA for $node..."

    # Create intermediate CA configuration
    cat > "${node}-intermediate-ca-config.json" << EOF
{
  "CN": "Kubernetes Intermediate CA - $node",
  "key": {
    "algo": "ecdsa",
    "size": 521
  },
  "names": [
    {
      "C": "US",
      "L": "Los Angeles",
      "O": "Kubernetes",
      "OU": "Intermediate CA",
      "ST": "CA"
    }
  ],
  "ca": {
    "expiry": "1460h"
  }
}
EOF

    # Generate intermediate CA
    if cfssl gencert -initca "${node}-intermediate-ca-config.json" | cfssljson -bare "${node}-intermediate-ca"; then
        echo "  ✓ Intermediate CA generated for $node"
    else
        echo "  ✗ Failed to generate intermediate CA for $node"
        exit 1
    fi

    # Sign intermediate CA with root CA
    if cfssl sign -ca ca.pem -ca-key ca-key.pem -config cfssl-config.json -profile intermediate_ca "${node}-intermediate-ca.csr" | cfssljson -bare "${node}-intermediate-ca"; then
        echo "  ✓ Intermediate CA signed by root CA"
    else
        echo "  ✗ Failed to sign intermediate CA for $node"
        exit 1
    fi

    # Set proper permissions
    chmod 600 "${node}-intermediate-ca-key.pem"
    chmod 644 "${node}-intermediate-ca.pem" "${node}-intermediate-ca.csr"

    echo "  - ${node}-intermediate-ca.pem (public certificate)"
    echo "  - ${node}-intermediate-ca-key.pem (private key)"
    echo
done

echo "✓ All intermediate CA certificates generated successfully"
echo "Each intermediate CA has 2-month validity and is signed by the root CA"
