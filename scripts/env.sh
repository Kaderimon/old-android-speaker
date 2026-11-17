# Shared settings for the build scripts (sourced, not run). Override any of them via environment.

# project root = the folder above scripts/ (works from WSL, Linux or macOS)
W="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# build tree (toolchains, sources, intermediate files): ~/w200-build

# Target CPU of the phone, in Zig/LLVM spelling. cortex_a7 = MediaTek MT6589 (THL W200).
# Other 32-bit ARM phones: cortex_a9 is a safe choice for most ARMv7 SoCs of the Android 4.x era,
# cortex_a8 for the oldest ones. A wrong (too new) value makes the binaries crash with SIGILL.
W200_CPU="${W200_CPU:-cortex_a7}"
ZIG_CPU="$W200_CPU"            # zig cc -mcpu=...
RUST_CPU="${W200_CPU//_/-}"    # rustc -C target-cpu=...
