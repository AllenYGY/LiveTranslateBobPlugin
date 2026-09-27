# Live Translate Bob Plugin

独立 Bob 翻译插件：在 Bob 内配置 API Key，直接请求云翻译服务，将英文文本翻译成简体中文。插件不依赖 OverShelf，也不需要运行其他本地应用。

## 安装

1. 运行 `./scripts/package.sh`，生成 `dist/LiveTranslate.bobplugin`。
2. 双击安装包，在 Bob「偏好设置 → 服务」添加并启用 **Live Translate EN→ZH**。
3. 在该服务中填写 API Key。默认 API URL 和模型适用于 DeepSeek；若使用其他 OpenAI 兼容服务，修改 API URL 和 Model。
4. 点击 Bob 的「验证」，然后使用 Bob 划词翻译或输入英文文本翻译。

API Key 由 Bob 的安全输入框保存；插件直接发送给所配置的云服务。不会经过 OverShelf。

## 功能边界

Bob 的翻译插件 API 只能接收 Bob 提供的文本，不能采集麦克风或创建实时字幕窗口。因此课堂连续语音转文字和字幕无法仅靠 `.bobplugin` 实现，需要独立的 macOS 应用。Deepgram API Key 是语音转文字密钥，不能用于此文本翻译服务；这里需要 DeepSeek 或其他 OpenAI 兼容翻译模型的 API Key。

## 测试

运行 `./scripts/test.sh` 验证插件包结构和 Bob 回调逻辑。云端端到端测试需在 Bob 内填写有效 API Key 后点击「验证」。
