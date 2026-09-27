import CryptoKit
import Foundation

/// 火山引擎 API 签名 V4（HMAC-SHA256 四级派生密钥，结构同 AWS SigV4）。
/// 参考 MailTranslator（Easydict 设计，独立实现）。文档：https://www.volcengine.com/docs/6369/67269
enum VolcengineSigner {
    struct SignedHeaders {
        let host: String
        let xDate: String
        let contentType: String
        let authorization: String

        var dictionary: [String: String] {
            [
                "Content-Type": contentType,
                "Host": host,
                "X-Date": xDate,
                "Authorization": authorization,
            ]
        }
    }

    static func sign(
        accessKeyID: String,
        secretAccessKey: String,
        host: String,
        uri: String,
        queryString: String,
        region: String,
        service: String,
        body: Data,
        date: Date = Date()
    ) -> SignedHeaders {
        let algorithm = "HMAC-SHA256"
        let xDate = Self.xDateString(from: date)
        let shortDate = String(xDate.prefix(8))

        let contentHash = sha256Hex(body)
        let canonicalHeaders = "content-type:application/json\nhost:\(host)\nx-date:\(xDate)\n"
        let signedHeaders = "content-type;host;x-date"
        let canonicalRequest = [
            "POST",
            uri,
            queryString,
            canonicalHeaders,
            signedHeaders,
            contentHash,
        ].joined(separator: "\n")

        let credentialScope = [shortDate, region, service, "request"].joined(separator: "/")
        let stringToSign = [
            algorithm,
            xDate,
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let kDate = hmacSHA256(key: Data(secretAccessKey.utf8), data: shortDate)
        let kRegion = hmacSHA256(key: kDate, data: region)
        let kService = hmacSHA256(key: kRegion, data: service)
        let kSigning = hmacSHA256(key: kService, data: "request")
        let signature = hexString(hmacSHA256(key: kSigning, data: stringToSign))

        let authorization =
            "\(algorithm) Credential=\(accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return SignedHeaders(
            host: host,
            xDate: xDate,
            contentType: "application/json",
            authorization: authorization
        )
    }

    static func xDateString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        hexString(Data(SHA256.hash(data: data)))
    }

    private static func hmacSHA256(key: Data, data: String) -> Data {
        let authentication = HMAC<SHA256>.authenticationCode(
            for: Data(data.utf8),
            using: SymmetricKey(data: key)
        )
        return Data(authentication)
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
