import Foundation

struct GeminiInterviewResearchClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func fetchInterviewResearch(
        for application: JobApplication,
        apiKey: String,
        model: String = "gemini-2.5-flash"
    ) async throws -> WebInterviewResearch {
        let groundedResponse = try await requestContent(
            requestBody: GroundedResearchRequest(
                contents: [
                    .init(parts: [.init(text: groundedResearchPrompt(for: application))]),
                ],
                tools: [.init(googleSearch: .init())],
                generationConfig: .init(temperature: 0.2)
            ),
            apiKey: apiKey,
            model: model
        )

        let groundedText = groundedResponse.firstText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let groundedSources = groundedResponse.groundingSources

        guard !groundedText.isEmpty else {
            throw GeminiInterviewResearchError.emptyResponse
        }

        let structuredResponse = try await requestContent(
            requestBody: StructuredResearchRequest(
                contents: [
                    .init(parts: [.init(text: structuredResearchPrompt(
                        for: application,
                        groundedAnswer: groundedText,
                        sources: groundedSources
                    ))]),
                ],
                generationConfig: .init(
                    responseMimeType: "application/json",
                    responseJsonSchema: .interviewResearchSchema,
                    temperature: 0.1
                )
            ),
            apiKey: apiKey,
            model: model
        )

        guard
            let jsonText = structuredResponse.firstText,
            let jsonData = jsonText.data(using: .utf8)
        else {
            throw GeminiInterviewResearchError.emptyStructuredResponse
        }

        let payload = try decoder.decode(InterviewResearchPayload.self, from: jsonData)
        let finalSources = mergeSources(preferred: groundedSources, fallback: payload.sources)

        return WebInterviewResearch(
            summary: payload.summary,
            hiringSignals: payload.hiringSignals.uniqued().prefix(4).map { $0 },
            likelyQuestions: payload.likelyQuestions.uniqued().prefix(6).map { $0 },
            preparationFocus: payload.preparationFocus.uniqued().prefix(4).map { $0 },
            sources: finalSources.prefix(5).map { $0 },
            generatedAt: Date(),
            model: model
        )
    }

    private func requestContent<RequestBody: Encodable>(
        requestBody: RequestBody,
        apiKey: String,
        model: String
    ) async throws -> GenerateContentResponse {
        guard
            let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")
        else {
            throw GeminiInterviewResearchError.invalidRequest
        }

        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components.url else {
            throw GeminiInterviewResearchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiInterviewResearchError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(GeminiErrorEnvelope.self, from: data)
            let message = apiError?.error.message ?? "Gemini returned status \(httpResponse.statusCode)."

            switch httpResponse.statusCode {
            case 400:
                throw GeminiInterviewResearchError.api(message)
            case 401, 403:
                throw GeminiInterviewResearchError.unauthorized(message)
            case 429:
                throw GeminiInterviewResearchError.rateLimited(message: message)
            default:
                throw GeminiInterviewResearchError.api(message)
            }
        }

        do {
            return try decoder.decode(GenerateContentResponse.self, from: data)
        } catch {
            throw GeminiInterviewResearchError.invalidResponse
        }
    }

    private func mergeSources(
        preferred: [InterviewResearchSource],
        fallback: [InterviewResearchSource]
    ) -> [InterviewResearchSource] {
        let preferredValid = preferred.filter { !$0.title.isEmpty && !$0.url.isEmpty }
        if !preferredValid.isEmpty {
            return preferredValid.uniqued(by: \.url)
        }

        return fallback
            .filter { !$0.title.isEmpty && !$0.url.isEmpty }
            .uniqued(by: \.url)
    }

    private func groundedResearchPrompt(for application: JobApplication) -> String {
        """
        Search for public interview feedback and candidate-reported interview experiences for this company and role.

        Company: \(application.companyName)
        Role: \(application.role)
        Candidate notes: \(nonEmpty(application.notes))
        Prior interviewer feedback from the user: \(nonEmpty(application.feedback))
        Location context: \(application.location)
        Priority: \(application.priority)

        Focus on:
        - company-specific interview patterns
        - role-relevant evaluations
        - recurring interview stages
        - repeated question themes
        - evidence from first-hand reports when possible

        Avoid generic interview advice unless the public evidence is thin. Be explicit if the evidence is limited or mixed.
        """
    }

    private func structuredResearchPrompt(
        for application: JobApplication,
        groundedAnswer: String,
        sources: [InterviewResearchSource]
    ) -> String {
        let renderedSources = sources.isEmpty
            ? "No grounded sources were returned."
            : sources.map { "- \($0.title) | \($0.url)" }.joined(separator: "\n")

        return """
        You are formatting grounded interview research into JSON for an iOS app.

        Company: \(application.companyName)
        Role: \(application.role)
        Candidate notes: \(nonEmpty(application.notes))
        Prior interviewer feedback from the user: \(nonEmpty(application.feedback))

        Grounded answer:
        \(groundedAnswer)

        Sources:
        \(renderedSources)

        Produce JSON only.
        Rules:
        - Use only the grounded answer and sources above.
        - If evidence is weak, keep the summary conservative.
        - Keep likely questions specific to the company and role where possible.
        - Include the source list provided above in the output.
        """
    }

    private func nonEmpty(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "None provided." : trimmed
    }
}

enum GeminiInterviewResearchError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case emptyResponse
    case emptyStructuredResponse
    case unauthorized(String)
    case rateLimited(message: String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The Gemini interview research request could not be prepared."
        case .invalidResponse:
            return "Gemini returned a response that CareerFuel could not read."
        case .emptyResponse:
            return "Gemini returned no grounded interview research."
        case .emptyStructuredResponse:
            return "Gemini returned grounded research, but the app could not turn it into structured results."
        case let .unauthorized(message):
            return message
        case let .rateLimited(message):
            return message
        case let .api(message):
            return message
        }
    }
}

private extension GeminiInterviewResearchClient {
    struct GroundedResearchRequest: Encodable {
        let contents: [RequestContent]
        let tools: [GroundingTool]
        let generationConfig: GroundedGenerationConfig
    }

    struct StructuredResearchRequest: Encodable {
        let contents: [RequestContent]
        let generationConfig: StructuredGenerationConfig
    }

    struct RequestContent: Encodable {
        let parts: [RequestPart]
    }

    struct RequestPart: Encodable {
        let text: String
    }

    struct GroundingTool: Encodable {
        let googleSearch: EmptyObject

        enum CodingKeys: String, CodingKey {
            case googleSearch = "google_search"
        }
    }

    struct EmptyObject: Encodable {}

    struct GroundedGenerationConfig: Encodable {
        let temperature: Double
    }

    struct StructuredGenerationConfig: Encodable {
        let responseMimeType: String
        let responseJsonSchema: ObjectSchema
        let temperature: Double
    }

    struct ObjectSchema: Encodable {
        let type = "object"
        let properties: [String: SchemaValue]
        let required: [String]
        let additionalProperties = false

        static let interviewResearchSchema = ObjectSchema(
            properties: [
                "summary": .string(description: "A concise summary of the grounded public interview evidence."),
                "hiringSignals": .array(
                    items: .string(description: "A repeated interview evaluation theme."),
                    description: "Repeated hiring signals from public reports."
                ),
                "likelyQuestions": .array(
                    items: .string(description: "A likely interview question grounded in the evidence."),
                    description: "Likely questions inferred from grounded evidence."
                ),
                "preparationFocus": .array(
                    items: .string(description: "A concrete preparation action."),
                    description: "What the candidate should prepare next."
                ),
                "sources": .array(
                    items: .object(
                        properties: [
                            "title": .string(description: "Source title."),
                            "url": .string(description: "Source URL."),
                        ],
                        required: ["title", "url"],
                        description: "Grounded source links."
                    ),
                    description: "Sources used by the grounded research."
                ),
            ],
            required: [
                "summary",
                "hiringSignals",
                "likelyQuestions",
                "preparationFocus",
                "sources",
            ]
        )
    }

    indirect enum SchemaValue: Encodable {
        case string(description: String)
        case array(items: SchemaValue, description: String)
        case object(properties: [String: SchemaValue], required: [String], description: String)

        func encode(to encoder: Encoder) throws {
            switch self {
            case let .string(description):
                try StringSchema(description: description).encode(to: encoder)
            case let .array(items, description):
                try ArraySchema(items: items, description: description).encode(to: encoder)
            case let .object(properties, required, description):
                var container = encoder.container(keyedBy: DynamicCodingKey.self)
                try container.encode("object", forKey: DynamicCodingKey("type"))
                try container.encode(description, forKey: DynamicCodingKey("description"))
                try container.encode(properties, forKey: DynamicCodingKey("properties"))
                try container.encode(required, forKey: DynamicCodingKey("required"))
                try container.encode(false, forKey: DynamicCodingKey("additionalProperties"))
            }
        }
    }

    struct StringSchema: Encodable {
        let type = "string"
        let description: String
    }

    struct ArraySchema: Encodable {
        let type = "array"
        let items: SchemaValue
        let description: String
    }

    struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(_ stringValue: String) {
            self.stringValue = stringValue
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    struct GenerateContentResponse: Decodable {
        let candidates: [Candidate]?

        var firstText: String? {
            candidates?
                .flatMap { $0.content?.parts ?? [] }
                .compactMap(\.text)
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }

        var groundingSources: [InterviewResearchSource] {
            (candidates ?? [])
                .flatMap { $0.groundingMetadata?.groundingChunks ?? [] }
                .compactMap { chunk in
                    guard
                        let title = chunk.web?.title,
                        let url = chunk.web?.uri,
                        !title.isEmpty,
                        !url.isEmpty
                    else {
                        return nil
                    }

                    return InterviewResearchSource(title: title, url: url)
                }
                .uniqued(by: \.url)
        }
    }

    struct Candidate: Decodable {
        let content: ResponseContent?
        let groundingMetadata: GroundingMetadata?
    }

    struct ResponseContent: Decodable {
        let parts: [ResponsePart]
    }

    struct ResponsePart: Decodable {
        let text: String?
    }

    struct GroundingMetadata: Decodable {
        let groundingChunks: [GroundingChunk]?
    }

    struct GroundingChunk: Decodable {
        let web: GroundingWeb?
    }

    struct GroundingWeb: Decodable {
        let uri: String?
        let title: String?
    }

    struct GeminiErrorEnvelope: Decodable {
        let error: GeminiAPIError
    }

    struct GeminiAPIError: Decodable {
        let code: Int?
        let message: String
        let status: String?
    }

    struct InterviewResearchPayload: Decodable {
        let summary: String
        let hiringSignals: [String]
        let likelyQuestions: [String]
        let preparationFocus: [String]
        let sources: [InterviewResearchSource]
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Array {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()

        return filter { element in
            let value = element[keyPath: keyPath]
            return seen.insert(value).inserted
        }
    }
}
