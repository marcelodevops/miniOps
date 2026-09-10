import Foundation
import Darwin

public struct ProcessRunResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(status: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public enum ProcessRunner {
    public static func run(
        executable: String,
        arguments: [String],
        currentDirectory: String,
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ProcessRunResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outputGroup = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()

        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            outputGroup.leave()
        }

        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            outputGroup.leave()
        }

        let deadline = Date().addingTimeInterval(max(0, timeout))
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                Thread.sleep(forTimeInterval: 0.1)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        process.waitUntilExit()
        outputGroup.wait()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let timeoutMessage = timedOut ? "Process timed out after \(timeout) seconds" : ""
        let combinedStderr = [stderr.trimmingCharacters(in: .whitespacesAndNewlines), timeoutMessage]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return ProcessRunResult(
            status: process.terminationStatus,
            stdout: stdout,
            stderr: combinedStderr,
            timedOut: timedOut
        )
    }
}
