# Live Translate

独立的 Bob 课堂实时翻译插件及 macOS 麦克风伴随应用，不依赖 OverShelf。

## 使用

1. 运行 `./scripts/test-app.sh` 和 `./scripts/test.sh`，生成 `dist/LiveTranslate.app` 与 `dist/LiveTranslate.bobplugin`。将 app 放在本机可持续运行的位置并打开，双击安装 Bob 插件。重新构建后需要退出旧版 app 再打开新版。
2. 在 **Bob → Services → Text Translate → Live Translate** 填写 **Deepgram API Key**。实时译文默认使用 **Apple System Translate**；如选择 Volcengine，再填写 Access Key ID 和 Secret Access Key。设置只需在 Bob 中完成，伴随应用没有重复的密钥设置页。
3. 在 Bob 翻译弹窗输入 `live`（`/live` 也兼容；Bob 可能去掉斜杠）。授权伴随应用使用麦克风后，会自动弹出**独立课堂字幕窗口**，可拖动、调整大小并浮在课件上方。Bob 卡片也会保留最近两段。伴随应用的主窗口继续显示完整的英文／中文分段记录，方便课后复习；主窗口的「课堂字幕」按钮可重新打开字幕窗。输入 `stop`，或关闭/取消查询可停止录音。

## 课程归档

主窗口的「课程归档」页按**课程 → 课次 → 双语分段**组织结果。可新建课程、重命名课次，并复制一整节课的双语记录。开始录音前，在「实时记录」页选择课程；每次录音会自动新建一节课。已结束课次可以在下次启动应用后继续查看。点击「清空当前显示」不会删除归档。

归档只保存在本机 `~/Library/Application Support/LiveTranslate/archives.json`，不包含 API Key；文件写入采用原子替换和仅当前用户可读的权限。每段最终英文和译文都会及时保存，即使应用意外退出也尽量保留已完成的内容。若归档文件损坏或版本较新，应用不会自动覆盖原文件。

伴随应用在本机 `127.0.0.1:17764` 与 Bob 插件通信，仅用于麦克风启动和字幕传递。密钥由 Bob Services 设置发送到本机伴随应用并保存在 Keychain，不进入 URL 或日志。英语音频由伴随应用直连 Deepgram Nova-3；Apple 翻译需要 macOS 26+ 及英中语言包。选择火山翻译时，伴随应用直连火山云。**Bob 插件 API 不提供麦克风采集和自定义弹窗按钮**，因此必须保持伴随应用运行。

Bob 插件最长可设置 300 秒超时，长课超过此限制时可能需要重新输入 `live`；Bob 版本相关的实际超时行为仍需实机确认。关闭独立字幕窗不会清空主窗口的复习记录。

`plugin/logo.svg` 是透明圆角的矢量 Logo 源文件。`plugin/logo.png` 是从 SVG 导出的 1024×1024 透明 PNG，打包时用于 Bob 插件的 `icon.png` 和 macOS 应用图标。修改 SVG 后可运行 `rsvg-convert -w 1024 -h 1024 plugin/logo.svg -o plugin/logo.png` 更新位图。

## 验证

`./scripts/test.sh` 覆盖插件配置、流式结果和取消回调；`./scripts/test-app.sh` 覆盖自动分段、归档持久化、编译与签名。可用 `curl http://127.0.0.1:17764/snapshot` 检查本机伴随应用。真实麦克风和云端端到端验证需要有效 Deepgram Key 与系统麦克风授权。
