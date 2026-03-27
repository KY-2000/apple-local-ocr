# apple-local-ocr

`apple-local-ocr` 是一个基于 Apple Vision 与 VisionKit 的本地 OCR 命令行工具，运行在 macOS 上。

这个项目主要服务两类用户：

- 想要用终端快速处理图片、PDF、文件夹 OCR 的用户
- 需要本地、可预测、可输出 JSON 的 OCR 能力给 AI agent 使用的开发者

## 这个项目能做什么

- 一次处理单个或多个文件、文件夹
- 支持 `pdf`、`png`、`jpg`、`jpeg`、`heic`、`tiff`、`bmp`、`gif`
- 支持 `liveText` 与 `vision` 两种 OCR 引擎
- 输出 `txt`、`json`、`md`
- 支持批处理、递归扫描、目录监听、预检查模式
- 完全本地运行，不依赖云端 OCR

## 运行要求

- macOS 13 或以上
- Swift 5.10 或以上
- 如果要跑测试，建议使用完整 Xcode，并用 `xcode-select` 指向它

如果你的测试环境有问题，可以看这份说明：
[docs/plans/2026-03-25-xctest-toolchain-fix-plan.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/plans/2026-03-25-xctest-toolchain-fix-plan.md)

## 安装

目前推荐直接从源码编译：

```bash
swift build -c release
```

查看版本：

```bash
.build/release/apple-local-ocr --version
```

## 快速开始

识别单张图片：

```bash
.build/release/apple-local-ocr receipt.png
```

识别 PDF：

```bash
.build/release/apple-local-ocr report.pdf
```

递归处理文件夹，并保留目录结构：

```bash
.build/release/apple-local-ocr --recursive --preserve-structure --output out scans/
```

直接把 OCR 结果打印到终端，而不是写入文件：

```bash
.build/release/apple-local-ocr --stdout screenshot.png
```

给 AI agent 返回结构化 JSON：

```bash
.build/release/apple-local-ocr \
  --stdout \
  --format json \
  --error-format json \
  scans/
```

## 核心命令

- `apple-local-ocr [options] <path...>`：正常执行 OCR
- `apple-local-ocr inspect [options] <path...>`：只显示将要处理什么，不真正执行 OCR
- `apple-local-ocr languages [--engine vision|liveText]`：列出支持的 OCR 语言
- `apple-local-ocr --version`：输出版本号

## 默认行为

- 默认引擎：`liveText`
- 默认语言：`zh-Hans,en-US`
- 默认输出格式：`txt`
- 默认输出目录：`output/`
- 默认重名策略：`--skip`
- 默认 PDF 模式：`combined`
- 默认错误格式：`text`

## 给 AI Agents 的建议

推荐流程：

1. 先调用 `--version` 确认工具版本。
2. 再调用 `inspect` 查看将要处理的任务。
3. 正式运行时使用 `--stdout --format json --error-format json`。
4. 先解析 `schemaVersion` 和 `toolVersion`，再依赖 JSON 结构。

示例：

```bash
.build/release/apple-local-ocr inspect inbox/
.build/release/apple-local-ocr --stdout --format json --error-format json inbox/
```

JSON 输出结构说明在：
[docs/json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md)

## 文档

- 英文完整教程：[TUTORIAL.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/TUTORIAL.md)
- 中文完整教程：[TUTORIAL_zh.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/TUTORIAL_zh.md)
- OpenClaw 集成指南：[docs/openclaw-integration.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/openclaw-integration.md)
- OpenClaw 示例：[docs/examples/README.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/examples/README.md)
- JSON 结构文档：[docs/json-output-schema.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/json-output-schema.md)
- 技术说明：[docs/ocr-folder-feature-tech.md](/Users/kenyuen/Desktop/coding-project/apple-local-ocr/docs/ocr-folder-feature-tech.md)

## 测试

```bash
swift test -v
```
