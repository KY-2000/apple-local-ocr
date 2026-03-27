# apple-local-ocr

`apple-local-ocr` is a local OCR CLI for macOS built on Apple's Vision and VisionKit frameworks.

It is designed for two kinds of users:

- terminal users who want a lightweight OCR tool for images, PDFs, and folders
- AI agents that need deterministic, local-first OCR with JSON output and machine-readable errors

## What It Does

- OCR one or more files or folders in a single run
- Support `pdf`, `png`, `jpg`, `jpeg`, `heic`, `tiff`, `bmp`, and `gif`
- Use either `liveText` or `vision` as the OCR engine
- Write output as `txt`, `json`, or `md`
- Run in batch mode, recursive mode, watch-folder mode, or inspect mode
- Stay local: no cloud OCR, no network dependency

## Requirements

- macOS 13 or later
- Swift 5.10 or later
- Full Xcode selected via `xcode-select` if you want to run tests

If your test toolchain is broken, see [docs/plans/2026-03-25-xctest-toolchain-fix-plan.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/plans/2026-03-25-xctest-toolchain-fix-plan.md).

## Install

Build from source:

```bash
swift build -c release
```

Check the installed version:

```bash
.build/release/apple-local-ocr --version
```

## Quick Start

OCR a single image:

```bash
.build/release/apple-local-ocr receipt.png
```

OCR a PDF:

```bash
.build/release/apple-local-ocr report.pdf
```

OCR a folder recursively and keep the folder structure:

```bash
.build/release/apple-local-ocr --recursive --preserve-structure --output out scans/
```

Print OCR text to stdout instead of writing files:

```bash
.build/release/apple-local-ocr --stdout screenshot.png
```

Return structured JSON for agents:

```bash
.build/release/apple-local-ocr \
  --stdout \
  --format json \
  --error-format json \
  scans/
```

## Core Commands

- `apple-local-ocr [options] <path...>`: run OCR normally
- `apple-local-ocr inspect [options] <path...>`: show what would be processed without running OCR
- `apple-local-ocr languages [--engine vision|liveText]`: list supported OCR languages
- `apple-local-ocr --version`: print the CLI version

## Useful Defaults

- Default engine: `liveText`
- Default languages: `zh-Hans,en-US`
- Default output format: `txt`
- Default output directory: `output/`
- Default overwrite behavior: `--skip`
- Default PDF mode: `combined`
- Default error format: `text`

## For AI Agents

Recommended flow:

1. Call `--version` to identify the tool version.
2. Call `inspect` to preview the work plan.
3. Run with `--stdout --format json --error-format json`.
4. Parse `schemaVersion` and `toolVersion` before relying on the payload shape.

Example:

```bash
.build/release/apple-local-ocr inspect inbox/
.build/release/apple-local-ocr --stdout --format json --error-format json inbox/
```

JSON schema details are documented in [docs/json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md).

## Documentation

- English tutorial: [TUTORIAL.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/TUTORIAL.md)
- Chinese tutorial: [TUTORIAL_zh.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/TUTORIAL_zh.md)
- Chinese overview: [README_zh.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/README_zh.md)
- OpenClaw integration: [docs/openclaw-integration.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/openclaw-integration.md)
- OpenClaw examples: [docs/examples/README.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/examples/README.md)
- JSON schema: [docs/json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md)
- Technical notes: [docs/ocr-folder-feature-tech.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/ocr-folder-feature-tech.md)

## Test

```bash
swift test -v
```
