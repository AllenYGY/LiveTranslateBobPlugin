import CryptoKit
import Foundation
import Translation

protocol LiveTextTranslator {
    func translate(_ text: String) async throws -> String
}

enum TranslationBackend: String, CaseIterable, Identifiable {
    case apple
    case volcengine

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: "Apple System Translate"
        case .volcengine: "火山翻译"
        }
    }
}

struct AppleLiveTranslator: LiveTextTranslator {
    func translate(_ text: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw LiveTranslationError.message("Apple 系统翻译需要 macOS 26 或更新版本")
        }
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
        try await session.prepareTranslation()
        let result = try await session.translate(text)
        let output = result.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw LiveTranslationError.message("Apple 系统翻译返回空结果") }
        return output
    }
}

struct VolcengineLiveTranslator: LiveTextTranslator {
    let accessKeyID: String
    let secretAccessKey: String

    func translate(_ text: String) async throws -> String {
        guard !accessKeyID.isEmpty, !secretAccessKey.isEmpty else {
            throw LiveTranslationError.message("请先填写火山翻译 Access Key ID 和 Secret Access Key")
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "TargetLanguage": "zh",
            "TextList": [text]
        ])
        let host = "translate.volcengineapi.com"
        let query = "Action=TranslateText&Version=2020-06-01"
        let headers = VolcengineSigner.sign(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            host: host,
            uri: "/",
            queryString: query,
            region: "cn-north-1",
            service: "translate",
            body: body
        )
        var request = URLRequest(url: URL(string: "https://\(host)/?\(query)")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        for (name, value) in headers.dictionary where name != "Host" {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LiveTranslationError.message("火山翻译请求失败，请检查密钥和服务权限")
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let translations = payload?["TranslationList"] as? [[String: Any]]
        guard let output = translations?.first?["Translation"] as? String, !output.isEmpty else {
            throw LiveTranslationError.message("火山翻译没有返回译文")
        }
        return output
    }
}

enum LiveTranslationError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}
