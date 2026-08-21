#!/usr/bin/env bash
# course/verify.sh — verification harness for the lesson series.
#
# Implements the CURRICULUM.md "Verification harness" spec: for each lesson
# with solutions,
#   1. extract every `**File: course/work/lessonXX/<name>**`-tagged fenced
#      code block from lessonXX.md into a temp dir,
#   2. diff each extracted file against course/solutions/lessonXX/ —
#      byte-identical required (and every solution source file must be
#      covered by a lesson block),
#   3. run `make sim` in the solutions dir and diff the output against
#      OUTPUT.log,
#   4. visit each extracted .vhd with `emacs --batch` and check the major
#      mode is vhdl-mode (editor-workflow smoke test).
#
# Lessons without code and hardware-only lessons are skipped EXPLICITLY via
# SKIP_LESSONS below, never silently. Exit status is nonzero on any mismatch.
# One summary line per lesson: PASS / FAIL / SKIP.

set -u

COURSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOLUTIONS_DIR="$COURSE_DIR/solutions"
ENV_SCRIPT="$HOME/tools/oss-cad-suite/environment"

# --- explicit skip list ------------------------------------------------------
# lesson99: lab-day hardware bring-up. Its results are observed on the bench,
# not simulated; it has no solutions dir and no machine-checkable output.
declare -A SKIP_LESSONS=(
  [lesson99]="hardware-only lab day: no solutions dir, results observed on bench"
)

# Solution-dir files that are NOT produced from lesson code blocks and are
# therefore exempt from the coverage check in step 2.
is_exempt_solution_file() {
  case "$1" in
    OUTPUT.log|SYNTH.log) return 0 ;;
    *) return 1 ;;
  esac
}

# --- toolchain ---------------------------------------------------------------
if [[ ! -r "$ENV_SCRIPT" ]]; then
  echo "ERROR: $ENV_SCRIPT not found — cannot run simulations" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$ENV_SCRIPT"

if ! command -v ghdl >/dev/null 2>&1; then
  echo "ERROR: ghdl not on PATH after sourcing $ENV_SCRIPT" >&2
  exit 2
fi
HAVE_EMACS=1
if ! command -v emacs >/dev/null 2>&1; then
  echo "WARNING: emacs not found — vhdl-mode smoke test will FAIL lessons" >&2
  HAVE_EMACS=0
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

overall_rc=0
summary=()

# --- step 1 helper: extract tagged blocks ------------------------------------
# extract_blocks <lesson.md> <lesson_name> <outdir>
# Writes each `**File: course/work/<lesson>/<name>**` block to <outdir>/<name>
# and the list of extracted names to <outdir>/.manifest. Tags pointing at a
# path outside course/work/<lesson>/ are recorded in <outdir>/.badtags.
extract_blocks() {
  local md="$1" lesson="$2" outdir="$3"
  mkdir -p "$outdir"
  awk -v lesson="$lesson" -v outdir="$outdir" '
    BEGIN { state = 0 }
    state == 0 && /^\*\*File: .*\*\*[[:space:]]*$/ {
      tag = $0
      sub(/^\*\*File: /, "", tag)
      sub(/\*\*[[:space:]]*$/, "", tag)
      prefix = "course/work/" lesson "/"
      if (index(tag, prefix) != 1) {
        print tag >> (outdir "/.badtags")
        next
      }
      fname = substr(tag, length(prefix) + 1)
      state = 1
      next
    }
    state == 1 && /^[[:space:]]*$/ { next }
    state == 1 && /^```/ {
      out = outdir "/" fname
      printf "" > out
      print fname >> (outdir "/.manifest")
      state = 2
      next
    }
    state == 1 { state = 0 }   # tag not followed by a fence — ignore tag
    state == 2 && /^```[[:space:]]*$/ { close(out); state = 0; next }
    state == 2 { print >> out }
  ' "$md"
}

# --- main loop ---------------------------------------------------------------
shopt -s nullglob
lesson_mds=("$COURSE_DIR"/lesson[0-9][0-9].md)
shopt -u nullglob

for md in "${lesson_mds[@]}"; do
  lesson="$(basename "$md" .md)"

  if [[ -n "${SKIP_LESSONS[$lesson]:-}" ]]; then
    summary+=("$lesson: SKIP (${SKIP_LESSONS[$lesson]})")
    continue
  fi

  sol="$SOLUTIONS_DIR/$lesson"
  fails=()

  if [[ ! -d "$sol" ]]; then
    fails+=("no solutions dir $sol")
    summary+=("$lesson: FAIL (${fails[*]})")
    overall_rc=1
    continue
  fi

  echo "=== $lesson ==="

  # -- step 1: extract --------------------------------------------------------
  extract="$TMP_ROOT/$lesson"
  extract_blocks "$md" "$lesson" "$extract"

  if [[ -f "$extract/.badtags" ]]; then
    while IFS= read -r bad; do
      fails+=("File tag outside course/work/$lesson/: $bad")
    done < "$extract/.badtags"
  fi
  if [[ ! -f "$extract/.manifest" ]]; then
    fails+=("no **File:** tagged code blocks found in $lesson.md")
  fi

  # -- step 2: byte-diff extracted blocks vs solutions ------------------------
  if [[ -f "$extract/.manifest" ]]; then
    while IFS= read -r name; do
      if [[ ! -f "$sol/$name" ]]; then
        fails+=("lesson block $name has no solution file $sol/$name")
      elif ! cmp -s "$extract/$name" "$sol/$name"; then
        fails+=("lesson block $name differs from solutions copy")
        echo "--- diff (lesson block vs solutions) for $name ---"
        diff -u "$extract/$name" "$sol/$name" | head -40
      fi
    done < "$extract/.manifest"

    # coverage: every solution source file must come from a lesson block
    for f in "$sol"/*; do
      [[ -f "$f" ]] || continue          # skip build/ etc.
      base="$(basename "$f")"
      is_exempt_solution_file "$base" && continue
      if ! grep -qxF "$base" "$extract/.manifest"; then
        fails+=("solution file $base has no **File:** block in $lesson.md")
      fi
    done
  fi

  # -- step 3: make sim vs OUTPUT.log -----------------------------------------
  if [[ ! -f "$sol/OUTPUT.log" ]]; then
    fails+=("missing $sol/OUTPUT.log")
  elif [[ ! -f "$sol/Makefile" ]]; then
    fails+=("missing $sol/Makefile")
  else
    simlog="$TMP_ROOT/$lesson.sim.log"
    mkdir -p "$sol/build"
    if ! ( cd "$sol" && make sim ) >"$simlog" 2>&1; then
      fails+=("make sim exited nonzero")
      echo "--- make sim output (tail) ---"
      tail -20 "$simlog"
    fi
    if ! diff -q "$sol/OUTPUT.log" "$simlog" >/dev/null 2>&1; then
      fails+=("make sim output differs from OUTPUT.log")
      echo "--- diff (OUTPUT.log vs fresh make sim) ---"
      diff -u "$sol/OUTPUT.log" "$simlog" | head -40
    fi
  fi

  # -- step 4: emacs vhdl-mode smoke test -------------------------------------
  if [[ -f "$extract/.manifest" ]]; then
    while IFS= read -r name; do
      [[ "$name" == *.vhd ]] || continue
      if [[ "$HAVE_EMACS" -eq 0 ]]; then
        fails+=("emacs unavailable for vhdl-mode check of $name")
        continue
      fi
      mode="$(emacs --batch "$extract/$name" \
                --eval '(princ (symbol-name major-mode))' 2>/dev/null)"
      echo "emacs: $name -> ${mode:-<none>}"
      if [[ "$mode" != "vhdl-mode" ]]; then
        fails+=("emacs --batch reports major mode '${mode:-<none>}' (not vhdl-mode) for $name")
      fi
    done < "$extract/.manifest"
  fi

  # -- per-lesson verdict -----------------------------------------------------
  if [[ ${#fails[@]} -eq 0 ]]; then
    summary+=("$lesson: PASS")
  else
    joined=""
    for f in "${fails[@]}"; do joined+="${joined:+; }$f"; done
    summary+=("$lesson: FAIL ($joined)")
    overall_rc=1
  fi
done

# --- summary -----------------------------------------------------------------
echo
echo "=== summary ==="
for line in "${summary[@]}"; do
  echo "$line"
done
exit "$overall_rc"
