

nix-build --max-jobs 0 -E << EOF
(import <nixpkgs> {}).writeText "test" "$(date)"
EOF