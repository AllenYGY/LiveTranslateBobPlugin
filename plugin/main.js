// Volcengine Machine Translation for Bob. Apple System Translate is Bob's built-in service.
var HOST = "translate.volcengineapi.com";
var QUERY = "Action=TranslateText&Version=2020-06-01";

function supportLanguages() {
    return ["en", "zh-Hans"];
}

function signRequest(bodyText, accessKeyID, secretAccessKey, date) {
    var CryptoJS = require("crypto-js");
    var xDate = date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
    var shortDate = xDate.slice(0, 8);
    var scope = shortDate + "/cn-north-1/translate/request";
    var signedHeaders = "content-type;host;x-date";
    var canonicalRequest = [
        "POST", "/", QUERY,
        "content-type:application/json\nhost:" + HOST + "\nx-date:" + xDate + "\n",
        signedHeaders,
        CryptoJS.SHA256(bodyText).toString(CryptoJS.enc.Hex)
    ].join("\n");
    var stringToSign = [
        "HMAC-SHA256", xDate, scope,
        CryptoJS.SHA256(canonicalRequest).toString(CryptoJS.enc.Hex)
    ].join("\n");
    var kDate = CryptoJS.HmacSHA256(shortDate, secretAccessKey);
    var kRegion = CryptoJS.HmacSHA256("cn-north-1", kDate);
    var kService = CryptoJS.HmacSHA256("translate", kRegion);
    var kSigning = CryptoJS.HmacSHA256("request", kService);
    var signature = CryptoJS.HmacSHA256(stringToSign, kSigning).toString(CryptoJS.enc.Hex);
    return {
        "Content-Type": "application/json",
        "Host": HOST,
        "X-Date": xDate,
        "Authorization": "HMAC-SHA256 Credential=" + accessKeyID + "/" + scope + ", SignedHeaders=" + signedHeaders + ", Signature=" + signature
    };
}

function requestTranslation(text, handler) {
    var accessKeyID = String($option.access_key_id || "").trim();
    var secretAccessKey = String($option.secret_access_key || "").trim();
    if (!accessKeyID || !secretAccessKey) {
        handler({ type: "secretKey", message: "请在 Bob 中填写火山翻译 Access Key ID 和 Secret Access Key。" });
        return;
    }
    var bodyText = JSON.stringify({ TargetLanguage: "zh", TextList: [text] });
    var headers = signRequest(bodyText, accessKeyID, secretAccessKey, new Date());
    $http.request({
        method: "POST",
        url: "https://" + HOST + "/?" + QUERY,
        header: headers,
        body: $data.fromUTF8(bodyText),
        timeout: 30,
        handler: function (response) {
            if (response.error) {
                handler({ type: "network", message: "火山翻译请求失败，请检查网络和 Access Key。" });
                return;
            }
            try {
                var data = typeof response.data === "string" ? JSON.parse(response.data) : response.data;
                var item = data && data.TranslationList && data.TranslationList[0];
                var output = item && item.Translation;
                if (!output || !String(output).trim()) {
                    handler({ type: "api", message: "火山翻译未返回译文，请检查密钥和服务权限。" });
                    return;
                }
                handler(null, String(output).trim());
            } catch (_) {
                handler({ type: "api", message: "火山翻译返回了无效数据。" });
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
        query.onCompletion(error ? { error: error } : {
            result: { from: "en", to: "zh-Hans", content: { format: "plain", text: output } }
        });
    });
}

function pluginValidate(completion) {
    requestTranslation("Hello", function (error) {
        completion(error ? { result: false, error: error } : { result: true });
    });
}
