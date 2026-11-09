// Runs a command-line tool and waits for it, with a time limit (the updater's hdiutil,
// codesign and ditto).

import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let output: String
    let timedOut: Bool

    var ok: Bool { status == 0 && !timedOut }
}

enum Shell {
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            return CommandResult(status: -1, output: error.localizedDescription, timedOut: false)
        }
        // Read while it runs, so a chatty tool can't fill the pipe and stall.
        var output = Data()
        let reader = DispatchQueue(label: "shell.read")
        let readDone = DispatchSemaphore(value: 0)
        reader.async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        let timedOut = process.isRunning
        if timedOut { process.terminate() }
        process.waitUntilExit()
        _ = readDone.wait(timeout: .now() + 2)
        return CommandResult(status: process.terminationStatus,
                             output: String(data: output, encoding: .utf8) ?? "", timedOut: timedOut)
    }
}
