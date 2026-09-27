# Live Translate

独立的课堂实时翻译项目，包含 **Live Translate macOS 应用**和 **Bob 文本翻译插件**，不依赖 OverShelf。

## 课堂实时翻译

运行 `./scripts/build-app.sh`，打开 `dist/LiveTranslate.app`。应用内点击「设置」：

1. 在「语音转文字 · Deepgram」填写 **Deepgram API Key** 并点击「验证 Deepgram」。麦克风音频直接发送到 Deepgram Nova-3，生成英文转写。
2. 「实时译文」默认选择 **Apple System Translate**，无需翻译 API Key。点击「测试翻译」检查系统英中语言包。
3. 若切换到「火山翻译」，填写 **Access Key ID** 和 **Secret Access Key** 并测试翻译。
4. 返回「实时字幕」，点击「开始」。语音会自动分段，显示英文和中文；「停止」结束录音。

密钥保存在本机钥匙串，翻译引擎选择保存在应用偏好设置。Apple 系统翻译使用 macOS Translation framework，需要 macOS 26 或更新版本。安装包 `dist/LiveTranslate-app.zip` 可用于从同步目录导出应用。

## Bob 插件

运行 `./scripts/package.sh`，双击 `dist/LiveTranslate.bobplugin`。Bob 插件提供火山英译中文本服务，AK/SK 在 Bob 服务设置中另行填写。Bob 的默认文本翻译可使用其内置 **System Translate**。Bob 插件 API 不提供麦克风输入；课堂实时语音翻译在上面的独立应用中使用。

## 测试

`./scripts/test-app.sh` 编译应用并运行分段测试；`./scripts/test.sh` 检查 Bob 插件的打包、签名和回调。云端端到端测试需要在应用内填写有效 Deepgram 或火山密钥。
