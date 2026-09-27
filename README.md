# Live Translate Bob Plugin

独立 Bob 英译中项目。**默认翻译使用 Bob 内置的 Apple System Translate**；本插件提供额外的火山引擎机器翻译服务。两者都不依赖 OverShelf。

## 安装和配置

1. 运行 `./scripts/package.sh`，双击 `dist/LiveTranslate.bobplugin` 安装。
2. 在 Bob「偏好设置 → 服务 → 文本翻译」添加并启用内置 **System Translate**，把它排在翻译服务列表前面，作为默认结果。
3. 添加并启用插件 **Live Translate · 火山翻译**，在该服务中填写火山引擎的 **Access Key ID** 和 **Secret Access Key**，点击「验证」。
4. 用 Bob 划词或输入框翻译英文；Apple 结果优先显示，火山翻译提供另一份结果。

Apple 系统翻译是 Bob 的内置服务，插件 API 无法在 JavaScript 中直接调用 Apple Translation framework。火山翻译通过插件直接请求官方 `TranslateText` 接口，并使用签名 V4；密钥保存在 Bob 的安全输入框内。

## 测试

运行 `./scripts/test.sh` 校验打包结构、签名和翻译回调。真实火山接口测试需要在 Bob 中填写有效 AK/SK 后点击「验证」。

## 功能边界

Bob 翻译插件 API 不能采集麦克风或创建实时字幕窗口，因此课堂连续语音转文字仍需要独立 macOS 应用。

火山接口：[TranslateText](https://www.volcengine.com/docs/4640/65067)；[签名 V4](https://www.volcengine.com/docs/6369/67269)。
