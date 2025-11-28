import Foundation
import CoreAudio
import AudioToolbox

enum SystemVolume {
    static func current() -> Double? {
        guard let deviceID = defaultOutputDevice() else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        if status == noErr {
            return Double(volume)
        }
        // Fallback: try left channel scalar volume
        size = UInt32(MemoryLayout<Float32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1 // left channel
        )
        let statusLeft = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard statusLeft == noErr else { return nil }
        return Double(volume)
    }

    static func set(_ value: Double) {
        guard let deviceID = defaultOutputDevice() else { return }
        var volume = Float32(min(max(value, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var setStatus = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volume)
        if setStatus != noErr {
            // Fallback: try left channel scalar volume
            address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1 // left channel
            )
            setStatus = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &volume)
        }
    }

    static func addVolumeChangeListener(_ handler: @escaping (Double) -> Void) -> (() -> Void)? {
        guard let deviceID = defaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let queue = DispatchQueue.main
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, queue) { _, _ in
            if let vol = current() {
                handler(vol)
            }
        }
        if status != noErr {
            // Try fallback channel listener
            address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            )
            let fallbackStatus = AudioObjectAddPropertyListenerBlock(deviceID, &address, queue) { _, _ in
                if let vol = current() {
                    handler(vol)
                }
            }
            guard fallbackStatus == noErr else { return nil }
        }

        return {
            var removalAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &removalAddress, queue, { _, _ in })
        }
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }
}
