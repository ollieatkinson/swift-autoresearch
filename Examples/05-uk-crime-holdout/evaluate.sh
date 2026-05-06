set -euo pipefail

example_dir="$(cd "$(dirname "$0")" && pwd)"
python3 "$example_dir/evaluate.py"
