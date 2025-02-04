import ArgumentParser
import Alamofire
import Foundation

@main
struct GippyCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gippy",
        abstract: "Secure, native ChatGPT Terminal Interface with multi-thread support",
        version: "2.1.0",
        subcommands: [
            Configure.self,
            ListThreads.self,
            OpenThread.self,
            Ask.self,
            Prompt.self
        ],
        defaultSubcommand: Ask.self
    )
    
    // MARK: - Subcommand: prompt (Interactive Shell)
    /// Continuously read user input and send it to the active thread (or create one).
    struct Prompt: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: """
            Drop into an interactive shell where each line is sent as a query.
            Type '/exit' or press Ctrl+C to quit.
            """
        )
        
        @Flag(name: .shortAndLong, help: "Enable debug logging.")
        var debug: Bool = false
        
        mutating func run() async throws {
            // 1. Ensure we have an API key
            let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            let configKey = await loadAPIKeyFromConfig()
            guard let apiKey = environmentKey ?? configKey else {
                print("No API key found.")
                print("Please run `gippy configure` or set OPENAI_API_KEY.")
                throw ExitCode.failure
            }
            
            // 2. Load or create a thread
            var thread = loadActiveThread()
            if let existingThread = thread {
                print("Currently active thread: [\(existingThread.id)].")
            } else {
                thread = createNewThread()
                print("No active thread was found; created a new one [\(thread!.id)].")
                saveActiveThreadID(thread!.id)
            }
            guard var currentThread = thread else {
                print("Error: Could not load or create a thread.")
                throw ExitCode.failure
            }
            
            // 3. Enter an input loop
            print("Entering interactive prompt mode. Type '/exit' to quit.")
            while true {
                // Prompt the user
                print("> ", terminator: "")
                guard let userInput = readLine(), !userInput.isEmpty else {
                    continue  // skip if empty
                }
                
                // Check for exit command
                if userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/exit" {
                    print("Exiting prompt mode.")
                    return
                }
                
                // Add user message to thread
                currentThread.messages.append(ChatGPTMessage(role: "user", content: userInput))
                
                // Prepare request
                let requestBody = ChatGPTRequest(
                    model: "gpt-3.5-turbo",
                    messages: currentThread.messages,
                    temperature: 0.7
                )
                
                if debug, let jsonData = try? JSONEncoder().encode(requestBody),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("DEBUG: Request Body:", jsonString)
                }
                
                // Send request
                do {
                    let headers: HTTPHeaders = [
                        "Authorization": "Bearer \(apiKey)",
                        "Content-Type": "application/json"
                    ]
                    
                    let response = try await AF.request(
                        "https://api.openai.com/v1/chat/completions",
                        method: .post,
                        parameters: requestBody,
                        encoder: JSONParameterEncoder.default,
                        headers: headers
                    )
                    .validate()
                    .serializingDecodable(OpenAIResponse.self)
                    .value
                    
                    // Append and print assistant response
                    if let content = response.choices.first?.message.content {
                        print(content)
                        currentThread.messages.append(ChatGPTMessage(role: "assistant", content: content))
                    } else {
                        print("No response content from ChatGPT.")
                    }
                    
                    // Save the updated thread
                    saveThreadToDisk(thread: currentThread)
                    saveActiveThreadID(currentThread.id)
                } catch {
                    print("Error during request: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Subcommand: ask
    /// Ask a single question in the current thread. If no current thread is set, start a new one automatically.
    struct Ask: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: """
            Ask a question in the current chat thread.

            If there's no active thread, a new one is started.
            If there's an active thread, you'll be prompted to continue it or start a new thread.
            """
        )
        
        @Flag(name: .shortAndLong, help: "Enable debug logging.")
        var debug: Bool = false
        
        @Argument(help: "Your query for ChatGPT.")
        var query: String
        
        mutating func run() async throws {
            // 1) Check API key
            let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            let configKey = await loadAPIKeyFromConfig()
            guard let apiKey = environmentKey ?? configKey else {
                print("No API key found.")
                print("Please run `gippy configure` or set OPENAI_API_KEY.")
                throw ExitCode.failure
            }
            
            // (Optional) If you wanted to auto-drop into prompt mode from config:
            let promptModeEnabled = await isPromptModeEnabled()
            if promptModeEnabled {
                print("Prompt mode is enabled in config. Switching to interactive shell...")
                var prompt = Prompt(debug: debug)
                try await prompt.run()
                return
            }
            
            // 2) Determine the active thread or create a new one
            var thread = loadActiveThread()
            
            if let existingThread = thread {
                // There's an active thread. Prompt user to continue or start new.
                print("You have an active thread: [\(existingThread.id)].")
                print("Press ENTER to continue with this thread, or type 'n' for new: ", terminator: "")
                let choice = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                if choice.lowercased() == "n" {
                    // Start new
                    thread = createNewThread()
                    if debug {
                        print("DEBUG: Created new thread: [\(thread!.id)]")
                    }
                } else {
                    // Continue the same thread
                    print("Continuing thread [\(existingThread.id)]...")
                }
            } else {
                // No active thread, create a new one
                thread = createNewThread()
                if debug {
                    print("DEBUG: Created new thread: [\(thread!.id)] (no previous active thread).")
                }
            }
            
            guard var currentThread = thread else {
                print("Error: Could not create or load a thread.")
                throw ExitCode.failure
            }
            
            // 3) Append user message
            currentThread.messages.append(ChatGPTMessage(role: "user", content: query))
            
            // 4) Build request
            let requestBody = ChatGPTRequest(
                model: "gpt-3.5-turbo",
                messages: currentThread.messages,
                temperature: 0.7
            )
            
            if debug {
                print("DEBUG: Using API key: ****\(apiKey.suffix(4))")
                if let jsonData = try? JSONEncoder().encode(requestBody),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("DEBUG: Request Body:", jsonString)
                }
            }
            
            // 5) Make the request
            if !debug {
                print("\nSending your question to ChatGPT, please wait...\n")
            }
            
            do {
                let headers: HTTPHeaders = [
                    "Authorization": "Bearer \(apiKey)",
                    "Content-Type": "application/json"
                ]
                
                let response = try await AF.request(
                    "https://api.openai.com/v1/chat/completions",
                    method: .post,
                    parameters: requestBody,
                    encoder: JSONParameterEncoder.default,
                    headers: headers
                )
                .validate()
                .serializingDecodable(OpenAIResponse.self)
                .value
                
                // 6) Save assistant response
                if let content = response.choices.first?.message.content {
                    print(content)
                    currentThread.messages.append(ChatGPTMessage(role: "assistant", content: content))
                } else {
                    print("No response content from ChatGPT.")
                }
                
                // 7) Persist
                saveThreadToDisk(thread: currentThread)
                saveActiveThreadID(currentThread.id)
                
            } catch {
                print("Error during request: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Subcommand: list
    struct ListThreads: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all existing chat threads."
        )
        
        func run() throws {
            let threads = loadAllThreads()
            if threads.isEmpty {
                print("No chat threads found.")
                return
            }
            print("Existing chat threads:")
            for t in threads {
                print("  - [\(t.id)], \(t.messages.count) message(s)")
            }
            
            if let activeID = loadActiveThreadID() {
                print("\nActive thread: [\(activeID)]")
            }
        }
    }
    
    // MARK: - Subcommand: open
    struct OpenThread: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open a specific chat thread by ID and make it active."
        )
        
        @Argument(help: "The ID of the thread to open.")
        var threadID: String
        
        func run() throws {
            guard let thread = loadThreadFromDisk(id: threadID) else {
                print("No thread found with ID \(threadID).")
                throw ExitCode.failure
            }
            // Mark this thread as active
            saveActiveThreadID(thread.id)
            print("Opened thread [\(thread.id)], \(thread.messages.count) message(s).")
        }
    }
    
    // MARK: - Subcommand: configure
    struct Configure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set up your OpenAI API key or toggle prompt mode via a local config file."
        )
        
        @Flag(help: "Enable or disable interactive prompt mode by default.")
        var promptMode: Bool = false
        
        mutating func run() throws {
            // 1) Request an API key
            print("OpenAI API Key Configuration")
            print("--------------------------------")
            print("Enter your OpenAI API key (sk-...): ", terminator: "")
            
            guard let newKey = readLine(), !newKey.isEmpty else {
                print("No key entered. Aborting.")
                throw ExitCode.failure
            }
            
            do {
                // 2) Save key + optional prompt mode
                let oldConfig = try? loadFullGippyConfig()
                let newConfig = GippyConfig(
                    apiKey: newKey,
                    promptMode: promptMode || (oldConfig?.promptMode ?? false)
                )
                try saveFullGippyConfig(config: newConfig)
                
                print("API key saved successfully!")
                if promptMode {
                    print("Prompt mode is now enabled by default.")
                }
                print("You can now run `gippy ask <query>` or `gippy prompt`.")
                
            } catch {
                print("Failed to save API key:", error.localizedDescription)
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Thread Management

/// Represents a single ChatGPT thread with an ID and an array of messages.
struct GippyThread: Codable {
    let id: String
    var messages: [ChatGPTMessage]
}

/// Creates a new thread with a unique ID (e.g., UUID).
func createNewThread() -> GippyThread {
    let newID = UUID().uuidString
    return GippyThread(id: newID, messages: [])
}

/// Saves a thread to ~/.gippy/threads/<threadID>.json
func saveThreadToDisk(thread: GippyThread) {
    do {
        let data = try JSONEncoder().encode(thread)
        let fileURL = gippyThreadsDir().appendingPathComponent("\(thread.id).json")
        if !FileManager.default.fileExists(atPath: gippyThreadsDir().path) {
            try FileManager.default.createDirectory(at: gippyThreadsDir(), withIntermediateDirectories: true)
        }
        try data.write(to: fileURL, options: [.atomicWrite])
    } catch {
        print("Failed to save thread: \(error.localizedDescription)")
    }
}

/// Loads a thread from disk.
func loadThreadFromDisk(id: String) -> GippyThread? {
    let fileURL = gippyThreadsDir().appendingPathComponent("\(id).json")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    do {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(GippyThread.self, from: data)
    } catch {
        print("Failed to load thread [\(id)]: \(error.localizedDescription)")
        return nil
    }
}

/// Loads all threads from the ~/.gippy/threads directory.
func loadAllThreads() -> [GippyThread] {
    var results = [GippyThread]()
    let dir = gippyThreadsDir()
    
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
    do {
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        for file in files where file.hasSuffix(".json") {
            let threadID = file.replacingOccurrences(of: ".json", with: "")
            if let thread = loadThreadFromDisk(id: threadID) {
                results.append(thread)
            }
        }
    } catch {
        print("Failed to list threads: \(error.localizedDescription)")
    }
    return results
}

// MARK: - Active Thread

/// We store the active thread ID in ~/.gippy/activeThread.txt
func loadActiveThreadID() -> String? {
    let fileURL = gippyConfigPath().deletingLastPathComponent().appendingPathComponent("activeThread.txt")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    do {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    } catch {
        return nil
    }
}

func saveActiveThreadID(_ id: String) {
    let fileURL = gippyConfigPath().deletingLastPathComponent().appendingPathComponent("activeThread.txt")
    do {
        if !FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path) {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try id.write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
        print("Failed to set active thread ID:", error.localizedDescription)
    }
}

/// Loads the active thread object from disk (if any).
func loadActiveThread() -> GippyThread? {
    guard let activeID = loadActiveThreadID() else { return nil }
    return loadThreadFromDisk(id: activeID)
}

// MARK: - Config File for API Key + Optional Prompt Mode

// Update your config struct to include a `promptMode` field
struct GippyConfig: Codable {
    let apiKey: String
    var promptMode: Bool  // new: default false unless user toggles
}

/// The legacy method used to load only the API key.
//  We'll keep it around for backward compatibility.
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
        return nil
    }
}

/// The new method for reading the *full* config object (API key + promptMode).
func loadFullGippyConfig() throws -> GippyConfig {
    let configPath = gippyConfigPath()
    let data = try Data(contentsOf: configPath)
    return try JSONDecoder().decode(GippyConfig.self, from: data)
}

func saveFullGippyConfig(config: GippyConfig) throws {
    let configDir = gippyConfigPath().deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: configDir.path) {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    }
    
    let data = try JSONEncoder().encode(config)
    try data.write(to: gippyConfigPath(), options: [.atomicWrite])
}

func gippyConfigPath() -> URL {
    // Example: ~/.gippy/config.json
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".gippy").appendingPathComponent("config.json")
}

func gippyThreadsDir() -> URL {
    // ~/.gippy/threads
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".gippy").appendingPathComponent("threads")
}

// If you want to conditionally enable prompt mode automatically:
func isPromptModeEnabled() async -> Bool {
    guard let data = try? Data(contentsOf: gippyConfigPath()) else { return false }
    do {
        let config = try JSONDecoder().decode(GippyConfig.self, from: data)
        return config.promptMode
    } catch {
        return false
    }
}

// MARK: - Models for Requests
struct ChatGPTRequest: Encodable {
    let model: String
    let messages: [ChatGPTMessage]
    let temperature: Double
}

struct ChatGPTMessage: Codable {
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
