#!/usr/bin/env bash
#
# mayhem/build.sh — cargo-fuzz parser/reparse targets + syntax crate tests (normal flags).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes}"
DWARF_FLAGS="-Zdwarf-version=3"

FUZZ_RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS} ${DWARF_FLAGS}"
echo "SANITIZER_FLAGS (base, informational) = ${SANITIZER_FLAGS:-<unset>}"

FUZZ_DIR="crates/syntax/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Turn LeakSanitizer off at BUILD time (SPEC §6.2 item 15): link mayhem/lsan_off.c, which defines the
# __lsan_is_turned_off() hook, into every ASan fuzz binary. rustc takes only one -Clinker, so the object
# goes in through a generated linker wrapper. -gdwarf-3 comes AFTER $SANITIZER_FLAGS (which ends in a
# plain -g = DWARF 5) so this object's CU, which lands first in .debug_info, stays DWARF 3.
LSAN_OBJ="/tmp/mayhem-lsan_off.o"
"${CC:-clang}" -fPIC ${SANITIZER_FLAGS:-} -gdwarf-3 -c "$SRC/mayhem/lsan_off.c" -o "$LSAN_OBJ"
LINK_WRAPPER="/tmp/mayhem-rustc-link.sh"
printf '#!/bin/sh\nexec cc %s "$@"\n' "$LSAN_OBJ" > "$LINK_WRAPPER"
chmod 755 "$LINK_WRAPPER"
FUZZ_RUSTFLAGS="$FUZZ_RUSTFLAGS -Clinker=$LINK_WRAPPER"

ASAN_A="$(rustc --print sysroot)/lib/rustlib/${TRIPLE}/lib/librustc-nightly_rt.asan.a"
if [ -f "$ASAN_A" ]; then
  echo "stripping debug info from prebuilt ASan runtime: $ASAN_A"
  objcopy --strip-debug "$ASAN_A" 2>/dev/null || objcopy --remove-section '.debug_*' "$ASAN_A" 2>/dev/null || true
fi

# Upstream gitignores the fuzz crate's Cargo.lock, so every fresh build re-resolves its dependencies
# against crates.io HEAD. That stopped building once unicode-ident moved to a Unicode version that
# unicode-properties does not match (ra-ap-rustc_lexer asserts the two agree at compile time). Pin the
# fuzz crate to the committed mayhem/fuzz-Cargo.lock, which is the workspace Cargo.lock plus
# libfuzzer-sys and its dependencies.
cp -f "$SRC/mayhem/fuzz-Cargo.lock" "$FUZZ_DIR/Cargo.lock"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

echo "=== cargo fuzz build (ASan via RUSTFLAGS, DWARF 3) ==="
echo "RUSTFLAGS=$FUZZ_RUSTFLAGS"
echo "CFLAGS=$CFLAGS  CXXFLAGS=$CXXFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  RUSTFLAGS="$FUZZ_RUSTFLAGS" cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "=== cargo test -p syntax --no-run (clean flags, for test.sh) ==="
TEST_RUSTFLAGS="--cap-lints=warn"
( cd "$SRC" && RUSTFLAGS="$TEST_RUSTFLAGS" cargo test -p syntax --no-run )

echo "build.sh complete"
