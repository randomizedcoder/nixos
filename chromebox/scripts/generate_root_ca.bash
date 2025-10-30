#!/etc/profiles/per-user/das/bin/bash
#
# generate_root_ca.bash - Generate root CA certificate
#
# This script generates a root CA certificate with 40-year validity.
# The root CA will be used to sign intermediate CA certificates.
#
# Usage: ./generate_root_ca.bash [output_directory]
#
# Exit codes:
#   0 - Success
#   1 - Error
#

set -euo pipefail

# Default output directory
OUTPUT_DIR="${1:-./pki}"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Change to output directory
cd "$OUTPUT_DIR"

# Root CA configuration
# 350400h ~= 14600d ~= 40 years
cat > ca-config.json << 'EOF'
{
  "CN": "Kubernetes Root CA",
  "key": {
    "algo": "ecdsa",
    "size": 521
  },
  "names": [
    {
      "C": "US",
      "L": "Los Angeles",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "CA"
    }
  ],
  "ca": {
    "expiry": "350400h"
  }
}
EOF

echo "Generating root CA certificate..."
echo "Output directory: $OUTPUT_DIR"

# Generate root CA
if cfssl gencert -initca ca-config.json | cfssljson -bare ca; then
    echo "✓ Root CA generated successfully"
    echo "  - ca.pem (public certificate)"
    echo "  - ca-key.pem (private key)"
    echo "  - ca.csr (certificate signing request)"
else
    echo "✗ Failed to generate root CA"
    exit 1
fi

# Set proper permissions
chmod 600 ca-key.pem
chmod 644 ca.pem ca.csr

echo
echo "Root CA certificate generated with 40-year validity"
echo "Keep the private key (ca-key.pem) secure and offline!"
