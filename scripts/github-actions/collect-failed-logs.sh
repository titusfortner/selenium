#!/usr/bin/env bash
# Collects failed test logs from Bazel testlogs directory
# Reads targets from build/failures/_run2.txt if present, otherwise _run1.txt

set -euxo pipefail

TESTLOGS_ROOT=$(bazel info bazel-testlogs)

LIST_FILE=""
if [ -s build/failures/_run2.txt ]; then
  LIST_FILE="build/failures/_run2.txt"
elif [ -s build/failures/_run1.txt ]; then
  LIST_FILE="build/failures/_run1.txt"
else
  exit 0
fi

echo "Failures to collect from $LIST_FILE:"
cat "$LIST_FILE"

while IFS= read -r target; do
  [ -z "$target" ] && continue

  # Convert //path/to:target to path/to/target
  rel_path=$(tr ':' '/' <<< "${target#//}")

  log_dir="$TESTLOGS_ROOT/${rel_path}"
  # Convert path separators to underscores for safe filename
  safe_name="${target#//}"
  safe_name="${safe_name//[\/:]/_}"

  found=0
  if [ -f "$log_dir/test.log" ]; then
    echo "Copying log for $target..."
    cp "$log_dir/test.log" "build/failures/${safe_name}.log"
    found=1
  fi
  # --runs_per_test and --flaky_test_attempts write each run's log to a subdirectory
  for extra in "$log_dir"/run_*_of_*/test.log "$log_dir"/test_attempts/attempt_*.log; do
    [ -f "$extra" ] || continue
    suffix=$(dirname "${extra#"$log_dir"/}")
    suffix="${suffix//\//_}"
    [ "$(basename "$extra")" = "test.log" ] || suffix="${suffix}_$(basename "$extra" .log)"
    echo "Copying $suffix log for $target..."
    cp "$extra" "build/failures/${safe_name}_${suffix}.log"
    found=1
  done

  if [ "$found" -eq 0 ]; then
    echo "Warning: No log found for $target under $log_dir" >&2
  fi
done < "$LIST_FILE"
