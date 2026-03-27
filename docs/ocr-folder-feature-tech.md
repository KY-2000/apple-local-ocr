# OCR Folder Feature Tech Notes (English + 中文)

## Original (English)

### 1) What this small feature does

This feature runs OCR for one or more image inputs, PDF inputs, and directory inputs, and writes OCR output in `txt`, `json`, or `md` format.

The CLI now supports both:
- single image input
- single PDF input
- directory input (non-recursive)
- recursive directory input
- multiple file and directory inputs in one invocation

Phase 1 also adds:
- custom output directory selection
- stdout mode
- overwrite policy selection (`overwrite`, `skip`, `fail-on-existing`)
- optional preserve-structure output layout

Phase 2 adds:
- PDF page rendering and OCR
- `combined` vs `per-page` PDF output modes
- page-range selection
- page separators for combined PDF text output
- page metadata in JSON output

Phase 3 automation slice adds:
- `inspect` mode for job planning without OCR execution
- `languages` mode for supported OCR locale listing
- `--watch` for folder automation on new or changed files
- `--jobs` to limit concurrent OCR work
- `--normalize-whitespace` for lightweight whitespace cleanup
- `--trim-empty-lines` for blank-line removal before final rendering
- `--smart-quotes` for straight/curly quote normalization
- `--find` / `--replace` and `--dictionary` for rule-based text cleanup

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
  - Parses engine, language, output, traversal, overwrite, format, and logging flags.
- `CLI.resolveInputs(...)`
  - Expands mixed image/PDF/file/directory inputs into grouped OCR jobs.
- `CLI.supportedInputFiles(in:recursive:)`
  - Filters supported image and PDF files from directories and optionally recurses.
- `PDFRenderer.renderDocument(at:selectedPages:)`
  - Renders selected PDF pages into temporary image files so the existing OCR engines can process them.
- `PageSelection.parse(...)`
  - Parses page range input like `1-3,5`.
- `CLI.makeProcessedOutput(...)`
  - Combines PDF page OCR results into a single output or per-page outputs.
- `CLI.executeJobs(...)`
  - Runs OCR jobs sequentially or with a caller-defined concurrency cap.
- `CLI.runWatch(...)`
  - Polls a directory for new or changed OCR inputs and processes them until cancellation.
- `CLI.makeLanguagesOutput(...)`
  - Lists supported OCR locales for one or both OCR engines.
- `CLI.makeInspectOutput(...)`
  - Prints the resolved OCR job plan without running OCR.
- `CLI.makePostProcessor(...)`
  - Builds the cleanup pipeline from whitespace, replacement, dictionary, and smart-quotes options.
- `PostProcessor.apply(...)`
  - Applies cleanup rules after OCR and before final rendering.
- `CLI.renderOutput(...)`
  - Renders OCR result as `txt`, `json`, or `md`.
- `CLI.defaultRecognizer(for:)`
  - Chooses OCR backend:
    - `liveText` -> `LiveTextOCRService`
    - `vision` -> `OCRService`
- `OCRLanguageSupport.supportedLanguages(for:)`
  - Reads supported OCR locales from Apple OCR APIs.
- `LiveTextOCRService.recognizeText(from:configuration:)`
  - Decodes image with ImageIO and runs `ImageAnalyzer.analyze(...)`.
- `OCRService.recognizeText(from:configuration:)`
  - Uses `VNRecognizeTextRequest` + `VNImageRequestHandler` to read text.
- `OutputWriter.defaultOutputURL(forInput:workingDirectory:)`
  - Converts image filename to output `.txt` path under `output/`.
- `OutputWriter.outputURL(forInput:outputDirectory:relativeOutputPath:format:)`
  - Builds output paths for custom directories, formats, and preserve-structure layouts.
- `OutputWriter.write(text:to:)`
  - Creates output directory (if missing) and writes UTF-8 text file.

### 4) Folder-level run pattern

Example:

```bash
.build/release/apple-local-ocr --recursive --preserve-structure --output out input
```

Directory behavior:
- scans supported image and PDF files in `input/`
- optionally recurses into subfolders
- writes output to `output/` by default or to a custom directory via `--output`
- can preserve the input folder structure via `--preserve-structure`
- skips existing files by default unless overwrite policy is changed
- can process resolved jobs with bounded concurrency via `--jobs`
- prints a summary: total files, wrote count, skipped count, failed count, elapsed time

### 5) PDF run pattern

Examples:

```bash
.build/release/apple-local-ocr report.pdf
.build/release/apple-local-ocr --pdf-mode per-page report.pdf
.build/release/apple-local-ocr --page-range 1-3,5 report.pdf
.build/release/apple-local-ocr --page-separator "\n--PAGE--\n" report.pdf
```

PDF behavior:
- renders PDF pages to temporary images using Apple-native APIs
- runs the existing OCR pipeline against those page images
- in `combined` mode, merges page text into one output file
- in `per-page` mode, writes one output file per page
- in `json` mode, includes page-level metadata for combined PDF output

### 6) Automation-focused behavior

Examples:

```bash
.build/release/apple-local-ocr languages
.build/release/apple-local-ocr inspect --pdf-mode per-page scans
.build/release/apple-local-ocr --watch inbox --output out
.build/release/apple-local-ocr --jobs 4 scans invoices report.pdf
.build/release/apple-local-ocr --find "rn" --replace "m" messy.png
.build/release/apple-local-ocr --dictionary cleanup-rules.txt --smart-quotes off messy.png
```

Automation behavior:
- `inspect` shows how the CLI resolved images, PDFs, and per-page PDF jobs without running the OCR recognizer
- `languages` reports the locale list exposed by Apple OCR APIs
- `--watch` continuously scans for new or changed supported files and reuses the same OCR pipeline
- `--jobs` limits how many OCR jobs run at the same time, which is useful for agents and batch shells
- cleanup flags and replacement rules are applied after OCR text is recognized and before final output is written or printed
- dictionary files accept either `find<TAB>replace` or `find => replace` rules

---

## 中文版 (Chinese)

### 1) 这个小功能做了什么

这个功能现在支持单图、多图、PDF、文件夹输入，并把 OCR 结果输出为 `txt`、`json` 或 `md`。

CLI 现在同时支持：
- 单图输入
- 单个 PDF 输入
- 文件夹输入（非递归）
- 文件夹输入（递归）
- 一次传入多个文件和文件夹

Phase 1 还增加了：
- 自定义输出目录
- `stdout` 输出模式
- 输出覆盖策略（覆盖、跳过、遇到已存在即失败）
- 保留输入目录结构的输出方式

Phase 2 还增加了：
- PDF 页面渲染与 OCR
- `combined` / `per-page` 两种 PDF 输出模式
- 页码范围选择
- 合并输出时的分页分隔符
- JSON 输出中的页级元数据

Phase 3 的第一批自动化能力还增加了：
- `inspect` 规划模式，只展示任务，不执行 OCR
- `languages` 支持语言列表模式
- `--watch` 文件夹监控模式
- `--jobs` 并发上限控制
- `--normalize-whitespace` 轻量空白字符整理
- `--trim-empty-lines` 空行清理
- `--smart-quotes` 引号风格整理
- `--find` / `--replace` 与 `--dictionary` 文本替换规则

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
  - 解析引擎、语言、输出、遍历、覆盖策略、格式和日志相关参数。
- `CLI.resolveInputs(...)`
  - 把图片、PDF、文件、目录输入展开成统一的 OCR 任务列表。
- `CLI.supportedInputFiles(in:recursive:)`
  - 在目录中筛选支持的图片和 PDF，并按需递归。
- `PDFRenderer.renderDocument(at:selectedPages:)`
  - 把选中的 PDF 页面渲染成临时图片，让现有 OCR 引擎复用同一套流程。
- `PageSelection.parse(...)`
  - 解析 `1-3,5` 这类页码范围参数。
- `CLI.makeProcessedOutput(...)`
  - 将 PDF 页面的 OCR 结果合并成单文件输出，或拆成逐页输出。
- `CLI.executeJobs(...)`
  - 按顺序或按并发上限执行 OCR 任务。
- `CLI.runWatch(...)`
  - 轮询目录中的新增或变更 OCR 输入，直到命令被取消。
- `CLI.makeLanguagesOutput(...)`
  - 输出一个或两个 OCR 引擎支持的语言列表。
- `CLI.makeInspectOutput(...)`
  - 输出解析后的 OCR 任务清单，而不真正执行 OCR。
- `CLI.makePostProcessor(...)`
  - 根据空白清理、替换规则、字典文件和智能引号选项构建后处理管线。
- `PostProcessor.apply(...)`
  - 在 OCR 完成后、最终输出前统一执行文本清理。
- `CLI.renderOutput(...)`
  - 把 OCR 结果渲染成 `txt`、`json` 或 `md`。
- `CLI.defaultRecognizer(for:)`
  - 选择 OCR 后端：
    - `liveText` -> `LiveTextOCRService`
    - `vision` -> `OCRService`
- `OCRLanguageSupport.supportedLanguages(for:)`
  - 从 Apple OCR API 读取支持的语言列表。
- `LiveTextOCRService.recognizeText(from:configuration:)`
  - 使用 ImageIO 解码图片，再调用 `ImageAnalyzer.analyze(...)` 做识别。
- `OCRService.recognizeText(from:configuration:)`
  - 使用 `VNRecognizeTextRequest` + `VNImageRequestHandler` 识别文字。
- `OutputWriter.defaultOutputURL(forInput:workingDirectory:)`
  - 把输入图片名映射为 `output/` 下对应的 `.txt` 路径。
- `OutputWriter.outputURL(forInput:outputDirectory:relativeOutputPath:format:)`
  - 根据输出目录、格式和目录结构生成最终输出路径。
- `OutputWriter.write(text:to:)`
  - 自动创建输出目录（如果不存在）并写入 UTF-8 文本文件。

### 4) 文件夹运行方式

示例：

```bash
.build/release/apple-local-ocr --recursive --preserve-structure --output out input
```

文件夹模式行为：
- 扫描 `input/` 中支持的图片和 PDF
- 可选递归扫描子目录
- 默认输出到 `output/`，也可通过 `--output` 改到自定义目录
- 可用 `--preserve-structure` 保留输入目录结构
- 默认跳过已存在输出，也可切换覆盖策略
- 可通过 `--jobs` 控制同时运行的 OCR 任务数
- 结束后输出汇总：总文件数、写入数、跳过数、失败数、耗时

### 5) PDF 运行方式

示例：

```bash
.build/release/apple-local-ocr report.pdf
.build/release/apple-local-ocr --pdf-mode per-page report.pdf
.build/release/apple-local-ocr --page-range 1-3,5 report.pdf
.build/release/apple-local-ocr --page-separator "\n--PAGE--\n" report.pdf
```

PDF 模式行为：
- 使用 Apple 原生 API 把 PDF 页面渲染成临时图片
- 复用现有 OCR 管线识别这些页面图片
- `combined` 模式下把多页文本合并成一个输出文件
- `per-page` 模式下每页生成一个输出文件
- `json` 模式下为合并后的 PDF 输出附带页级元数据

### 6) 自动化导向的 CLI 行为

示例：

```bash
.build/release/apple-local-ocr languages
.build/release/apple-local-ocr inspect --pdf-mode per-page scans
.build/release/apple-local-ocr --watch inbox --output out
.build/release/apple-local-ocr --jobs 4 scans invoices report.pdf
.build/release/apple-local-ocr --find "rn" --replace "m" messy.png
.build/release/apple-local-ocr --dictionary cleanup-rules.txt --smart-quotes off messy.png
```

自动化相关行为：
- `inspect` 只展示图片、PDF、逐页 PDF 任务的解析结果，不真正跑 OCR
- `languages` 会输出 Apple OCR API 当前暴露的支持语言列表
- `--watch` 会持续扫描新增或变更的支持文件，并复用同一套 OCR 流程
- `--jobs` 限制同时执行的 OCR 任务数量，适合 agent 和批处理场景
- 文本清理参数和替换规则会在 OCR 识别完成后、最终输出前统一生效
- 字典文件支持 `find<TAB>replace` 或 `find => replace` 两种规则格式
