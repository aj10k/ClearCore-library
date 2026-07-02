#!/usr/bin/env bash
# rebuild_libclearcore.sh
# Recompiles libClearCore.a from source.
# Requires: nix-shell with gcc-arm-embedded available.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SRC_LIB="/home/aj/ClearCore-library/libClearCore"
ARDUINO_SDK="$HOME/.arduino15/packages/ClearCore/hardware/sam/1.7.4"
CMSIS_INC="$HOME/.arduino15/packages/arduino/tools/CMSIS/4.5.0/CMSIS/Include"
OUT_DIR="/tmp/clearcore-rebuild"
DEST_LIB="$ARDUINO_SDK/Teknic/libClearCore/Release/libClearCore.a"
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p "$OUT_DIR"

# ── Write inner build script (runs inside nix-shell) ─────────────────────────
# Using a separate script avoids shell quoting issues with paths containing spaces.
INNER="$OUT_DIR/do_build.sh"
cat > "$INNER" << INNER_EOF
#!/usr/bin/env bash
set -euo pipefail

CC=arm-none-eabi-g++
AR=arm-none-eabi-ar
SRC_LIB="$SRC_LIB"
OUT_DIR="$OUT_DIR"
DEST_LIB="$DEST_LIB"

CFLAGS=(
  -mthumb -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16
  -c -g -O3 -w
  -std=gnu++11 -ffunction-sections -fdata-sections
  -fno-threadsafe-statics -nostdlib
  --param max-inline-insns-single=500
  -fno-rtti -fno-exceptions
  -DF_CPU=120000000L -D__FPU_PRESENT=1
  -DARDUINO=10607 -DARDUINO_ARM_ClearCore -DARDUINO_ARCH_SAM
  -D__ARM_FEATURE_DSP=1 -DCPPUTEST_USE_MEM_LEAK_DETECTION=0
  -DUSB_VID=0x2890 -DUSB_PID=0x0022
  -lc -DDEBUG -DUSBCON -DUSB_CONFIG_POWER=0
  -D__CLEARCORE__ -D__SAME53N19A__ -DARM_MATH_CM4
)

INCS=(
  "-I$ARDUINO_SDK/cores/arduino/api"
  "-I$CMSIS_INC"
  "-I$ARDUINO_SDK/variants/clearcore/Third Party/SAME53/CMSIS/Device/Include"
  "-I$SRC_LIB/inc"
  "-I$ARDUINO_SDK/Teknic/LwIP/LwIP/src/include"
  "-I$ARDUINO_SDK/Teknic/LwIP/LwIP/port/include"
  "-I$ARDUINO_SDK/cores/arduino"
  "-I$ARDUINO_SDK/variants/clearcore"
)

TCP_SRCS=(
    "\$SRC_LIB/src/EthernetTcp.cpp"
    "\$SRC_LIB/src/EthernetTcpClient.cpp"
    "\$SRC_LIB/src/EthernetTcpServer.cpp"
)

OBJS=()
for src in "\${TCP_SRCS[@]}"; do
    base=\$(basename "\$src" .cpp)
    obj="\$OUT_DIR/\${base}.o"
    echo "    \$base.cpp"
    "\$CC" "\${CFLAGS[@]}" "\${INCS[@]}" "\$src" -o "\$obj"
    OBJS+=("\$obj")
done

echo "==> Replacing objects in archive..."
# 'r' replaces existing members by name, leaving all other objects intact
"\$AR" r "\$DEST_LIB" "\${OBJS[@]}"
echo "    Updated: \$DEST_LIB"
INNER_EOF
chmod +x "$INNER"
# ─────────────────────────────────────────────────────────────────────────────

echo "==> Compiling all source files..."

# Back up original if not already backed up
if [[ ! -f "${DEST_LIB}.bak" ]]; then
    cp "$DEST_LIB" "${DEST_LIB}.bak"
    echo "    Backed up original to ${DEST_LIB}.bak"
fi

nix-shell -p gcc-arm-embedded --run "$INNER"

echo "==> Done. libClearCore.a rebuilt."
echo "    Written to: $DEST_LIB"
echo ""
echo "    To restore original: cp '${DEST_LIB}.bak' '$DEST_LIB'"
