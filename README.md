# apple-local-ocr

Simple local OCR CLI for macOS using Apple's Vision framework.

## What it does

- Input: image file path (png, jpg, jpeg, heic, tiff, bmp, gif)
- OCR engine: Apple Vision (`vision`) or VisionKit Live Text (`liveText`)
- Output: `output/<input-file-name>.txt` in the current working directory

## Requirements

- macOS 13+
- Swift 5.10+
- Xcode Command Line Tools configured correctly

If you see `XCTest not available` or SDK/toolchain mismatch errors, run:

```bash
xcode-select --install
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Build

```bash
swift build -c release
```

## Run

```bash
.build/release/apple-local-ocr /absolute/or/relative/path/to/image.png
```

### Optional flags

```bash
.build/release/apple-local-ocr --engine liveText --lang zh-Hans,en-US --no-correction /path/to/image.jpg
```

- Default engine/languages: `liveText` + `zh-Hans,en-US`
- `--engine vision|liveText`
- `--lang code1,code2` (example: `zh-Hans,en-US`)
- `--no-correction` (Vision engine only)

Example output:

```text
OCR settings -> engine: liveText, languages: zh-Hans,en-US
Wrote OCR text to: /path/to/project/output/image.txt
```

## Tests

```bash
swift test -v
```

Test coverage includes:
- CLI argument validation
- Output path generation
- macOS integration OCR flow (generates an image, runs OCR, verifies output text)
