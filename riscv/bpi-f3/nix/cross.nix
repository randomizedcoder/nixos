# Cross-compilation target for the Banana Pi BPI-F3 (SpacemiT K1, RISC-V).
#
# We cross-compile from x86_64-linux -> riscv64.
#
# ISA / ABI baseline:
#   g : general purpose         (IMAFD_Zicsr_Zifencei)
#   c : compressed instructions
#   v : vector                  (RVV 1.0 — the K1's X60 cores implement RVV 1.0,
#                                unlike the Lichee Pi 4A's C910 which is stuck on v0.7)
#
# NOTE: targeting rv64gcv diverges from the riscv64 community binary caches, which
# build an rv64gc baseline. Consequently the *entire* closure is built locally — fine
# on a fast build host, but expect a long first build with no cache hits.
#
# lp64d: 64-bit long & pointers; GPRs, 64-bit FPRs and the stack used for parameter passing.
{
  config = "riscv64-unknown-linux-gnu";
  gcc.arch = "rv64gcv";
  gcc.abi = "lp64d";
}
