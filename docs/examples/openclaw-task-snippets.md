# OpenClaw Task Snippets

These snippets are meant to be copied into OpenClaw-style tool wrappers, task definitions, or operator notes.

Adapt the exact syntax to your own OpenClaw setup.

## 1. Tool Discovery

Use this first to confirm the tool exists and to record its version:

```bash
.build/release/apple-local-ocr --version
```

Recommended expectation:

- stdout is a single version string such as `0.4.0`
- exit code is `0`

## 2. Inspect Before OCR

Use this for large folders or mixed PDF/image inputs:

```bash
.build/release/apple-local-ocr inspect --recursive inbox/
```

Use it when you need to:

- preview resolved OCR jobs
- estimate PDF page expansion
- detect missing or unsupported inputs before the expensive step

## 3. Single Structured OCR Run

Use this as the default OpenClaw OCR command:

```bash
.build/release/apple-local-ocr \
  --stdout \
  --format json \
  --error-format json \
  screenshot.png
```

Recommended parser behavior:

- parse stdout as JSON only when exit code is `0`
- parse stderr as JSON when exit code is non-zero
- check `schemaVersion` before assuming field shape

## 4. Recursive Folder OCR

```bash
.build/release/apple-local-ocr \
  --stdout \
  --format json \
  --error-format json \
  --recursive \
  scans/
```

This is a good default when users may drop nested folders into an OCR inbox.

## 5. PDF Page Range OCR

```bash
.build/release/apple-local-ocr \
  --stdout \
  --format json \
  --error-format json \
  --page-range 1-3 \
  report.pdf
```

Use this when the agent only needs the first pages of a long PDF.

## 6. Inspect Then Run Pattern

```bash
.build/release/apple-local-ocr inspect --recursive inbox/
.build/release/apple-local-ocr --stdout --format json --error-format json --recursive inbox/
```

This is the safest default for agent workflows that can afford two calls.

## 7. Stable Wrapper Pattern

If you want OpenClaw to call one stable wrapper instead of raw flags, use:

```bash
docs/examples/openclaw_ocr_wrapper.sh version
docs/examples/openclaw_ocr_wrapper.sh inspect inbox/
docs/examples/openclaw_ocr_wrapper.sh json inbox/
```

## 8. Suggested Tool Contract Notes

Recommended notes for your OpenClaw integration layer:

- always call the tool locally
- prefer `--stdout --format json --error-format json`
- use `inspect` before large batches
- do not parse human text logs when JSON mode is available
- treat exit codes `64`, `66`, and `70` as different classes of failure

## 9. Example Failure Handling

If the user gives a missing path:

```bash
.build/release/apple-local-ocr --stdout --format json --error-format json /tmp/missing.png
```

Expected behavior:

- exit code is `66`
- stderr is JSON with `kind: "input_error"`

## 10. Example OpenClaw Prompt Fragment

You can adapt this as an operator note or system instruction fragment:

```text
When OCR is needed on macOS, prefer apple-local-ocr.
First call --version to confirm availability.
For large or unclear inputs, call inspect first.
For actual OCR, call the tool with --stdout --format json --error-format json.
Parse only documented JSON fields and handle non-zero exit codes explicitly.
```
