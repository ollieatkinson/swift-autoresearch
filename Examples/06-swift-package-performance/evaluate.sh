#!/usr/bin/env bash
set -euo pipefail

example_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$example_dir/../.." && pwd)"

expected_checksum=53633945
source_package="$example_dir/PackageUnderTest"
work_root="$repo_dir/.build/06-swift-package-performance"
work_package="$work_root/PackageUnderTest"
executable="$work_package/.build/release/BuildRunProbe"

rm -rf "$work_package"
mkdir -p "$work_root"
cp -R "$source_package" "$work_package"

run_timed() {
  local label="$1"
  local cwd="$2"
  shift 2

  local stdout_file="$work_root/$label.stdout"
  local stderr_file="$work_root/$label.stderr"
  local time_file="$work_root/$label.time"

  set +e
  (
    cd "$cwd"
    TIMEFORMAT="%R"
    { time "$@" >"$stdout_file" 2>"$stderr_file"; } 2>"$time_file"
  )
  local status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "Command failed: $*" >&2
    cat "$stdout_file" >&2
    cat "$stderr_file" >&2
    exit "$status"
  fi

  awk '/^[0-9]+([.][0-9]+)?$/ { value = $1 } END { if (value != "") print value }' "$time_file"
}

build_seconds="$(run_timed build "$work_package" swift build -c release)"
run_seconds="$(run_timed run "$work_package" "$executable")"

checksum="$(awk '/^checksum:/ { value = $2 } END { if (value != "") print value }' "$work_root/run.stdout")"
if [[ -z "$checksum" ]]; then
  echo "Executable did not print checksum: <integer>" >&2
  cat "$work_root/run.stdout" >&2
  exit 2
fi

if [[ "$checksum" != "$expected_checksum" ]]; then
  echo "Executable checksum mismatch: got $checksum, expected $expected_checksum" >&2
  cat "$work_root/run.stdout" >&2
  exit 2
fi

score="$(awk -v build="$build_seconds" -v run="$run_seconds" 'BEGIN { printf "%.6f", build + run }')"

echo "---"
echo "score: $score"
echo "build_seconds: $build_seconds"
echo "run_seconds: $run_seconds"
echo "checksum: $checksum"
echo "build_command: swift build -c release"
echo "run_command: .build/release/BuildRunProbe"
echo "package: PackageUnderTest"
echo "optimization_target: clean release build plus executable runtime"
echo "scoring_rule: build_seconds + run_seconds"
