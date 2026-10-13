import Darwin
import TattleCore

public struct SysctlProcessInspector: ProcessInspecting {
    public init() {}

    public func snapshot(of pid: Int32) -> ProcessSnapshot? {
        guard let parent = parentPID(of: pid) else { return nil }
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0 ? Self.string(from: pathBuffer) : ""
        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let name = Self.string(from: nameBuffer)
        return ProcessSnapshot(
            pid: pid,
            parentPID: parent,
            name: name.isEmpty ? (path.split(separator: "/").last.map(String.init) ?? "pid \(pid)") : name,
            executablePath: path,
            arguments: arguments(of: pid),
            responsiblePID: Self.responsiblePID(of: pid)
        )
    }

    private typealias ResponsibilityFn = @convention(c) (pid_t) -> pid_t
    /// `responsibility_get_pid_responsible_for_pid` is exported by libSystem but undeclared in
    /// any public header, so look it up at run time; nil when it is missing.
    private static let responsibility: ResponsibilityFn? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }  // RTLD_DEFAULT
        return unsafeBitCast(symbol, to: ResponsibilityFn.self)
    }()

    private static func responsiblePID(of pid: Int32) -> Int32? {
        guard let responsibility else { return nil }
        let result = responsibility(pid)
        return result > 0 && result != pid ? result : nil
    }

    private static func string(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func parentPID(of pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// KERN_PROCARGS2 layout: int32 argc, exec path, NUL padding, then argc NUL-separated args.
    private func arguments(of pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return [] }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }  // exec path
        while index < size, buffer[index] == 0 { index += 1 }  // padding
        var result: [String] = []
        while result.count < Int(argc), index < size {
            var end = index
            while end < size, buffer[end] != 0 { end += 1 }
            result.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return result
    }
}
