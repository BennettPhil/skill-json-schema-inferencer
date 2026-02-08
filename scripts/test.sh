#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  FAIL: $1 -- $2"; }

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$description"
  else
    fail "$description" "expected '$expected', got '$actual'"
  fi
}

assert_exit_code() {
  local description="$1" expected_code="$2"
  shift 2
  set +e
  "$@" >/dev/null 2>&1
  local actual_code=$?
  set -e
  if [ "$expected_code" -eq "$actual_code" ]; then
    pass "$description"
  else
    fail "$description" "expected exit code $expected_code, got $actual_code"
  fi
}

assert_contains() {
  local description="$1" needle="$2" haystack="$3"
  if grep -q -- "$needle" <<<"$haystack"; then
    pass "$description"
  else
    fail "$description" "output does not contain '$needle'"
  fi
}

echo "Running tests for: json-schema-inferencer"
echo "================================"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/user1.json" <<'EOF'
{"name":"Ada","age":36,"active":true}
EOF

cat >"$tmp_dir/user2.json" <<'EOF'
{"name":"Lin","active":false}
EOF

cat >"$tmp_dir/special.json" <<'EOF'
{"first-name":"Ada","team/id":42}
EOF

cat >"$tmp_dir/invalid.json" <<'EOF'
{"name":"bad"
EOF

echo ""
echo "Happy path:"

help_out="$("$SCRIPT_DIR/run.sh" --help)"
assert_contains "help contains usage" "Usage: run.sh" "$help_out"

schema_one="$("$SCRIPT_DIR/run.sh" "$tmp_dir/user1.json")"
assert_eq "single sample type is object" "object" "$(jq -r '.type' <<<"$schema_one")"
assert_eq "name inferred as string" "string" "$(jq -r '.properties.name.type' <<<"$schema_one")"
assert_eq "age inferred as integer" "integer" "$(jq -r '.properties.age.type' <<<"$schema_one")"
assert_eq "active inferred as boolean" "boolean" "$(jq -r '.properties.active.type' <<<"$schema_one")"

schema_two="$("$SCRIPT_DIR/run.sh" "$tmp_dir/user1.json" "$tmp_dir/user2.json")"
assert_eq "name required across samples" "true" "$(jq -r '.required | index("name") != null' <<<"$schema_two")"
assert_eq "active required across samples" "true" "$(jq -r '.required | index("active") != null' <<<"$schema_two")"
assert_eq "age becomes optional across samples" "false" "$(jq -r '.required | index("age") != null' <<<"$schema_two")"

echo ""
echo "Edge cases:"

schema_special="$("$SCRIPT_DIR/run.sh" "$tmp_dir/special.json")"
assert_eq "special key preserved first-name" "string" "$(jq -r '.properties["first-name"].type' <<<"$schema_special")"
assert_eq "special key preserved team/id" "integer" "$(jq -r '.properties["team/id"].type' <<<"$schema_special")"

printf '{"id":1}\n' | "$SCRIPT_DIR/run.sh" >"$tmp_dir/stdin-schema.json"
assert_eq "stdin input supported" "integer" "$(jq -r '.properties.id.type' "$tmp_dir/stdin-schema.json")"

python3 -c 'import json; print(json.dumps([{"n":i} for i in range(500)]))' >"$tmp_dir/large.json"
schema_large="$("$SCRIPT_DIR/run.sh" "$tmp_dir/large.json")"
assert_eq "large array inferred as array type" "array" "$(jq -r '.type' <<<"$schema_large")"
assert_eq "large array item object property inferred" "integer" "$(jq -r '.items.properties.n.type' <<<"$schema_large")"

echo ""
echo "Error cases:"

assert_exit_code "fails with no args and empty stdin" 1 "$SCRIPT_DIR/run.sh"
assert_exit_code "fails on invalid json input file" 2 "$SCRIPT_DIR/run.sh" "$tmp_dir/invalid.json"
assert_exit_code "fails when file path is missing" 1 "$SCRIPT_DIR/run.sh" "$tmp_dir/missing.json"

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] || exit 1
