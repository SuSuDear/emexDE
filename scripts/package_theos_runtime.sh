#!/usr/bin/env bash
set -euo pipefail

THEOS_SRC="${THEOS_SRC:-${THEOS:-/var/mobile/theos}}"
OUT_DIR="${OUT_DIR:-/var/mobile/theos-runtime}"
ARCHIVE="${ARCHIVE:-/var/mobile/theos-runtime.tar.gz}"
PATCH_INSTALL_NAMES="${PATCH_INSTALL_NAMES:-1}"
SIGN_RUNTIME="${SIGN_RUNTIME:-1}"
RUN_SELF_TEST="${RUN_SELF_TEST:-1}"

log() { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
fail() { printf '[!] %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

copy_file() {
  src="$1"
  dst="$2"
  [ -e "$src" ] || return 1
  mkdir -p "$(dirname "$dst")"
  cp -f "$src" "$dst"
}

find_file() {
  name="$1"
  for dir in \
    /usr/lib \
    /usr/local/lib \
    /var/jb/usr/lib \
    /var/jb/usr/local/lib \
    /var/mobile/.jbroot/usr/lib \
    /var/mobile/.jbroot/usr/local/lib \
    /var/mobile/Containers/Shared/AppGroup/.jbroot-*/usr/lib \
    /var/mobile/Containers/Shared/AppGroup/.jbroot-*/usr/local/lib
  do
    for p in $dir/$name; do
      [ -e "$p" ] && { printf '%s\n' "$p"; return 0; }
    done
  done
  return 1
}

is_system_dep() {
  dep="$1"
  case "$dep" in
    /usr/lib/libSystem.B.dylib|/usr/lib/libc++.1.dylib|/usr/lib/libobjc.A.dylib|/usr/lib/libbz2.1.0.dylib|/System/Library/*)
      return 0 ;;
  esac
  return 1
}

mach_o_deps() {
  file="$1"
  otool -L "$file" 2>/dev/null | awk 'NR>1 {print $1}' | sed '/^$/d' || true
}

resolve_dep() {
  dep="$1"
  loader="$2"
  case "$dep" in
    @loader_path/*)
      rel="${dep#@loader_path/}"
      candidate="$(dirname "$loader")/$rel"
      [ -e "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
      base="$(basename "$dep")"
      find_file "$base" && return 0
      ;;
    @rpath/*)
      base="$(basename "$dep")"
      find_file "$base" && return 0
      ;;
    /*)
      [ -e "$dep" ] && { printf '%s\n' "$dep"; return 0; }
      ;;
  esac
  return 1
}

copy_macho_deps_recursive() {
  root="$1"
  queue_file="$OUT_DIR/.deps.queue"
  seen_file="$OUT_DIR/.deps.seen"
  : > "$queue_file"
  : > "$seen_file"
  printf '%s\n' "$root" >> "$queue_file"

  while [ -s "$queue_file" ]; do
    current="$(head -n 1 "$queue_file")"
    tail -n +2 "$queue_file" > "$queue_file.tmp" || true
    mv "$queue_file.tmp" "$queue_file"
    grep -Fxq "$current" "$seen_file" 2>/dev/null && continue
    printf '%s\n' "$current" >> "$seen_file"

    mach_o_deps "$current" | while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      is_system_dep "$dep" && continue
      resolved="$(resolve_dep "$dep" "$current" || true)"
      if [ -z "$resolved" ]; then
        warn "unresolved dependency for $(basename "$current"): $dep"
        continue
      fi
      base="$(basename "$resolved")"
      dst="$OUT_DIR/lib/$base"
      if [ ! -e "$dst" ]; then
        log "copy dylib $base"
        copy_file "$resolved" "$dst" || true
        chmod 0755 "$dst" 2>/dev/null || true
        printf '%s\n' "$dst" >> "$queue_file"
      fi
    done
  done

  rm -f "$queue_file" "$seen_file"
}

patch_binary() {
  file="$1"
  command -v install_name_tool >/dev/null 2>&1 || command -v llvm-install-name-tool >/dev/null 2>&1 || return 0
  tool="$(command -v install_name_tool 2>/dev/null || command -v llvm-install-name-tool)"

  "$tool" -add_rpath '@loader_path/../lib' "$file" 2>/dev/null || true
  mach_o_deps "$file" | while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    is_system_dep "$dep" && continue
    case "$dep" in
      @loader_path/../lib/*) continue ;;
      @rpath/*|@loader_path/*)
        base="$(basename "$dep")"
        [ -e "$OUT_DIR/lib/$base" ] || continue
        "$tool" -change "$dep" "@loader_path/../lib/$base" "$file" 2>/dev/null || true
        ;;
    esac
  done
}

patch_dylib_id() {
  file="$1"
  command -v install_name_tool >/dev/null 2>&1 || command -v llvm-install-name-tool >/dev/null 2>&1 || return 0
  tool="$(command -v install_name_tool 2>/dev/null || command -v llvm-install-name-tool)"
  base="$(basename "$file")"
  "$tool" -id "@rpath/$base" "$file" 2>/dev/null || true
}

copy_perl_inc() {
  perl_bin="$1"
  log "copy perl @INC"
  mkdir -p "$OUT_DIR/perl5"
  "$perl_bin" -e 'print join("\n", @INC), "\n"' 2>/dev/null | while IFS= read -r dir; do
    [ -d "$dir" ] || continue
    case "$dir" in
      .) continue ;;
    esac
    log "copy perl lib $dir"
    cp -a "$dir"/. "$OUT_DIR/perl5"/ 2>/dev/null || true
  done
}

sign_macho() {
  ldid_bin="$(command -v ldid 2>/dev/null || true)"
  [ -n "$ldid_bin" ] || { warn "ldid not found, skip signing"; return 0; }
  find "$OUT_DIR/bin" "$OUT_DIR/lib" -type f 2>/dev/null | while IFS= read -r f; do
    if file "$f" 2>/dev/null | grep -q 'Mach-O'; then
      chmod 0755 "$f" 2>/dev/null || true
      "$ldid_bin" -S "$f" 2>/dev/null || warn "ldid failed: $f"
    fi
  done
}

self_test() {
  log "self-test"
  export THEOS="$OUT_DIR/theos"
  export PATH="$OUT_DIR/bin:$THEOS/bin:$PATH"
  export DYLD_LIBRARY_PATH="$OUT_DIR/lib:${DYLD_LIBRARY_PATH:-}"
  export PERL5LIB="$OUT_DIR/perl5:${PERL5LIB:-}"
  "$OUT_DIR/bin/perl" -e 'print "perl ok\n"'
  "$OUT_DIR/bin/make" -v | head -n 1
  "$OUT_DIR/bin/dpkg-deb" --version | head -n 1
  if [ -f "$THEOS/bin/logos.pl" ]; then
    "$OUT_DIR/bin/perl" "$THEOS/bin/logos.pl" >/dev/null 2>&1 || true
    printf 'logos.pl reachable\n'
  fi
}

need_cmd otool
need_cmd file
[ -d "$THEOS_SRC" ] || fail "THEOS_SRC not found: $THEOS_SRC"
[ -f "$THEOS_SRC/makefiles/common.mk" ] || fail "common.mk missing under THEOS_SRC: $THEOS_SRC"

log "output dir: $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/bin" "$OUT_DIR/lib" "$OUT_DIR/perl5" "$OUT_DIR/theos"

log "copy theos: $THEOS_SRC"
cp -a "$THEOS_SRC"/. "$OUT_DIR/theos"/

for tool in perl make dpkg-deb ldid; do
  src="$(command -v "$tool" 2>/dev/null || true)"
  [ -n "$src" ] || fail "$tool not found in PATH"
  if [ -L "$src" ]; then
    real="$(cd "$(dirname "$src")" && pwd -P)/$(readlink "$src")"
    [ -e "$real" ] && src="$real"
  fi
  log "copy $tool: $src"
  copy_file "$src" "$OUT_DIR/bin/$tool"
  chmod 0755 "$OUT_DIR/bin/$tool"
  copy_macho_deps_recursive "$OUT_DIR/bin/$tool"
done

copy_perl_inc "$(command -v perl)"

if [ "$PATCH_INSTALL_NAMES" = "1" ]; then
  log "patch install names"
  find "$OUT_DIR/bin" -type f | while IFS= read -r f; do
    file "$f" | grep -q 'Mach-O' && patch_binary "$f"
  done
  find "$OUT_DIR/lib" -type f | while IFS= read -r f; do
    file "$f" | grep -q 'Mach-O' || continue
    patch_dylib_id "$f"
    patch_binary "$f"
  done
else
  warn "skip install_name_tool patching"
fi

if [ "$SIGN_RUNTIME" = "1" ]; then
  log "sign runtime Mach-O files"
  sign_macho
fi

if [ "$RUN_SELF_TEST" = "1" ]; then
  self_test || warn "self-test failed; inspect dependencies before embedding"
fi

log "create archive: $ARCHIVE"
rm -f "$ARCHIVE"
parent="$(dirname "$OUT_DIR")"
base="$(basename "$OUT_DIR")"
(cd "$parent" && tar -czf "$ARCHIVE" "$base")

log "done"
printf '\nRuntime: %s\nArchive: %s\n\n' "$OUT_DIR" "$ARCHIVE"
printf 'Use with:\n'
printf '  export THEOS="%s/theos"\n' "$OUT_DIR"
printf '  export PATH="%s/bin:$THEOS/bin:$PATH"\n' "$OUT_DIR"
printf '  export DYLD_LIBRARY_PATH="%s/lib:$DYLD_LIBRARY_PATH"\n' "$OUT_DIR"
printf '  export PERL5LIB="%s/perl5:$PERL5LIB"\n' "$OUT_DIR"
