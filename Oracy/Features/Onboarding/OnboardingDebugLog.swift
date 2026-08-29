import Foundation

enum OnboardingDebugLog {
    private static let path = "/Users/singh.ayush@grofers.com/Developer/personal/OneWord/.cursor/debug-0f5216.log"
    private static let sessionId = "0f5216"

    static func write(
        _ message: String,
        hypothesisId: String,
        location: String,
        data: [String: Any] = [:],
        runId: String = "pre-fix"
    ) {
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "message": message,
            "hypothesisId": hypothesisId,
            "location": location,
            "runId": runId
        ]
        if !data.isEmpty { payload["data"] = data }
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        let entry = line + "\n"
        if FileManager.default.fileExists(atPath: path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            if let bytes = entry.data(using: .utf8) { try? handle.write(contentsOf: bytes) }
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
