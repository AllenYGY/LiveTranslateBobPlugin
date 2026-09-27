// Standalone Bob text translation service. Bob stores the key and calls the cloud API directly.
function supportLanguages() {
    return ["en", "zh-Hans"];
}

function configuration() {
    var key = String($option.api_key || "").trim();
    var baseURL = String($option.base_url || "https://api.deepseek.com/v1").trim().replace(/\/+$/, "");
    var model = String($option.model || "deepseek-chat").trim();
    if (!key) return { error: { type: "secretKey", message: "请在 Bob 的插件设置中填写 API Key。" } };
    if (!/^https:\/\//i.test(baseURL) || !model) {
        return { error: { type: "param", message: "请检查 API URL 和 Model。" } };
    }
    return {
        key: key,
        url: /\/chat\/completions$/i.test(baseURL) ? baseURL : baseURL + "/chat/completions",
        model: model
    };
}

function requestTranslation(text, handler) {
    var config = configuration();
    if (config.error) { handler(config.error); return; }
    $http.request({
        method: "POST",
        url: config.url,
        header: {
            "Content-Type": "application/json",
            "Authorization": "Bearer " + config.key
        },
        body: {
            model: config.model,
            stream: false,
            temperature: 0.2,
            messages: [
                { role: "system", content: "Translate the user's English text into Simplified Chinese. Output only the translation. Preserve names, numbers, and paragraph breaks." },
                { role: "user", content: text }
            ]
        },
        timeout: 30,
        handler: function (response) {
            if (response.error) {
                handler({ type: "network", message: "云服务请求失败，请检查 API Key、网络和服务配置。" });
                return;
            }
            try {
                var data = typeof response.data === "string" ? JSON.parse(response.data) : response.data;
                var output = data && data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content;
                if (!output || !String(output).trim()) {
                    handler({ type: "api", message: "云服务未返回译文，请检查 API Key 和 Model。" });
                    return;
                }
                handler(null, String(output).trim());
            } catch (_) {
                handler({ type: "api", message: "云服务返回了无效数据。" });
            }
        }
    });
}

function translate(query, completion) {
    var text = String(query.text || "").trim();
    if (!text || text.length > 10000) {
        query.onCompletion({ error: { type: "param", message: "请输入 1–10000 字符的英文文本。" } });
        return;
    }
    if (query.detectFrom && query.detectFrom !== "en") {
        query.onCompletion({ error: { type: "unsupportedLanguage", message: "仅支持英文翻译成中文。" } });
        return;
    }
    requestTranslation(text, function (error, output) {
        if (error) { query.onCompletion({ error: error }); return; }
        query.onCompletion({ result: {
            from: "en", to: "zh-Hans",
            content: { format: "plain", text: output }
        } });
    });
}

function pluginValidate(completion) {
    requestTranslation("Hello", function (error) {
        completion(error ? { result: false, error: error } : { result: true });
    });
}
