# apple-local-ocr Tutorial

This tutorial explains how to use every command and flag in `apple-local-ocr`.

It is written for:

- terminal users who want to OCR files locally on macOS
- developers who want to script the tool
- AI agents that need deterministic OCR with JSON output

## 1. Install And Verify

Build the release binary:

```bash
swift build -c release
```

Check that the binary works:

```bash
.build/release/apple-local-ocr --version
.build/release/apple-local-ocr --help
```

Run tests if you want to verify the local environment:

```bash
swift test -v
```

## 2. Core Mental Model

`apple-local-ocr` has four main entry points:

- normal run: OCR files and folders
- `inspect`: show what would be processed without running OCR
- `languages`: show supported OCR languages
- `--version`: show the CLI version

The tool accepts:

- image files
- PDF files
- folders containing supported files
- multiple inputs in one command

The tool can output:

- text files
- markdown files
- JSON files
- direct stdout output

## 3. Basic Usage

OCR one image:

```bash
.build/release/apple-local-ocr image.png
```

OCR multiple inputs:

```bash
.build/release/apple-local-ocr image.png report.pdf scans/
```

Write files into a custom directory:

```bash
.build/release/apple-local-ocr --output out scans/
```

Print OCR result to stdout:

```bash
.build/release/apple-local-ocr --stdout image.png
```

## 4. Supported Inputs

Supported file types:

- `pdf`
- `png`
- `jpg`
- `jpeg`
- `heic`
- `tiff`
- `bmp`
- `gif`

Folder inputs:

- are scanned for supported files
- can be flat or recursive
- can be mixed with direct file paths

## 5. Commands

### Normal Run

Use the default command form when you want OCR to actually run:

```bash
.build/release/apple-local-ocr [options] <path1> <path2> ...
```

### `inspect`

Use `inspect` when you want to preview the planned OCR jobs without running OCR.

```bash
.build/release/apple-local-ocr inspect scans/
```

Typical use:

- confirm which files will be processed
- confirm PDF page expansion
- confirm output paths before running OCR

### `languages`

Use `languages` to list supported OCR languages.

List both engines:

```bash
.build/release/apple-local-ocr languages
```

List one engine only:

```bash
.build/release/apple-local-ocr languages --engine vision
```

### `--version`

Use `--version` to print the CLI version and exit immediately.

```bash
.build/release/apple-local-ocr --version
```

This is especially useful for scripts and AI agents.

## 6. OCR Engine And Language Flags

### `--engine vision|liveText`

Choose the OCR engine.

```bash
.build/release/apple-local-ocr --engine vision image.png
.build/release/apple-local-ocr --engine liveText image.png
```

Notes:

- default is `liveText`
- `vision` uses `VNRecognizeTextRequest`
- `liveText` uses VisionKit Live Text APIs

### `--lang code1,code2`

Set OCR languages explicitly.

```bash
.build/release/apple-local-ocr --lang en-US image.png
.build/release/apple-local-ocr --lang zh-Hans,en-US image.png
```

Notes:

- default is `zh-Hans,en-US`
- use `languages` to discover supported values

### `--no-correction`

Disable language correction.

```bash
.build/release/apple-local-ocr --engine vision --no-correction image.png
```

Notes:

- mainly relevant for `vision`
- useful when language correction harms raw OCR output

## 7. Output Flags

### `--output PATH`

Choose the output directory.

```bash
.build/release/apple-local-ocr --output out scans/
```

Default output directory:

- `output/`

### `--stdout`

Print OCR output to stdout instead of writing files.

```bash
.build/release/apple-local-ocr --stdout image.png
```

Notes:

- no output file is written
- useful for pipelines and AI agents
- cannot be combined with `--watch`

### `--format txt|json|md`

Choose the output format.

```bash
.build/release/apple-local-ocr --format txt image.png
.build/release/apple-local-ocr --format json image.png
.build/release/apple-local-ocr --format md image.png
```

Behavior:

- `txt`: plain OCR text
- `json`: structured OCR payload
- `md`: Markdown with source metadata and page headings for combined PDFs

### `--error-format text|json`

Choose how errors are rendered to stderr.

```bash
.build/release/apple-local-ocr --error-format text image.png
.build/release/apple-local-ocr --error-format json missing.png
```

Behavior:

- `text`: human-readable stderr
- `json`: machine-readable stderr with `kind`, `message`, and `exitCode`

AI-agent recommendation:

```bash
.build/release/apple-local-ocr --stdout --format json --error-format json scans/
```

## 8. Batch And Folder Flags

### `--recursive`

Recursively scan folder inputs.

```bash
.build/release/apple-local-ocr --recursive scans/
```

Without `--recursive`, only the top level of the folder is scanned.

### `--preserve-structure`

Preserve the input folder structure under the output directory.

```bash
.build/release/apple-local-ocr --recursive --preserve-structure --output out scans/
```

Example:

- input: `scans/2026/invoice.png`
- output: `out/scans/2026/invoice.txt`

### `--overwrite`

Overwrite existing output files.

```bash
.build/release/apple-local-ocr --overwrite scans/
```

### `--skip`

Skip items whose output already exists.

```bash
.build/release/apple-local-ocr --skip scans/
```

Notes:

- this is the default behavior

### `--fail-on-existing`

Fail items whose output already exists.

```bash
.build/release/apple-local-ocr --fail-on-existing scans/
```

Use this when you want strict automation and do not want silent skipping.

### `--jobs N`

Run multiple OCR jobs in parallel.

```bash
.build/release/apple-local-ocr --jobs 4 scans/
```

Notes:

- default is `1`
- useful for folders and multi-page PDFs
- use a moderate number to avoid oversubscribing the machine

## 9. PDF Flags

### `--pdf-mode combined|per-page`

Choose how PDFs are emitted.

```bash
.build/release/apple-local-ocr --pdf-mode combined report.pdf
.build/release/apple-local-ocr --pdf-mode per-page report.pdf
```

Behavior:

- `combined`: one output per PDF
- `per-page`: one output per page

### `--page-range LIST`

OCR only selected PDF pages.

```bash
.build/release/apple-local-ocr --page-range 1-3,5 report.pdf
```

Examples:

- `1`
- `1-3`
- `1-3,5,8-10`

### `--page-separator TEXT`

Control how page text is joined in combined PDF mode.

```bash
.build/release/apple-local-ocr --page-separator "\n---\n" report.pdf
```

Notes:

- mainly useful with `--pdf-mode combined`
- ignored for `per-page`

## 10. Cleanup And Post-Processing Flags

These flags modify OCR text after recognition and before output is rendered.

### `--normalize-whitespace`

Collapse internal runs of spaces and tabs within each line.

```bash
.build/release/apple-local-ocr --normalize-whitespace image.png
```

### `--trim-empty-lines`

Remove blank lines from OCR output.

```bash
.build/release/apple-local-ocr --trim-empty-lines image.png
```

### `--smart-quotes on|off`

Convert between straight and curly quotes.

```bash
.build/release/apple-local-ocr --smart-quotes on image.png
.build/release/apple-local-ocr --smart-quotes off image.png
```

Behavior:

- `on`: tries to convert straight quotes to curly quotes
- `off`: normalizes curly quotes back to ASCII quotes

### `--find TEXT`

Provide a direct replacement search string.

```bash
.build/release/apple-local-ocr --find rn --replace m image.png
```

### `--replace TEXT`

Replacement text used together with `--find`.

```bash
.build/release/apple-local-ocr --find teh --replace the image.png
```

Important:

- `--find` and `--replace` must be used together

### `--dictionary PATH`

Load replacement rules from a text file.

```bash
.build/release/apple-local-ocr --dictionary cleanup-rules.txt image.png
```

Supported rule formats:

```text
teh	the
reciept	receipt
foo => bar
```

Notes:

- blank lines are ignored
- lines starting with `#` are ignored

## 11. Runtime And Logging Flags

### `--watch PATH`

Watch a folder for new or changed supported files and OCR them continuously.

```bash
.build/release/apple-local-ocr --watch inbox --output out
```

Behavior:

- runs until cancelled
- polls the directory for changes
- can be combined with `--recursive`
- reuses the same OCR pipeline as normal runs

Important:

- cannot be combined with direct input paths
- cannot be combined with `inspect`
- cannot be combined with `--stdout`

### `--quiet`

Suppress success logs.

```bash
.build/release/apple-local-ocr --quiet scans/
```

Errors still appear.

### `--verbose`

Enable detailed success logs.

```bash
.build/release/apple-local-ocr --verbose scans/
```

## 12. Common Recipes

OCR one image to the default `output/` folder:

```bash
.build/release/apple-local-ocr note.png
```

OCR a folder into JSON files:

```bash
.build/release/apple-local-ocr --format json --output out scans/
```

OCR a PDF page-by-page:

```bash
.build/release/apple-local-ocr --pdf-mode per-page report.pdf
```

Preview work before running a big batch:

```bash
.build/release/apple-local-ocr inspect --recursive scans/
```

Process a watch folder with cleanup rules:

```bash
.build/release/apple-local-ocr \
  --watch inbox \
  --output out \
  --dictionary cleanup-rules.txt \
  --normalize-whitespace
```

## 13. AI Agent Workflow

Recommended agent workflow:

1. Discover the tool version.
2. Inspect the planned work.
3. Run with JSON output and JSON errors.
4. Parse only documented fields.

Example:

```bash
.build/release/apple-local-ocr --version
.build/release/apple-local-ocr inspect --recursive inbox/
.build/release/apple-local-ocr --stdout --format json --error-format json --recursive inbox/
```

What agents should rely on:

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

Error JSON fields:

- `schemaVersion`
- `toolVersion`
- `kind`
- `message`
- `exitCode`
- `errors`

Schema details:

- see [docs/json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md)

## 14. Exit Codes

| Exit code | Meaning |
|-----------|---------|
| `0` | Success |
| `1` | OCR or batch processing had one or more failures |
| `64` | Invalid CLI usage or invalid flag values |
| `65` | Supported input type was given, but no OCR work could be derived |
| `66` | Input path, watch path, or dictionary path could not be found or read |
| `70` | Internal or environment failure |

## 15. Common Mistakes

`languages` with input paths:

- invalid

```bash
.build/release/apple-local-ocr languages scans/
```

`--watch` with `--stdout`:

- invalid

```bash
.build/release/apple-local-ocr --watch inbox --stdout
```

`--find` without `--replace`:

- invalid

```bash
.build/release/apple-local-ocr --find rn image.png
```

Wrong engine name:

- invalid

```bash
.build/release/apple-local-ocr --engine invalid image.png
```

## 16. Where To Go Next

- Overview: [README.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/README.md)
- Chinese overview: [README_zh.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/README_zh.md)
- Chinese tutorial: [TUTORIAL_zh.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/TUTORIAL_zh.md)
- OpenClaw integration: [docs/openclaw-integration.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/openclaw-integration.md)
- JSON schema: [docs/json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md)
