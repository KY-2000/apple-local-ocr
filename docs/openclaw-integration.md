# OpenClaw Integration Guide

This guide explains how to use `apple-local-ocr` as a local OCR backend for OpenClaw or any similar AI-agent runtime.

## Positioning

Treat `apple-local-ocr` as:

- a local OCR worker
- a deterministic command-line dependency
- a tool that should be called in a narrow, explicit contract

Do not treat it as:

- a general document platform
- a GUI app
- a long-running service with a network API

## Why It Fits Agent Workflows

`apple-local-ocr` is useful for agents because it is:

- local-only
- scriptable
- non-interactive
- able to emit JSON
- able to emit machine-readable JSON errors
- able to inspect work before doing OCR

## Recommended Agent Contract

For OpenClaw-style use, the safest path is:

1. discover the tool with `--version`
2. inspect the intended workload with `inspect`
3. run OCR with `--stdout --format json --error-format json`
4. parse only documented JSON fields

## Step 1: Version Discovery

Check the tool version before using it:

```bash
.build/release/apple-local-ocr --version
```

Example output:

```text
0.4.0
```

Use this to:

- confirm the binary exists
- pin behavior by version
- gate agent logic if you later introduce new schema versions

## Step 2: Inspect Before Running

Use `inspect` to preview which jobs would run.

```bash
.build/release/apple-local-ocr inspect --recursive inbox/
```

This is useful for:

- validating input resolution
- previewing PDF page expansion
- estimating output paths
- catching missing inputs before OCR

## Step 3: Run With Structured Output

Recommended OCR call:

```bash
.build/release/apple-local-ocr \
  --stdout \
  --format json \
  --error-format json \
  --recursive \
  inbox/
```

This combination gives:

- OCR data on stdout as JSON
- errors on stderr as JSON
- no output file writes
- behavior that is easy for an agent to parse

## Success Payload Shape

The main fields agents should rely on are:

- `schemaVersion`
- `toolVersion`
- `inputPath`
- `outputPath`
- `engine`
- `languages`
- `format`
- `text`
- `pageNumber`
- `pages`

See the full schema here:
[json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md)

## Error Payload Shape

With `--error-format json`, stderr returns one JSON object like this:

```json
{
  "exitCode": 66,
  "kind": "input_error",
  "message": "Input not found at path: /tmp/missing.png",
  "schemaVersion": "1.0",
  "toolVersion": "0.4.0"
}
```

Error fields:

- `schemaVersion`
- `toolVersion`
- `kind`
- `message`
- `exitCode`
- `errors`

## Exit Code Handling

Recommended handling:

- `0`: success
- `1`: partial or full OCR processing failure
- `64`: usage error, likely agent bug or bad tool call
- `65`: no OCR jobs derived from valid-looking input
- `66`: missing or unreadable input/dictionary/watch path
- `70`: internal or environment error

## Suggested OpenClaw Tool Wrapper

Suggested wrapper policy:

- always call `--version` during tool discovery
- default to `--stdout --format json --error-format json`
- call `inspect` before large batches
- avoid `--watch` unless OpenClaw explicitly wants a long-running task
- parse `schemaVersion` before assuming payload shape

## Example Flows

### Single Image

```bash
.build/release/apple-local-ocr --stdout --format json --error-format json screenshot.png
```

### Recursive Folder

```bash
.build/release/apple-local-ocr --stdout --format json --error-format json --recursive scans/
```

### PDF Range

```bash
.build/release/apple-local-ocr \
  --stdout \
  --format json \
  --error-format json \
  --page-range 1-3 \
  report.pdf
```

### Plan Then Run

```bash
.build/release/apple-local-ocr inspect --recursive inbox/
.build/release/apple-local-ocr --stdout --format json --error-format json --recursive inbox/
```

## Safety Boundaries

OpenClaw developers can rely on these boundaries:

- OCR is local-only
- the CLI is non-interactive
- no network access is required
- stdout can be used instead of file writes
- existing files are not overwritten unless `--overwrite` is explicitly passed

## What Not To Rely On

Do not rely on:

- undocumented fields in future JSON payloads
- text-mode stderr when building agent parsers
- implicit behavior outside the documented exit codes and schema fields

## Recommended Next Layer

If you are packaging this for OpenClaw, the next useful layer is a very small wrapper that:

- normalizes paths
- enforces JSON mode
- captures stdout/stderr separately
- maps exit codes into OpenClaw tool states

That keeps OpenClaw integration stable even if the CLI grows more human-facing features later.

Practical examples:

- [examples/README.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/examples/README.md)
- [examples/openclaw_ocr_wrapper.sh](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/examples/openclaw_ocr_wrapper.sh)
- [examples/openclaw-task-snippets.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/examples/openclaw-task-snippets.md)
