import AudioToolbox
import CoreAudio
import Foundation
import TattleCore

/// Mutes by tapping the target processes with `.muted` behaviour: while the tap
/// is being read, those processes no longer reach the speakers. The tap is read
/// by a private aggregate device with an IOProc that discards the samples.
/// Needs the "System Audio Recording" permission (macOS 14.2+).
public final class CoreAudioProcessMuter: ProcessMuting, @unchecked Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let step: String
        public let status: OSStatus
        public var description: String { "\(step) failed (OSStatus \(status))" }
    }

    private struct Tap {
        var tapID: AudioObjectID
        var aggregateID: AudioObjectID
        var procID: AudioDeviceIOProcID?
    }

    private let lock = NSLock()
    private var taps: [Int32: Tap] = [:]

    public init() {}

    deinit { lock.withLock { taps.keys.forEach { release($0) } } }

    public func mute(ownerPID: Int32, audioPIDs: [Int32]) throws {
        try lock.withLock {
            release(ownerPID)
            let objects = audioPIDs.compactMap(Self.processObject(for:))
            guard !objects.isEmpty else { throw Failure(step: "find audio process", status: kAudioHardwareBadObjectError) }

            let description = CATapDescription(stereoMixdownOfProcesses: objects)
            description.uuid = UUID()
            description.muteBehavior = .muted
            description.isPrivate = true

            var tapID = AudioObjectID(kAudioObjectUnknown)
            var status = AudioHardwareCreateProcessTap(description, &tapID)
            guard status == noErr else { throw Failure(step: "create tap", status: status) }

            let outputUID = try Self.defaultOutputUID()
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Tattle mute \(ownerPID)",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]],
            ]
            var aggregateID = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
            guard status == noErr else {
                AudioHardwareDestroyProcessTap(tapID)
                throw Failure(step: "create aggregate device", status: status)
            }

            var procID: AudioDeviceIOProcID?
            status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, _, _, _, _ in }
            guard status == noErr else {
                AudioHardwareDestroyAggregateDevice(aggregateID)
                AudioHardwareDestroyProcessTap(tapID)
                throw Failure(step: "create IO proc", status: status)
            }

            // AudioDeviceStart can block indefinitely (seen when the process is not
            // allowed to tap). Never block the caller (the UI thread) for long.
            let started = DispatchSemaphore(value: 0)
            let outcome = StartOutcome()
            let tap = Tap(tapID: tapID, aggregateID: aggregateID, procID: procID)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = AudioDeviceStart(tap.aggregateID, tap.procID)
                if outcome.finish(result) { started.signal() } else { Self.destroy(tap) }  // caller gave up: clean up late
            }
            guard started.wait(timeout: .now() + Self.startTimeout) == .success else {
                if outcome.abandon() { throw Failure(step: "start tap (timed out; is Screen & System Audio Recording allowed?)", status: -1) }
                // finished in the gap: fall through and use it
                if outcome.status != noErr { Self.destroy(tap); throw Failure(step: "start tap", status: outcome.status) }
                taps[ownerPID] = tap
                return
            }
            guard outcome.status == noErr else {
                Self.destroy(tap)
                throw Failure(step: "start tap", status: outcome.status)
            }
            taps[ownerPID] = Tap(tapID: tapID, aggregateID: aggregateID, procID: procID)
        }
    }

    public func unmute(ownerPID: Int32) {
        lock.withLock { release(ownerPID) }
    }

    /// Caller holds the lock.
    private func release(_ ownerPID: Int32) {
        guard let tap = taps.removeValue(forKey: ownerPID) else { return }
        Self.destroy(tap)
    }

    private static let startTimeout: DispatchTimeInterval = .seconds(3)

    private static func destroy(_ tap: Tap) {
        AudioDeviceStop(tap.aggregateID, tap.procID)
        if let procID = tap.procID { AudioDeviceDestroyIOProcID(tap.aggregateID, procID) }
        AudioHardwareDestroyAggregateDevice(tap.aggregateID)
        AudioHardwareDestroyProcessTap(tap.tapID)
    }

    /// Hand-off between the start call and the caller that may stop waiting for it.
    private final class StartOutcome: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var abandoned = false
        private(set) var status: OSStatus = noErr

        /// Returns false when the caller already abandoned the wait.
        func finish(_ status: OSStatus) -> Bool {
            lock.withLock { self.status = status; finished = true; return !abandoned }
        }
        /// Returns true when the start had not finished yet (so it must clean up itself).
        func abandon() -> Bool {
            lock.withLock { if finished { return false }; abandoned = true; return true }
        }
    }

    private static func processObject(for pid: Int32) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<Int32>.size), &pid, &size, &object
        )
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw Failure(step: "find output device", status: status) }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw Failure(step: "read output device UID", status: status) }
        return uid.takeRetainedValue() as String
    }
}
