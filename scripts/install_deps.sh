#!/usr/bin/env bash
#
# Purpose: Install common build, simulation, and formal-verification tools for
# the NAND model repository.
# Role: Developer environment setup helper.
# Related design docs:
# - Nand_Model_Specification_Index.md
# - design_spec/nand_cdc_ip.md
# - design_spec/nand_picorv32.md
# File version: v0.3
# Revision history:
# - v0.3: Update the firmware build hint for the compact
#   Makefile target surface.
# - v0.2: Use the repository-managed tools/sby submodule as the
#   SymbiYosys source instead of cloning an untracked temporary copy.
# - v0.1: Initial apt-based dependency installer with SymbiYosys
#   source-install fallback.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SBY_DIR="${REPO_ROOT}/tools/sby"

APT_PACKAGES=(
    build-essential
    ca-certificates
    git
    make
    python3
    python3-pip
    iverilog
    yosys
    z3
)

OPTIONAL_APT_PACKAGES=(
    binutils-riscv64-unknown-elf
    gcc-riscv64-unknown-elf
)

if [[ "${EUID}" -eq 0 ]]; then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
else
    echo "ERROR: root or sudo is required for apt package installation." >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: this installer currently supports apt-based Linux systems only." >&2
    echo "Install manually: make git python3 iverilog yosys yosys-smtbmc z3 sby." >&2
    exit 1
fi

install_apt_packages() {
    echo "[deps] apt-get update"
    "${SUDO[@]}" apt-get update

    echo "[deps] apt-get install core project tools"
    "${SUDO[@]}" apt-get install -y "${APT_PACKAGES[@]}"

    local pkg
    local install_optional=()
    for pkg in "${OPTIONAL_APT_PACKAGES[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            install_optional+=("$pkg")
        else
            echo "[deps] optional apt package not available: $pkg"
        fi
    done

    if ((${#install_optional[@]} > 0)); then
        echo "[deps] apt-get install optional RISC-V toolchain packages"
        "${SUDO[@]}" apt-get install -y "${install_optional[@]}"
    fi
}

ensure_sby_submodule() {
    if [[ ! -f "${SBY_DIR}/Makefile" || ! -f "${SBY_DIR}/sbysrc/sby.py" ]]; then
        echo "[deps] initializing SymbiYosys submodule: tools/sby"
        git -C "${REPO_ROOT}" submodule update --init tools/sby
    fi

    if [[ ! -f "${SBY_DIR}/Makefile" || ! -f "${SBY_DIR}/sbysrc/sby.py" ]]; then
        echo "ERROR: tools/sby is not initialized correctly." >&2
        echo "Run manually: git submodule update --init tools/sby" >&2
        exit 1
    fi
}

install_sby_if_missing() {
    local prefix

    ensure_sby_submodule

    if command -v sby >/dev/null 2>&1; then
        echo "[deps] sby already installed: $(command -v sby)"
        echo "[deps] Makefile formal wrapper still uses repo-local tools/sby by default."
        return
    fi

    if [[ -w /usr/local/bin ]] || [[ "${EUID}" -eq 0 ]] || command -v sudo >/dev/null 2>&1; then
        prefix="/usr/local"
    else
        prefix="${HOME}/.local"
        mkdir -p "${prefix}"
    fi

    echo "[deps] installing SymbiYosys sby from tools/sby into ${prefix}"
    if [[ "${prefix}" == "/usr/local" && "${EUID}" -ne 0 && ! -w /usr/local/bin ]]; then
        "${SUDO[@]}" make -C "${SBY_DIR}" install PREFIX="${prefix}"
    else
        make -C "${SBY_DIR}" install PREFIX="${prefix}"
    fi

    if [[ "${prefix}" == "${HOME}/.local" ]]; then
        export PATH="${HOME}/.local/bin:${PATH}"
        echo "[deps] add this to your shell profile if needed:"
        echo "       export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

print_versions() {
    echo
    echo "[deps] installed tool versions / paths"
    command -v iverilog >/dev/null 2>&1 && iverilog -V | head -n 1 || true
    command -v yosys >/dev/null 2>&1 && yosys -V || true
    command -v yosys-smtbmc >/dev/null 2>&1 && echo "yosys-smtbmc: $(command -v yosys-smtbmc)" || true
    command -v z3 >/dev/null 2>&1 && z3 --version || true
    command -v sby >/dev/null 2>&1 && echo "sby: $(command -v sby)" || true

    if [[ -x /tools/riscv/bin/riscv64-unknown-elf-gcc ]]; then
        echo "riscv gcc: /tools/riscv/bin/riscv64-unknown-elf-gcc"
    elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
        echo "riscv gcc: $(command -v riscv64-unknown-elf-gcc)"
        echo "note: Makefile default is /tools/riscv/bin/riscv64-unknown-elf-."
        echo "      Use: make RISCV_TOOLCHAIN_PREFIX=riscv64-unknown-elf- fw"
    else
        echo "warning: riscv64-unknown-elf-gcc not found."
        echo "         RV32 firmware build needs a RISC-V embedded GCC toolchain."
    fi
}

install_apt_packages
install_sby_if_missing
print_versions

echo
echo "[deps] done"
