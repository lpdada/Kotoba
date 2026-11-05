import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Model

/// An "in this line, the word means …" explanation.
struct WordExplanation: Codable, Hashable {
    var headline: String
    var grammar: String
    var nuance: String
    var source: String
    var createdAt: Date
    var isRemote: Bool

    var combined: String {
        [headline, grammar, nuance]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

protocol ContextExplaining {
    var displayName: String { get }
    func explain(word: String, sentence: String, entry: DictEntry?) async throws -> WordExplanation
}

enum ExplanationError: LocalizedError {
    case notConfigured
    case invalidURL
    case http(status: Int, body: String)
    case emptyResponse
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有填写 AI 服务地址或密钥"
        case .invalidURL: return "AI 服务地址格式不正确"
        case .http(let status, let body):
            let trimmed = body.prefix(180)
            return "服务返回 \(status)：\(trimmed)"
        case .emptyResponse: return "服务没有返回内容"
        case .decoding: return "返回内容无法解析"
        }
    }
}

// MARK: - Offline grammar explainer

/// Produces a real, analysis-based explanation without any network call.
///
/// It re-tokenizes the sentence, finds which slot the tapped word occupies, looks
/// at the particle that follows it, and reports the surface conjugation. The
/// result is genuinely derived from the sentence, not a canned string.
struct LocalContextExplainer: ContextExplaining {
    let tokenizer: Tokenizer
    let dictionary: DictionaryStore

    var displayName: String { "本地语法分析" }

    func explain(word: String, sentence: String, entry: DictEntry?) async throws -> WordExplanation {
        let tokens = tokenizer.tokenize(sentence)
        let targetIndex = tokens.firstIndex { token in
            token.text == word || token.lemma == word || (word.count > 1 && token.text.contains(word))
        }

        var headlineParts: [String] = []
        let meaning = entry?.primaryMeaning ?? ""
        let posLabel = entry?.posLabel ?? ""

        if let entry {
            if !meaning.isEmpty {
                headlineParts.append("在这句里，「\(entry.word)」对应词典释义 “\(meaning)”。")
            } else {
                headlineParts.append("「\(entry.word)」在这句话里作为 \(posLabel.isEmpty ? "词" : posLabel) 出现。")
            }
        } else {
            headlineParts.append("「\(word)」不在内置词表里，通常是人名、专有名词或口语缩略。可以先用 AI 解释补充。")
        }

        guard let targetIndex else {
            return WordExplanation(
                headline: headlineParts.joined(separator: " "),
                grammar: "未能在这句字幕里定位到该词，可能它是更大词组的一部分。",
                nuance: nuance(for: entry),
                source: displayName,
                createdAt: Date(),
                isRemote: false
            )
        }

        let target = tokens[targetIndex]
        var grammarParts: [String] = []

        if let formation = target.formation, let lemma = target.lemma {
            grammarParts.append("原形是「\(lemma)」，这里用了\(formation)。")
        }

        // Which particle follows? That is the strongest signal for the word's role.
        let following = tokens.dropFirst(targetIndex + 1).first { $0.kind == .particle }
        if let particle = following {
            let role = Self.role(forParticle: particle.text)
            grammarParts.append("后面跟着助词「\(particle.text)」，把「\(word)」标记为\(role)。")
        } else if let preceding = tokens[..<targetIndex].last(where: { $0.kind == .particle }) {
            let role = Self.role(forParticle: preceding.text)
            grammarParts.append("它接在助词「\(preceding.text)」之后，和前面的成分构成\(role)关系。")
        }

        let sentenceHasPolite = sentence.contains("です") || sentence.contains("ます") || sentence.contains("ました")
        grammarParts.append(sentenceHasPolite ? "整句是敬体（です・ます），适合对不熟的人说。" : "整句是常体（だ・である），更像朋友之间或内心独白。")

        if let pos = entry?.partsOfSpeech, PartsOfSpeech.isVerb(pos) {
            grammarParts.append("作为动词，注意它和助词的搭配会改变意思，别只记单词本身。")
        }

        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSentence.isEmpty {
            grammarParts.append("整句：「\(trimmedSentence)」")
        }

        return WordExplanation(
            headline: headlineParts.joined(separator: " "),
            grammar: grammarParts.joined(separator: " "),
            nuance: nuance(for: entry),
            source: displayName,
            createdAt: Date(),
            isRemote: false
        )
    }

    private func nuance(for entry: DictEntry?) -> String {
        guard let entry else { return "口语素材里出现的不认识词，建议保存到生词本，复习两三轮后再判断它是否常用。" }
        var parts: [String] = []
        if let level = entry.level {
            parts.append("属于 \(level.label) 范围")
        }
        switch entry.frequencyBand {
        case 1: parts.append("属于最高频词，影视对白里几乎每集都会出现")
        case 2: parts.append("高频词，日常对话出现很多")
        case 3: parts.append("中等频率，出现时值得留意语境")
        default: parts.append("相对低频，先认识、不必强求马上会说")
        }
        if entry.meanings.count > 1 {
            parts.append("它有 \(entry.meanings.count) 个常见义项，具体怎么选要看这一句的语境")
        }
        if entry.examples.first != nil {
            parts.append("词条里附了例句，可以对照语序")
        }
        return parts.joined(separator: "；") + "。"
    }

    static func role(forParticle particle: String) -> String {
        switch particle {
        case "は": return "主题（这句话在谈什么）"
        case "が": return "主语（谁在做/谁是这样）"
        case "を": return "宾语（动作的对象）"
        case "に": return "对象或时间点（动作指向谁、何时）"
        case "で": return "场所或手段（在哪、用什么）"
        case "と": return "并列或引用（和谁、说了什么）"
        case "も": return "追加（也一样）"
        case "の": return "修饰或所属（谁的、什么样的）"
        case "から": return "起点（从…开始）"
        case "まで": return "终点（到…为止）"
        case "より": return "比较（比…）"
        case "へ": return "方向（朝向…）"
        case "や": return "列举（…之类）"
        case "ね": return "确认语气（寻求认同）"
        case "よ": return "提示语气（把信息推给对方）"
        default: return "「\(particle)」所标记的成分"
        }
    }
}

// MARK: - Remote LLM explainer

struct AIConfiguration {
    let baseURL: String
    let model: String
    let apiKey: String

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Talks to any OpenAI-compatible `/chat/completions` endpoint.
struct RemoteLLMExplainer: ContextExplaining {
    let configuration: AIConfiguration
    let language: TranslationLanguage

    var displayName: String { configuration.model }

    func explain(word: String, sentence: String, entry: DictEntry?) async throws -> WordExplanation {
        guard configuration.isConfigured else { throw ExplanationError.notConfigured }
        let trimmedBase = configuration.baseURL.trimmingCharacters(in: .whitespaces)
        guard var components = URLComponents(string: trimmedBase) else { throw ExplanationError.invalidURL }
        if !components.path.hasSuffix("/chat/completions") {
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + components.path + "/chat/completions"
            components.path = components.path.replacingOccurrences(of: "//", with: "/")
        }
        guard let url = components.url else { throw ExplanationError.invalidURL }

        let glosses = entry?.meanings.joined(separator: " / ") ?? ""
        let system = """
        你是一位日语教师，正在陪学生看日本影视片段。学生点了一个词，请只针对这一句字幕解释它。
        \(language.instruction)。
        输出 JSON：{"headline": "一句话说明它在这句里的意思", "grammar": "语法与搭配", "nuance": "语感、使用场合、常见坑"}
        不要输出 JSON 以外的任何字符。三个字段都用 1-3 句自然的话，避免套话。
        """
        let user = """
        字幕：\(sentence)
        被点的词：\(word)
        词典形与释义：\(entry?.word ?? word) \(entry?.reading ?? "") — \(glosses)
        学生水平：\(entry?.level?.label ?? "未知")
        """

        let body: [String: Any] = [
            "model": configuration.model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ExplanationError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExplanationError.emptyResponse
        }

        let parsed = Self.decodePayload(content)
        return WordExplanation(
            headline: parsed.headline,
            grammar: parsed.grammar,
            nuance: parsed.nuance,
            source: configuration.model,
            createdAt: Date(),
            isRemote: true
        )
    }

    private struct Payload {
        let headline: String
        let grammar: String
        let nuance: String
    }

    private static func decodePayload(_ content: String) -> Payload {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start < end,
           let data = String(cleaned[start...end]).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let headline = (object["headline"] as? String) ?? (object["meaning"] as? String) ?? ""
            let grammar = (object["grammar"] as? String) ?? ""
            let nuance = (object["nuance"] as? String) ?? (object["usage"] as? String) ?? ""
            if !headline.isEmpty || !grammar.isEmpty || !nuance.isEmpty {
                return Payload(headline: headline, grammar: grammar, nuance: nuance)
            }
        }
        return Payload(headline: cleaned, grammar: "", nuance: "")
    }
}
