// Bob owns configuration and renders the live result; the companion captures audio.
var LIVE_URL = "http://127.0.0.1:17764";

function supportLanguages() { return ["en", "zh-Hans"]; }
function pluginTimeoutInterval() { return 300; }

function localRequest(path, body, handler) {
    $http.request({
        method: body === null ? "GET" : "POST",
        url: LIVE_URL + path,
        header: { "Content-Type": "application/json" },
        body: body === null ? undefined : body,
        timeout: 5,
        handler: function (response) {
            if (response.error) { handler({ type: "network", message: "请先打开 LiveTranslate.app，再在 Bob 输入 live。" }); return; }
            var data = response.data;
            if (typeof data === "string") {
                try { data = JSON.parse(data); } catch (_) { data = null; }
            }
            if (!data || data.ok === false) {
                handler({ type: "api", message: (data && data.message) || "实时翻译伴随应用无响应。" });
                return;
            }
            handler(null, data);
        }
    });
}

function render(snapshot) {
    var lines = [];
    var segments = snapshot.segments || [];
    var start = Math.max(0, segments.length - (snapshot.interim ? 1 : 2));
    for (var i = start; i < segments.length; i++) {
        lines.push("> " + escapeMarkdown(segments[i].source) + "\n\n### " + escapeMarkdown(segments[i].translation || "翻译中…"));
    }
    if (snapshot.interim) {
        lines.push("> 🎙 " + escapeMarkdown(snapshot.interim) + "\n\n### " + escapeMarkdown(snapshot.interimTranslation || "识别中…"));
    }
    if (!lines.length) { lines.push("### " + escapeMarkdown(snapshot.status || "正在连接麦克风…")); }
    return lines.join("\n\n---\n\n");
}

function escapeMarkdown(value) {
    return String(value || "").replace(/[\\`*_{}\[\]()#+.!>|-]/g, "\\$&").replace(/\n/g, " ");
}

function translate(query) {
    var command = String(query.text || "").trim().toLowerCase();
    // Bob's word normalization can strip the leading slash from /live and /stop.
    if (command === "/stop" || command === "stop") {
        localRequest("/stop", {}, function (error) {
            query.onCompletion(error ? { error: error } : { result: { from: "en", to: "zh-Hans", content: { format: "plain", text: "实时翻译已停止。" } } });
        });
        return;
    }
    if (command !== "/live" && command !== "live") {
        query.onCompletion({ error: { type: "param", message: "输入 live 开始实时翻译，输入 stop 停止。" } });
        return;
    }
    var key = String($option.deepgram_api_key || "").trim();
    if (!key) {
        query.onCompletion({ error: { type: "secretKey", message: "请在 Bob → Services → Live Translate 填写 Deepgram API Key。" } });
        return;
    }
    var backend = $option.translation_backend === "volcengine" ? "volcengine" : "apple";
    if (backend === "volcengine" && (!$option.access_key_id || !$option.secret_access_key)) {
        query.onCompletion({ error: { type: "secretKey", message: "请在 Bob → Services → Live Translate 填写火山翻译 AK/SK，或切换到 Apple System Translate。" } });
        return;
    }
    var active = true;
    var timerID = null;
    var lastText = "";
    var sessionID = null;
    var inFlight = false;
    var cancelled = false;
    function stopLocal() {
        if (timerID !== null) { $timer.invalidate(timerID); timerID = null; }
        if (sessionID) { localRequest("/stop", { session: sessionID }, function () {}); }
    }
    function finish(error, text) {
        if (!active) { return; }
        active = false;
        stopLocal();
        if (subscription) { subscription.dispose(); }
        if (!cancelled) {
            query.onCompletion(error ? { error: error } : { result: { from: "en", to: "zh-Hans", content: { format: "markdown", text: text || lastText || "实时翻译已停止。" } } });
        }
    }
    var subscription = query.cancelSignal && query.cancelSignal.subscribe(function () {
        cancelled = true;
        finish(null, lastText);
    });
    function poll() {
        if (!active || inFlight) { return; }
        inFlight = true;
        localRequest("/snapshot", null, function (error, snapshot) {
            inFlight = false;
            if (!active) { return; }
            if (error) { finish(error); return; }
            var text = render(snapshot);
            if (text !== lastText) {
                lastText = text;
                query.onStream({ from: "en", to: "zh-Hans", content: { format: "markdown", text: text } });
            }
            if (!snapshot.running && snapshot.status !== "连接 Deepgram…" && snapshot.status !== "准备就绪") {
                finish(null, text);
            }
        });
    }
    localRequest("/start", {
        deepgramKey: key,
        backend: backend,
        accessKeyID: String($option.access_key_id || "").trim(),
        secretAccessKey: String($option.secret_access_key || "").trim()
    }, function (error, data) {
        if (!active) {
            if (data && data.session) { localRequest("/stop", { session: data.session }, function () {}); }
            return;
        }
        if (error) { finish(error); return; }
        sessionID = data.session;
        poll();
        timerID = $timer.schedule({ interval: 0.7, repeats: true, handler: poll });
    });
}

function pluginValidate(completion) {
    if (!$option.deepgram_api_key) {
        completion({ result: false, error: { type: "secretKey", message: "请填写 Deepgram API Key。" } });
        return;
    }
    completion({ result: true });
}
