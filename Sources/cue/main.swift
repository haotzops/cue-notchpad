import CueCore
import Darwin
import Foundation

private func stderr(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }
private func readAll(_ fd: Int32) -> Data {
    var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
    while true { let n = Darwin.read(fd, &buffer, buffer.count); if n <= 0 { break }; result.append(buffer, count: n) }
    return result
}
private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { raw in
        guard var base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
        var remaining = raw.count
        while remaining > 0 { let n = Darwin.write(fd, base, remaining); if n <= 0 { return false }; base = base.advanced(by: n); remaining -= n }
        return true
    }
}
private func connectSocket() -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { return nil }
    let bytes = CueIPC.socketPath.utf8CString
    var address = sockaddr_un(); address.sun_len = UInt8(2 + bytes.count); address.sun_family = sa_family_t(AF_UNIX)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
    let addressLength = socklen_t(address.sun_len)
    let result = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, addressLength) } }
    guard result == 0 else { close(fd); return nil }; return fd
}
private func launchHost() {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard app.pathExtension == "app" else { return }
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = ["-a", app.path]
    try? process.run()
}
private func callerName() -> String? {
    var pid = getppid()
    for _ in 0..<8 {
        let p = Process(), pipe = Pipe(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-o", "comm=,ppid=", "-p", String(pid)]; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let fields = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.split(whereSeparator: { $0 == " " || $0 == "\t" }) ?? []
        guard let raw = fields.first else { break }
        let name = URL(fileURLWithPath: String(raw)).lastPathComponent
        if ["pi", "codex", "opencode", "claude", "gemini"].contains(where: { name.lowercased().contains($0) }) { return name.capitalized }
        guard fields.count > 1, let parent = Int32(fields[1]) else { break }; pid = parent
    }
    return nil
}

signal(SIGPIPE, SIG_IGN)
let args: CueArguments
do { args = try CueArguments(arguments: Array(CommandLine.arguments.dropFirst())) }
catch { stderr("usage: cue [--wait] [file]"); exit(EX_USAGE) }
let input: String
do {
    if let path = args.filePath { input = try String(contentsOfFile: path, encoding: .utf8) }
    else if isatty(STDIN_FILENO) == 0 { input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) }
    else { input = "" }
} catch { stderr("cue: cannot read file: \(error)"); exit(EXIT_FAILURE) }
let document: CueDocument = args.filePath.map { .file(path: $0) } ?? .standardInput
let request = CueSessionRequest(initialText: input, document: document, callerPID: getppid(), callerName: callerName(), workingDirectory: FileManager.default.currentDirectoryPath)
var connection = connectSocket()
if connection == nil {
    launchHost()
    for _ in 0..<50 { usleep(100_000); if let fd = connectSocket() { connection = fd; break } }
}
guard let fd = connection else { stderr("cue: unable to start Cue Notchpad"); exit(EXIT_FAILURE) }
guard let payload = try? CueIPC.encode(request) else { stderr("cue: unable to encode edit request"); exit(EXIT_FAILURE) }
guard writeAll(fd, payload) else { stderr("cue: unable to send edit request: \(String(cString: strerror(errno)))"); close(fd); exit(EXIT_FAILURE) }
let responseData = readAll(fd); close(fd)
guard let response = try? JSONDecoder().decode(CueSessionResponse.self, from: responseData) else { stderr("cue: edit session ended unexpectedly"); exit(EXIT_FAILURE) }
switch response {
case .submitted(let text):
    if case .file(let path) = document { do { try text.write(toFile: path, atomically: true, encoding: .utf8) } catch { stderr("cue: cannot write \(path): \(error)"); exit(EXIT_FAILURE) } }
    else { FileHandle.standardOutput.write(Data(text.utf8)) }
    exit(EXIT_SUCCESS)
case .cancelled: exit(130)
case .failed(let message): stderr("cue: \(message)"); exit(EXIT_FAILURE)
}
