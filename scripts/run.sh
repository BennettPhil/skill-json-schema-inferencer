#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: run.sh [JSON_FILE ...] [--output OUTPUT_FILE]

Infer a JSON Schema from one or more JSON samples.
If no JSON_FILE is provided, reads one JSON document from stdin.

Exit codes:
  0 success
  1 invalid arguments, missing input, or missing file
  2 invalid JSON input
  3 missing dependency (jq)
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "run.sh: jq is required" >&2
  exit 3
fi

output_file=""
inputs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      output_file="$2"
      shift 2
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      inputs+=("$1")
      shift
      ;;
  esac
done

tmp_input=""
cleanup() {
  if [[ -n "$tmp_input" ]]; then
    rm -f "$tmp_input"
  fi
  return 0
}
trap cleanup EXIT

if [[ "${#inputs[@]}" -eq 0 ]]; then
  tmp_input="$(mktemp)"
  cat >"$tmp_input"
  if [[ ! -s "$tmp_input" ]]; then
    echo "run.sh: no input provided" >&2
    exit 1
  fi
  inputs=("$tmp_input")
fi

for f in "${inputs[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "run.sh: input file not found: $f" >&2
    exit 1
  fi
done

jq_filter='
def merge(a; b):
  a as $a | b as $b |
  if $a == null then $b
  elif $b == null then $a
  elif $a == $b then $a
  elif ($a.type? == "object" and $b.type? == "object") then
    {
      type:"object",
      properties: (
        ((($a.properties // {}) | keys_unsorted) + (($b.properties // {}) | keys_unsorted) | unique)
        | map({key:., value: merge(($a.properties[.] // null); ($b.properties[.] // null))})
        | from_entries
      ),
      required: (((($a.required // []) as $ar | ($b.required // []) as $br | [$ar[] as $k | select(($br | index($k)) != null) | $k])) | unique)
    }
  elif ($a.type? == "array" and $b.type? == "array") then
    {type:"array",items:merge(($a.items // null); ($b.items // null))}
  elif ($a.type? and $b.type? and $a.type == $b.type) then
    $a
  else
    {anyOf: ([$a,$b] | unique)}
  end;

def infer:
  if type == "object" then
    {type:"object",properties:(with_entries(.value |= infer)),required:keys}
  elif type == "array" then
    if length == 0 then {type:"array",items:{}}
    else {type:"array",items:(map(infer) | reduce .[] as $s (null; merge(.; $s)))}
    end
  elif type == "string" then {type:"string"}
  elif type == "boolean" then {type:"boolean"}
  elif type == "number" then (if floor == . then {type:"integer"} else {type:"number"} end)
  elif type == "null" then {type:"null"}
  else {type:"string"}
  end;

map(infer) | reduce .[] as $s (null; merge(.; $s))
'

set +e
schema="$(jq -s "$jq_filter" "${inputs[@]}" 2>/tmp/json-schema-inferencer-jq.err)"
jq_status=$?
set -e
if [[ "$jq_status" -ne 0 ]]; then
  echo "run.sh: invalid JSON input" >&2
  cat /tmp/json-schema-inferencer-jq.err >&2 || true
  rm -f /tmp/json-schema-inferencer-jq.err
  exit 2
fi
rm -f /tmp/json-schema-inferencer-jq.err

if [[ -n "$output_file" ]]; then
  printf '%s\n' "$schema" >"$output_file"
else
  printf '%s\n' "$schema"
fi
