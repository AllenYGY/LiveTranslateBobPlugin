# Live Translate

在 **Bob** 中为英文课堂提供实时中文字幕的翻译插件，配套一个 macOS 麦克风伴随应用。不依赖 OverShelf。

在 Bob 翻译弹窗输入 `live` 即可开始：伴随应用用麦克风采集英语语音，经 Deepgram 转写、实时翻译后，字幕同时显示在 Bob 卡片、独立字幕浮窗和课程归档中。

## 工作原理

Bob 插件 API 不提供麦克风采集，也没有自定义弹窗按钮，因此本方案拆成两部分：

```
麦克风 ──► 伴随应用（LiveTranslate.app）──┬──► Deepgram Nova-3 英文转写
                                         └──► 翻译引擎 ──► 字幕 / 归档
   ▲                                              ▲
   │           127.0.0.1:17764　loopback          │
Bob 插件（Live Translate）◄──── 轮询快照 ──────────┘
```

- **Bob 插件**：提供设置项、渲染流式结果、响应 `live` / `stop` 指令。它只与本机伴随应用通信，不接触任何密钥。
- **伴随应用**：采集麦克风、直连 Deepgram（英文转写）、调用翻译引擎（默认 **Apple System Translate**，可选 **火山翻译**），并保存课程归档。

## 功能特性

- 实时双语字幕：英文原文 + 中文译文，随语音滚动更新
- 独立字幕浮窗：可拖动、调整大小、浮在课件上方，跨空间显示
- Bob 卡片保留最近两段，方便随手查看
- 课程归档：按 **课程 → 课次 → 双语分段** 组织，可新建课程、重命名课次、一键复制整节课记录
- 归档持久化：每段译文完成即保存，应用意外退出也不丢失已完成内容
- 密钥只在 Bob 中配置一次（存入钥匙串），伴随应用没有重复的设置页

## 系统要求

- macOS 26 或更新版本（依赖系统翻译框架，当前为 arm64 构建）
- 已安装「英语 → 简体中文」翻译语言包（Apple System Translate 需要）
- [Deepgram](https://deepgram.com) API Key（英文语音识别）
- Bob 1.21.0 或更新版本
- 选择火山翻译时，还需火山引擎 Access Key ID / Secret Access Key

## 构建与安装

```bash
./scripts/test-app.sh   # 生成 dist/LiveTranslate.app
./scripts/test.sh       # 生成 dist/LiveTranslate.bobplugin
```

1. 将 `dist/LiveTranslate.app` 放到本机可持续运行的位置（例如「应用程序」），双击打开。
2. 双击 `dist/LiveTranslate.bobplugin` 安装 Bob 插件。
3. 重新构建后，先退出旧版应用再打开新版。

## 使用

### 第一次配置（仅需在 Bob 中完成一次）

打开 **Bob → Services → Text Translate → Live Translate**：

| 设置项 | 说明 |
| --- | --- |
| Deepgram API Key (live speech) | 必填，课堂实时语音识别 |
| Live translation engine | `Apple System Translate`（默认）或 `Volcengine` |
| Volcengine Access Key ID / Secret Access Key | 选择火山翻译时必填 |

### 开始 / 停止

- 在 Bob 翻译弹窗输入 `live`（`/live` 也兼容，Bob 可能去掉斜杠）。
- 首次使用会请求麦克风权限，请允许。
- 输入 `stop`，或关闭 / 取消当前查询，即可停止录音。

### 字幕与记录

- **Bob 卡片**：保留最近两段的英文与中文译文。
- **字幕浮窗**：录音开始后自动弹出；主窗口工具栏的「课堂字幕」按钮可随时重新打开。
- **主窗口「实时记录」页**：完整的分段记录，录音前可选择所属课程；「清空当前显示」只清空屏幕，不影响归档。也可以通过主窗口的「开始」按钮直接录音（需已通过 Bob 保存 Deepgram 密钥）。

### 课程归档

- 录音前在「实时记录」页选择课程；每次录音自动在该课程下新建一节课。
- **主窗口「课程归档」页**：浏览任意历史课程与课次，重命名课次，或复制整节课的双语记录。
- 归档存放在本机 `~/Library/Application Support/LiveTranslate/archives.json`。
- 写入采用**原子替换**，文件权限仅当前用户可读（`0600`），且不含任何 API Key。
- 每段英文及最终译文都会及时保存，应用意外退出也能保留已完成内容。
- 若归档损坏或来自更新版本，应用会保留原文件并继续运行，绝不覆盖。

## 安全与隐私

- 插件与伴随应用仅在本机 `127.0.0.1:17764` 通信；本地桥会拒绝带 `Origin` 头的请求。
- 密钥由 Bob 设置界面发送到本机伴随应用并存入 **Keychain**，不会出现在 URL 或日志中。
- 英语音频由伴随应用直连 Deepgram；选择火山翻译时直连火山云。密钥与音频均不经过 Bob 插件。

## 已知限制

- Bob 插件最长可设置 300 秒超时，长课超过此限制时需重新输入 `live`；实际超时行为与 Bob 版本有关，仍需实机确认。
- 关闭字幕浮窗不会清空主窗口的复习记录。

## 项目结构

```
app/            macOS 伴随应用（SwiftUI）
  Services/     音频采集、Deepgram、翻译、归档、本地桥、字幕浮窗
  Views/        归档界面
plugin/         Bob 插件（info.json / main.js）与 Logo 源文件
scripts/        构建、打包、测试脚本
tests/          Swift / Node 测试
dist/           构建产物（git 忽略）
```

`plugin/logo.svg` 是透明圆角的矢量 Logo 源文件；`plugin/logo.png` 为 1024×1024 导出位图，同时用作插件图标与 macOS 应用图标。修改 SVG 后重新导出：

```bash
rsvg-convert -w 1024 -h 1024 plugin/logo.svg -o plugin/logo.png
```

## 开发与验证

```bash
./scripts/test.sh       # 插件：配置、流式结果、取消回调
./scripts/test-app.sh   # 应用：自动分段、归档持久化、编译与签名
curl http://127.0.0.1:17764/snapshot   # 检查本地桥是否在运行
```

真实麦克风和云端端到端验证需要有效的 Deepgram Key 与系统麦克风授权。