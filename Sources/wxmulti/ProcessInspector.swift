import Foundation

struct ProcessInspector {
    let runner: ProcessRunner

    func runningProcesses(matching text: String) throws -> [RunningProcess] {
        let result = try runner.run("/bin/ps", ["-axww", "-o", "pid=,command="])
        return Self.processes(fromPSOutput: result.stdout).filter { $0.command.contains(text) }
    }

    func runningProcesses(executablePath: String) throws -> [RunningProcess] {
        Self.processes(withExecutablePath: executablePath, in: try allProcesses())
    }

    func firstPID(for appURL: URL, executableName: String) throws -> Int32? {
        let executablePath = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
            .path
        return try runningProcesses(executablePath: executablePath).first?.pid
    }

    func isRunning(_ pid: Int32) -> Bool {
        let result = try? runner.run("/bin/kill", ["-0", "\(pid)"], allowFailure: true)
        return result?.status == 0
    }

    private func allProcesses() throws -> [RunningProcess] {
        let result = try runner.run("/bin/ps", ["-axww", "-o", "pid=,command="])
        return Self.processes(fromPSOutput: result.stdout)
    }

    static func processes(withExecutablePath executablePath: String, in processes: [RunningProcess]) -> [RunningProcess] {
        processes.filter { process in
            process.command == executablePath || process.command.hasPrefix(executablePath + " ")
        }
    }

    static func processes(fromPSOutput output: String) -> [RunningProcess] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    return nil
                }
                let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                guard let pidPart = parts.first, let pid = Int32(pidPart) else {
                    return nil
                }
                return RunningProcess(pid: pid, command: parts.count > 1 ? String(parts[1]) : "")
            }
    }
}
