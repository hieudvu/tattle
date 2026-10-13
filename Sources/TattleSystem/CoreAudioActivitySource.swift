import CoreAudio
import TattleCore

/// Reads which processes are running audio output from the HAL process list
/// (macOS 14.2+). Reading it needs no permission.
public struct CoreAudioActivitySource: AudioActivitySource {
    public struct HALError: Error { public let status: OSStatus }

    public init() {}

    public func outputtingPIDs() throws -> [Int32] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard status == noErr else { throw HALError(status: status) }

        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects)
        guard status == noErr else { throw HALError(status: status) }

        return objects.compactMap { object in
            guard Self.read(UInt32.self, object, kAudioProcessPropertyIsRunningOutput) == 1 else { return nil }
            return Self.read(Int32.self, object, kAudioProcessPropertyPID)
        }
    }

    private static func read<T: FixedWidthInteger>(_: T.Type, _ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
