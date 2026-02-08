---
name: json-schema-inferencer
description: Infer JSON Schema from one or more sample JSON documents.
version: 0.1.0
license: Apache-2.0
---

# JSON Schema Inferencer

## Purpose
This skill infers a JSON Schema-like structure from sample JSON data. It supports one or more input samples and merges them into a single contract where required fields are those present in every sample object.

## Contract
- The output is JSON with inferred types for objects, arrays, strings, booleans, integers, numbers, and nulls.
- For object samples, `properties` contains each discovered field schema.
- For object merges, `required` is the intersection of required fields across samples.
- For array samples, `items` is inferred from merged element schemas.
- Input can be files or stdin.

## Inputs
- Positional args: one or more JSON file paths.
- Stdin: one JSON document when no file arguments are provided.
- Optional flag: `--output <path>` to write schema to a file.

## Outputs
- Inferred schema JSON to stdout (or output path if provided).
- Exit code `0` on success.

## Error Handling
- Exit code `1` for missing input or missing file path.
- Exit code `2` for invalid JSON.
- Exit code `3` if `jq` is not installed.

## Testing
Run:

```bash
./scripts/test.sh
```

Expected behavior: all tests pass. If any test fails, fix `scripts/run.sh` to satisfy the contract in tests.
