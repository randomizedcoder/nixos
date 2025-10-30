#!/etc/profiles/per-user/das/bin/bash
#
# copy_intermediate_cas.bash - Copy intermediate CA certificates to nodes
#
# This script securely copies intermediate CA certificates to the target nodes.
# It uses SSH to copy files and sets proper permissions.
#
# Usage: ./copy_intermediate_cas.bash [source_directory] [node_list]
#
# Arguments:
#   source_directory - Directory containing intermediate CA files (default: ./pki)
#   node_list        - Comma-separated list of node names (default: chromebox1,chromebox2,chromebox3)
#
# Exit codes:
#   0 - Success
#   1 - Error
#

set -euo pipefail

# Default values
SOURCE_DIR="${1:-./pki}"
NODE_LIST="${2:-chromebox1,chromebox2,chromebox3}"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory $SOURCE_DIR does not exist"
    exit 1
fi

# Split node list into array
IFS=',' read -ra NODES <<< "$NODE_LIST"

echo "Copying intermediate CA certificates to nodes..."
echo "Source directory: $SOURCE_DIR"
echo "Nodes: ${NODES[*]}"
echo

# Function to copy intermediate CA to a node
copy_to_node() {
    local node="$1"
    local source_dir="$2"

    echo "Copying intermediate CA to $node..."

    # Check if intermediate CA files exist
    if [ ! -f "$source_dir/${node}-intermediate-ca.pem" ] || [ ! -f "$source_dir/${node}-intermediate-ca-key.pem" ]; then
        echo "  ✗ Intermediate CA files not found for $node"
        return 1
    fi

    # Create PKI directory on target node
    if ssh "$node" "mkdir -p /etc/kubernetes/pki"; then
        echo "  ✓ Created PKI directory on $node"
    else
        echo "  ✗ Failed to create PKI directory on $node"
        return 1
    fi

    # Copy intermediate CA certificate
    if scp "$source_dir/${node}-intermediate-ca.pem" "$node:/etc/kubernetes/pki/intermediate-ca.crt"; then
        echo "  ✓ Copied intermediate CA certificate to $node"
    else
        echo "  ✗ Failed to copy intermediate CA certificate to $node"
        return 1
    fi

    # Copy intermediate CA private key
    if scp "$source_dir/${node}-intermediate-ca-key.pem" "$node:/etc/kubernetes/pki/intermediate-ca.key"; then
        echo "  ✓ Copied intermediate CA private key to $node"
    else
        echo "  ✗ Failed to copy intermediate CA private key to $node"
        return 1
    fi

    # Copy root CA certificate
    if scp "$source_dir/ca.pem" "$node:/etc/kubernetes/pki/ca.crt"; then
        echo "  ✓ Copied root CA certificate to $node"
    else
        echo "  ✗ Failed to copy root CA certificate to $node"
        return 1
    fi

    # Set proper permissions on target node
    if ssh "$node" "chmod 600 /etc/kubernetes/pki/intermediate-ca.key && chmod 644 /etc/kubernetes/pki/intermediate-ca.crt /etc/kubernetes/pki/ca.crt"; then
        echo "  ✓ Set proper permissions on $node"
    else
        echo "  ✗ Failed to set permissions on $node"
        return 1
    fi

    echo "  ✓ Successfully copied intermediate CA to $node"
    return 0
}

# Copy intermediate CA to each node
failed_nodes=()
for node in "${NODES[@]}"; do
    if copy_to_node "$node" "$SOURCE_DIR"; then
        echo "  ✓ $node completed successfully"
    else
        echo "  ✗ $node failed"
        failed_nodes+=("$node")
    fi
    echo
done

# Report results
if [ ${#failed_nodes[@]} -eq 0 ]; then
    echo "✓ All intermediate CA certificates copied successfully"
    echo "Each node now has:"
    echo "  - /etc/kubernetes/pki/ca.crt (root CA certificate)"
    echo "  - /etc/kubernetes/pki/intermediate-ca.crt (intermediate CA certificate)"
    echo "  - /etc/kubernetes/pki/intermediate-ca.key (intermediate CA private key)"
    exit 0
else
    echo "✗ Failed to copy intermediate CA to: ${failed_nodes[*]}"
    exit 1
fi
