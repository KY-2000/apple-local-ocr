# JSON Output Schema

`apple-local-ocr` exposes two machine-readable JSON payload families:

- OCR result payloads from `--format json`
- Error payloads from `--error-format json`

The current schema version is `1.0`.

## Result Payload

Single-item runs emit one JSON object. Multi-item `--stdout --format json` runs emit an array of objects with the same shape.

Fields:

| Field | Type | Notes |
|-------|------|-------|
| `schemaVersion` | string | Current schema version, for example `1.0` |
| `toolVersion` | string | CLI version reported by `--version` |
| `inputPath` | string | Absolute or resolved input path processed by the CLI |
| `outputPath` | string or null | Output file path when writing files, otherwise `null` |
| `engine` | string | `vision` or `liveText` |
| `languages` | string array | Requested OCR languages |
| `format` | string | `json` |
| `text` | string | Final OCR text after cleanup rules |
| `pageNumber` | integer or null | Present for per-page PDF output |
| `pages` | array or null | Present for combined PDF JSON output |

Example image result:

```json
{
  "engine": "liveText",
  "format": "json",
  "inputPath": "/tmp/invoice.png",
  "languages": [
    "zh-Hans",
    "en-US"
  ],
  "outputPath": "/tmp/out/invoice.json",
  "pageNumber": null,
  "pages": null,
  "schemaVersion": "1.0",
  "text": "Invoice total 42.00",
  "toolVersion": "0.4.0"
}
```

Example combined PDF result:

```json
{
  "engine": "liveText",
  "format": "json",
  "inputPath": "/tmp/report.pdf",
  "languages": [
    "zh-Hans",
    "en-US"
  ],
  "outputPath": "/tmp/out/report.json",
  "pageNumber": null,
  "pages": [
    {
      "pageNumber": 1,
      "text": "First page"
    },
    {
      "pageNumber": 2,
      "text": "Second page"
    }
  ],
  "schemaVersion": "1.0",
  "text": "First page\n\nSecond page",
  "toolVersion": "0.4.0"
}
```

## Error Payload

When `--error-format json` is set, stderr emits a single JSON object with this shape:

| Field | Type | Notes |
|-------|------|-------|
| `schemaVersion` | string | Current schema version |
| `toolVersion` | string | CLI version reported by `--version` |
| `kind` | string | `usage_error`, `configuration_error`, `input_error`, `processing_error`, or `internal_error` |
| `message` | string | Summary of the failure |
| `exitCode` | integer | Exit code returned by the process |
| `errors` | string array or null | Optional detailed per-item errors for batch failures |

Example:

```json
{
  "exitCode": 64,
  "kind": "usage_error",
  "message": "Invalid engine 'invalid'. Use 'vision' or 'liveText'.",
  "schemaVersion": "1.0",
  "toolVersion": "0.4.0"
}
```

## Stability Notes

- Treat `schemaVersion` as the compatibility boundary for parsers.
- Treat new fields as additive unless the schema version changes.
- Pin `toolVersion` in agent deployments when reproducibility matters.
