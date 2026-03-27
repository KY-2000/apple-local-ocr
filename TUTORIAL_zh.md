# apple-local-ocr 使用教程

这份教程会完整说明 `apple-local-ocr` 的所有命令与参数。

适合这些读者：

- 想在 macOS 终端里本地做 OCR 的用户
- 想把这个工具接入脚本或自动化流程的开发者
- 想让 AI agent 在本地完成 OCR 的用户

## 1. 安装与验证

编译 release 版本：

```bash
swift build -c release
```

确认二进制可用：

```bash
.build/release/apple-local-ocr --version
.build/release/apple-local-ocr --help
```

如果你想验证本地开发环境，也可以运行：

```bash
swift test -v
```

## 2. 核心使用模型

`apple-local-ocr` 主要有四种入口：

- 普通运行：真正执行 OCR
- `inspect`：只预览会处理什么，不执行 OCR
- `languages`：查看支持的 OCR 语言
- `--version`：查看工具版本

输入可以是：

- 图片文件
- PDF 文件
- 文件夹
- 多个路径一起传入

输出可以是：

- 文本文件
- Markdown 文件
- JSON 文件
- 直接输出到 stdout

## 3. 基础用法

识别单张图片：

```bash
.build/release/apple-local-ocr image.png
```

一次处理多个输入：

```bash
.build/release/apple-local-ocr image.png report.pdf scans/
```

输出到自定义目录：

```bash
.build/release/apple-local-ocr --output out scans/
```

直接输出到终端：

```bash
.build/release/apple-local-ocr --stdout image.png
```

## 4. 支持的输入类型

支持的文件格式：

- `pdf`
- `png`
- `jpg`
- `jpeg`
- `heic`
- `tiff`
- `bmp`
- `gif`

文件夹输入：

- 会扫描其中支持的文件
- 可以只扫当前层，也可以递归
- 可以和单文件路径混合使用

## 5. 命令

### 普通运行

正常 OCR 的命令格式：

```bash
.build/release/apple-local-ocr [options] <path1> <path2> ...
```

### `inspect`

预览将要处理的 OCR 任务，但不真正执行 OCR：

```bash
.build/release/apple-local-ocr inspect scans/
```

典型用途：

- 确认哪些文件会被处理
- 确认 PDF 会拆成哪些页
- 确认输出路径是否符合预期

### `languages`

查看支持的 OCR 语言。

列出所有引擎：

```bash
.build/release/apple-local-ocr languages
```

只列出某一个引擎：

```bash
.build/release/apple-local-ocr languages --engine vision
```

### `--version`

输出版本号并立即退出：

```bash
.build/release/apple-local-ocr --version
```

这对脚本与 AI agent 很有用。

## 6. OCR 引擎与语言参数

### `--engine vision|liveText`

选择 OCR 引擎。

```bash
.build/release/apple-local-ocr --engine vision image.png
.build/release/apple-local-ocr --engine liveText image.png
```

说明：

- 默认是 `liveText`
- `vision` 使用 `VNRecognizeTextRequest`
- `liveText` 使用 VisionKit Live Text API

### `--lang code1,code2`

手动指定 OCR 语言。

```bash
.build/release/apple-local-ocr --lang en-US image.png
.build/release/apple-local-ocr --lang zh-Hans,en-US image.png
```

说明：

- 默认是 `zh-Hans,en-US`
- 可以先用 `languages` 查询支持的语言值

### `--no-correction`

关闭语言纠错。

```bash
.build/release/apple-local-ocr --engine vision --no-correction image.png
```

说明：

- 主要对 `vision` 有意义
- 当自动纠错反而影响原始 OCR 结果时很有用

## 7. 输出参数

### `--output PATH`

指定输出目录。

```bash
.build/release/apple-local-ocr --output out scans/
```

默认输出目录：

- `output/`

### `--stdout`

把 OCR 结果直接输出到终端，而不是写入文件。

```bash
.build/release/apple-local-ocr --stdout image.png
```

说明：

- 不会写输出文件
- 适合管道、脚本、AI agent
- 不能和 `--watch` 一起使用

### `--format txt|json|md`

指定输出格式。

```bash
.build/release/apple-local-ocr --format txt image.png
.build/release/apple-local-ocr --format json image.png
.build/release/apple-local-ocr --format md image.png
```

说明：

- `txt`：纯文本
- `json`：结构化输出
- `md`：Markdown 输出，合并 PDF 时会带页标题

### `--error-format text|json`

指定 stderr 错误输出格式。

```bash
.build/release/apple-local-ocr --error-format text image.png
.build/release/apple-local-ocr --error-format json missing.png
```

说明：

- `text`：适合人看
- `json`：适合机器解析

给 AI agent 的推荐组合：

```bash
.build/release/apple-local-ocr --stdout --format json --error-format json scans/
```

## 8. 批处理与文件夹参数

### `--recursive`

递归扫描文件夹。

```bash
.build/release/apple-local-ocr --recursive scans/
```

如果不加 `--recursive`，只扫描顶层目录。

### `--preserve-structure`

在输出目录下保留原始目录结构。

```bash
.build/release/apple-local-ocr --recursive --preserve-structure --output out scans/
```

例子：

- 输入：`scans/2026/invoice.png`
- 输出：`out/scans/2026/invoice.txt`

### `--overwrite`

覆盖已有输出文件。

```bash
.build/release/apple-local-ocr --overwrite scans/
```

### `--skip`

如果输出已存在，就跳过。

```bash
.build/release/apple-local-ocr --skip scans/
```

说明：

- 这是默认行为

### `--fail-on-existing`

如果输出已存在，就把该项当作失败。

```bash
.build/release/apple-local-ocr --fail-on-existing scans/
```

适合严格自动化流程。

### `--jobs N`

并行执行多个 OCR 任务。

```bash
.build/release/apple-local-ocr --jobs 4 scans/
```

说明：

- 默认是 `1`
- 对文件夹批处理和多页 PDF 很有用
- 不建议设置过大，避免机器过载

## 9. PDF 参数

### `--pdf-mode combined|per-page`

控制 PDF 输出方式。

```bash
.build/release/apple-local-ocr --pdf-mode combined report.pdf
.build/release/apple-local-ocr --pdf-mode per-page report.pdf
```

说明：

- `combined`：一个 PDF 输出一个文件
- `per-page`：每一页输出一个文件

### `--page-range LIST`

只处理指定 PDF 页码。

```bash
.build/release/apple-local-ocr --page-range 1-3,5 report.pdf
```

示例：

- `1`
- `1-3`
- `1-3,5,8-10`

### `--page-separator TEXT`

在合并 PDF 模式下指定页与页之间的分隔符。

```bash
.build/release/apple-local-ocr --page-separator "\n---\n" report.pdf
```

说明：

- 主要用于 `--pdf-mode combined`
- 对 `per-page` 没有意义

## 10. 清理与后处理参数

这些参数会在 OCR 完成后、输出前修改文本。

### `--normalize-whitespace`

压缩每一行内部重复的空格和 tab。

```bash
.build/release/apple-local-ocr --normalize-whitespace image.png
```

### `--trim-empty-lines`

删除空白行。

```bash
.build/release/apple-local-ocr --trim-empty-lines image.png
```

### `--smart-quotes on|off`

在直引号和弯引号之间做转换。

```bash
.build/release/apple-local-ocr --smart-quotes on image.png
.build/release/apple-local-ocr --smart-quotes off image.png
```

说明：

- `on`：尽量把直引号转成弯引号
- `off`：把弯引号转回 ASCII 引号

### `--find TEXT`

指定要查找的文本。

```bash
.build/release/apple-local-ocr --find rn --replace m image.png
```

### `--replace TEXT`

和 `--find` 搭配使用，指定替换文本。

```bash
.build/release/apple-local-ocr --find teh --replace the image.png
```

注意：

- `--find` 和 `--replace` 必须一起使用

### `--dictionary PATH`

从文本文件加载替换规则。

```bash
.build/release/apple-local-ocr --dictionary cleanup-rules.txt image.png
```

支持格式：

```text
teh	the
reciept	receipt
foo => bar
```

说明：

- 空行会被忽略
- 以 `#` 开头的行会被忽略

## 11. 运行与日志参数

### `--watch PATH`

持续监听一个目录中的新文件或变更文件，并自动执行 OCR。

```bash
.build/release/apple-local-ocr --watch inbox --output out
```

说明：

- 会一直运行，直到被取消
- 使用轮询方式检测文件变化
- 可以和 `--recursive` 一起使用
- 会复用普通运行模式的同一套 OCR 流程

注意：

- 不能和直接输入路径一起用
- 不能和 `inspect` 一起用
- 不能和 `--stdout` 一起用

### `--quiet`

隐藏成功日志。

```bash
.build/release/apple-local-ocr --quiet scans/
```

错误仍然会输出。

### `--verbose`

输出更详细的成功日志。

```bash
.build/release/apple-local-ocr --verbose scans/
```

## 12. 常见使用场景

识别单张图片，输出到默认 `output/`：

```bash
.build/release/apple-local-ocr note.png
```

把文件夹 OCR 成 JSON 文件：

```bash
.build/release/apple-local-ocr --format json --output out scans/
```

逐页 OCR 一个 PDF：

```bash
.build/release/apple-local-ocr --pdf-mode per-page report.pdf
```

大批量运行前先预览：

```bash
.build/release/apple-local-ocr inspect --recursive scans/
```

监听目录并配合文本清理：

```bash
.build/release/apple-local-ocr \
  --watch inbox \
  --output out \
  --dictionary cleanup-rules.txt \
  --normalize-whitespace
```

## 13. AI Agent 使用流程

推荐流程：

1. 先获取工具版本。
2. 再用 `inspect` 查看任务计划。
3. 正式运行时用 JSON 输出和 JSON 错误。
4. 只解析文档中承诺的字段。

示例：

```bash
.build/release/apple-local-ocr --version
.build/release/apple-local-ocr inspect --recursive inbox/
.build/release/apple-local-ocr --stdout --format json --error-format json --recursive inbox/
```

建议 AI agent 依赖这些字段：

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

错误 JSON 字段：

- `schemaVersion`
- `toolVersion`
- `kind`
- `message`
- `exitCode`
- `errors`

详细结构说明：

- 见 [docs/json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md)

## 14. 退出码

| 退出码 | 含义 |
|--------|------|
| `0` | 成功 |
| `1` | OCR 或批处理过程中有一项或多项失败 |
| `64` | 命令参数错误 |
| `65` | 输入类型受支持，但最终没有得到可执行的 OCR 任务 |
| `66` | 输入路径、监听路径、字典文件路径不存在或不可读 |
| `70` | 内部错误或环境错误 |

## 15. 常见错误

`languages` 后面跟输入路径：

- 无效

```bash
.build/release/apple-local-ocr languages scans/
```

`--watch` 和 `--stdout` 同时使用：

- 无效

```bash
.build/release/apple-local-ocr --watch inbox --stdout
```

只写 `--find` 不写 `--replace`：

- 无效

```bash
.build/release/apple-local-ocr --find rn image.png
```

错误的引擎名：

- 无效

```bash
.build/release/apple-local-ocr --engine invalid image.png
```

## 16. 下一步

- 英文概览：[README.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/README.md)
- 中文概览：[README_zh.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/README_zh.md)
- 英文完整教程：[TUTORIAL.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/TUTORIAL.md)
- JSON 结构说明：[docs/json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md)
