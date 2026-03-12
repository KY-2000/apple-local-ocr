# OCR Folder Feature Tech Notes (English + 中文)

## Original (English)

### 1) What this small feature does

This feature runs OCR for every image in a folder (for example `input/`) and writes one `.txt` file per image into `output/`.

Important: the Swift CLI processes one image per invocation. The "folder OCR" behavior is achieved by a shell loop that calls the CLI repeatedly.

### 2) Core technologies used

- Swift CLI app (`apple-local-ocr`)
- Apple VisionKit Live Text (`ImageAnalyzer`) for default OCR engine
- Apple Vision (`VNRecognizeTextRequest`) as optional OCR engine
- ImageIO (`CGImageSourceCreateWithURL`, `CGImageSourceCreateImageAtIndex`) for image decoding in Live Text path
- Foundation (`FileManager`, `URL`, file writing) for path handling and output

### 3) Main functions/classes involved

- `CLI.run(arguments:currentDirectory:)`
  - Main entry for command execution.
- `CLI.parse(arguments:)`
  - Parses flags like `--engine`, `--lang`, `--no-correction`, and image path.
- `CLI.defaultRecognizer(for:)`
  - Chooses OCR backend:
    - `liveText` -> `LiveTextOCRService`
    - `vision` -> `OCRService`
- `LiveTextOCRService.recognizeText(from:configuration:)`
  - Decodes image with ImageIO and runs `ImageAnalyzer.analyze(...)`.
- `OCRService.recognizeText(from:configuration:)`
  - Uses `VNRecognizeTextRequest` + `VNImageRequestHandler` to read text.
- `OutputWriter.defaultOutputURL(forInput:workingDirectory:)`
  - Converts image filename to output `.txt` path under `output/`.
- `OutputWriter.write(text:to:)`
  - Creates output directory (if missing) and writes UTF-8 text file.

### 4) Batch execution pattern (folder-level)

Example shell pattern:

```bash
find input -maxdepth 1 -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' -o -iname '*.tiff' -o -iname '*.bmp' -o -iname '*.gif' \) \
  -print0 | sort -z | while IFS= read -r -d '' img; do
    ./.build/release/apple-local-ocr "$img"
  done
```

This keeps OCR logic inside the Swift CLI, while using shell scripting for multi-file orchestration.

---

## 中文版 (Chinese)

### 1) 这个小功能做了什么

这个功能会对一个文件夹中的所有图片（例如 `input/`）逐个执行 OCR，并在 `output/` 里为每张图片生成一个对应的 `.txt` 文件。

重点：Swift CLI 本身一次只处理一张图片。"整文件夹 OCR" 是通过 shell 循环多次调用 CLI 实现的。

### 2) 使用到的核心技术

- Swift 命令行程序（`apple-local-ocr`）
- Apple VisionKit Live Text（`ImageAnalyzer`）作为默认 OCR 引擎
- Apple Vision（`VNRecognizeTextRequest`）作为可选 OCR 引擎
- ImageIO（`CGImageSourceCreateWithURL`、`CGImageSourceCreateImageAtIndex`）用于 Live Text 路径的图片解码
- Foundation（`FileManager`、`URL`、文件写入）用于路径处理与输出落盘

### 3) 关键函数/类

- `CLI.run(arguments:currentDirectory:)`
  - 命令执行入口。
- `CLI.parse(arguments:)`
  - 解析 `--engine`、`--lang`、`--no-correction` 以及图片路径。
- `CLI.defaultRecognizer(for:)`
  - 选择 OCR 后端：
    - `liveText` -> `LiveTextOCRService`
    - `vision` -> `OCRService`
- `LiveTextOCRService.recognizeText(from:configuration:)`
  - 使用 ImageIO 解码图片，再调用 `ImageAnalyzer.analyze(...)` 做识别。
- `OCRService.recognizeText(from:configuration:)`
  - 使用 `VNRecognizeTextRequest` + `VNImageRequestHandler` 识别文字。
- `OutputWriter.defaultOutputURL(forInput:workingDirectory:)`
  - 把输入图片名映射为 `output/` 下对应的 `.txt` 路径。
- `OutputWriter.write(text:to:)`
  - 自动创建输出目录（如果不存在）并写入 UTF-8 文本文件。

### 4) 批量执行方式（文件夹级）

示例 shell 批处理：

```bash
find input -maxdepth 1 -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' -o -iname '*.tiff' -o -iname '*.bmp' -o -iname '*.gif' \) \
  -print0 | sort -z | while IFS= read -r -d '' img; do
    ./.build/release/apple-local-ocr "$img"
  done
```

这样可以保持 OCR 核心能力在 Swift CLI 内部，同时用 shell 负责多文件调度。
