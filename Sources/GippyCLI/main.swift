import ArgumentParser
import Alamofire
import Foundation

@main
struct GippyCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gippy",
        abstract: "Secure, native ChatGPT Terminal Interface",
        version: "1.0.0",
        subcommands: [
            Configure.self,
            Run.self
        ],
        defaultSubcommand: Run.self
    )
    
    // MARK: - Subcommand: Run
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: nil,
            abstract: "Send a query to ChatGPT (default command)."
        )
        
        @Flag(name: .shortAndLong, help: "Enable debug logging.")
        var debug: Bool = false
        
        @Argument(help: "Your query for ChatGPT")
        var query: String
        
        mutating func run() async throws {
            // 1) Check environment variable
            let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            
            // 2) If environment variable is nil, try the config file
            let configKey = await loadAPIKeyFromConfig()
            
            guard let apiKey = environmentKey ?? configKey else {
                print("No API key found.")
                print("Please run `gippy configure` to set up your OpenAI API key, or set OPENAI_API_KEY.")
                throw ExitCode.failure
            }
            
            if debug {
                print("DEBUG: Using API key: ****\(apiKey.suffix(4))")
            }
            
            let headers: HTTPHeaders = [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ]
            
            // Build request body
            let requestBody = ChatGPTRequest(
                model: "gpt-3.5-turbo",
                messages: [ChatGPTMessage(role: "user", content: query)],
                temperature: 0.7
            )
            
            if debug, let jsonData = try? JSONEncoder().encode(requestBody),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("DEBUG: Request Body:", jsonString)
            }
            
            do {
                let openAIResponse = try await AF.request(
                    "https://api.openai.com/v1/chat/completions",
                    method: .post,
                    parameters: requestBody,
                    encoder: JSONParameterEncoder.default,
                    headers: headers
                )
                .validate()
                .serializingDecodable(OpenAIResponse.self)
                .value
                
                if debug {
                    print("DEBUG: Received response with \(openAIResponse.choices.count) choice(s).")
                }
                
                if let content = openAIResponse.choices.first?.message.content {
                    print(content)
                } else {
                    print("No response content available.")
                }
            } catch {
                print("Error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Subcommand: Configure
    struct Configure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set up your OpenAI API key via a local config file."
        )
        
        mutating func run() throws {
            print("OpenAI API Key Configuration")
            print("--------------------------------")
            print("Enter your OpenAI API key (sk-...): ", terminator: "")
            
            guard let newKey = readLine(), !newKey.isEmpty else {
                print("No key entered. Aborting.")
                throw ExitCode.failure
            }
            
            do {
                try saveAPIKeyToConfig(key: newKey)
                print("API key saved successfully!")
                print("You can now run `gippy <query>`.")
            } catch {
                print("Failed to save API key:", error.localizedDescription)
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Helper: Load & Save API Key to Config File
func loadAPIKeyFromConfig() async -> String? {
    let configPath = gippyConfigPath()
    guard FileManager.default.fileExists(atPath: configPath.path) else {
        return nil
    }
    
    do {
        let data = try Data(contentsOf: configPath)
        let config = try JSONDecoder().decode(GippyConfig.self, from: data)
        return config.apiKey
    } catch {
        // If there's an error reading/decoding, just return nil
        return nil
    }
}

func saveAPIKeyToConfig(key: String) throws {
    let configDir = gippyConfigPath().deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: configDir.path) {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    let config = GippyConfig(apiKey: key)
    let data = try JSONEncoder().encode(config)
    try data.write(to: gippyConfigPath(), options: [.atomicWrite])
}

func gippyConfigPath() -> URL {
    // Example: ~/.gippy/config.json
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".gippy").appendingPathComponent("config.json")
}

// MARK: - GippyConfig Model
struct GippyConfig: Codable {
    let apiKey: String
}

// MARK: - Request & Response Models
struct ChatGPTRequest: Encodable {
    let model: String
    let messages: [ChatGPTMessage]
    let temperature: Double
}

struct ChatGPTMessage: Encodable {
    let role: String
    let content: String
}

struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
