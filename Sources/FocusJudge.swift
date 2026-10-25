import Foundation

enum JudgeError: Error {
    case unauthorized
    case retryLater(TimeInterval, String)
    case failed(String)
}

final class FocusJudge {
    private let apiKey: String
    private let workspaceID: String?
    private let model: String
    private let systemPrompt: String

    init(apiKey: String, workspaceID: String?, model: String, systemPrompt: String) {
        self.apiKey = apiKey
        self.workspaceID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.systemPrompt = systemPrompt
    }

    static func body(for request: JudgeRequest, model: String,
                     systemPrompt: String) -> [String: Any] {
        var lines: [String]
        if request.strict {
            lines = ["Mode: strict. Only the task below counts as work.", "Task: \(request.task)"]
        } else {
            lines = ["Mode: lenient. The task below and any other open task count as work.",
                     "Task: \(request.task)"]
            let others = Array(request.otherTasks.prefix(3))
            if others.isEmpty {
                lines.append("Other open tasks: (none)")
            } else {
                lines.append("Other open tasks:")
                lines.append(contentsOf: others.map { "- \($0)" })
            }
        }
        let context = request.context
        let title = context.windowTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "(none)"
        let url = context.url.flatMap { $0.isEmpty ? nil : $0 } ?? "(none)"
        lines.append(contentsOf: ["App: \(context.appName) (\(context.bundleID))",
                                 "Window title: \(title)",
                                 "URL: \(url)",
                                 "Minutes in this context: \(request.minutesInContext)",
                                 "Reply language: \(L.isRussian ? "Russian" : "English")"])
        return [
            "model": model,
            "max_tokens": 200,
            "system": systemPrompt,
            "messages": [["role": "user", "content": lines.joined(separator: "\n")]],
            "output_config": ["format": ["type": "json_schema", "schema": [
                "type": "object",
                "properties": [
                    "verdict": ["type": "string", "enum": ["on_task", "off_task", "unclear"]],
                    "confidence": ["type": "number"],
                    "line": ["type": "string"],
                ],
                "required": ["verdict", "confidence", "line"],
                "additionalProperties": false,
            ]]],
        ]
    }

    func judge(_ request: JudgeRequest,
               completion: @escaping (Result<(Judgement, Int, Int), JudgeError>) -> Void) {
        let body = Self.body(for: request, model: model, systemPrompt: systemPrompt)
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(.failure(.failed(L.t("неверный запрос", "bad request"))))
            return
        }
        var call = URLRequest(url: url)
        call.httpMethod = "POST"
        call.httpBody = data
        call.timeoutInterval = 20
        call.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let workspaceID, !workspaceID.isEmpty {
            call.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }
        call.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        call.setValue("application/json", forHTTPHeaderField: "content-type")
        URLSession.shared.dataTask(with: call) { data, response, error in
            let result = Self.parse(data: data, response: response, error: error)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private static func parse(data: Data?, response: URLResponse?, error: Error?)
        -> Result<(Judgement, Int, Int), JudgeError> {
        if error != nil { return .failure(.retryLater(60, L.t("нет связи", "no connection"))) }
        guard let response = response as? HTTPURLResponse else {
            return .failure(.retryLater(60, L.t("нет связи", "no connection")))
        }
        switch response.statusCode {
        case 401, 403:
            return .failure(.unauthorized)
        case 429:
            let seconds = TimeInterval(response.value(forHTTPHeaderField: "retry-after") ?? "") ?? 60
            return .failure(.retryLater(max(0, seconds), L.t("лимит запросов, жду минуту", "rate limited, waiting a minute")))
        case 500...599:
            return .failure(.retryLater(60, L.t("нет связи", "no connection")))
        case 400:
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let detail = (json?["error"] as? [String: Any])?["message"] as? String
            return .failure(.failed(detail ?? L.t("неверный запрос", "bad request")))
        case 200:
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.retryLater(60, L.t("нет связи", "no connection")))
            }
            let content = (json["content"] as? [[String: Any]])?.first
            let refusal = json["stop_reason"] as? String == "refusal"
            let text = !refusal && content?["type"] as? String == "text"
                ? content?["text"] as? String ?? "" : ""
            let usage = json["usage"] as? [String: Any]
            return .success((FocusCore.parseJudgement(text),
                             usage?["input_tokens"] as? Int ?? 0,
                             usage?["output_tokens"] as? Int ?? 0))
        default:
            return .failure(.retryLater(60, L.t("нет связи", "no connection")))
        }
    }
}
