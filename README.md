# json-schema-inferencer

Infer a JSON Schema from one or more sample JSON inputs.

## Run
```bash
./scripts/run.sh sample1.json sample2.json
```

Read from stdin:
```bash
echo '{"name":"Ada"}' | ./scripts/run.sh
```

## Test
```bash
./scripts/test.sh
```

## Philosophy
This skill is test-driven: tests define behavior, and implementation follows the tests as the source of truth.
