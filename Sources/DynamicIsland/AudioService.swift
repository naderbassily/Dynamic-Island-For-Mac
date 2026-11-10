import AppKit
import SwiftUI
import CoreAudio

/// Volume HUD (when the volume or mute changes) and a "microphone in use" indicator.
final class AudioService: ObservableObject {
    static let unknown = AudioObjectID(0)

    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var micInUse = false
    @Published private(set) var outputName = ""

    var onAlert: ((IslandAlert) -> Void)?

    private var device = AudioService.unknown
    private var listenedDevice = AudioService.unknown
    private var lastChange = Date.distantPast
    private var started = Date()
    private var micTimer: Timer?
    private let listenerQueue = DispatchQueue.main
    private lazy var volumeBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.levelChanged() }
    private lazy var deviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachToDefaultDevice() }

    func start() {
        started = Date()
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, listenerQueue, deviceBlock)
        attachToDefaultDevice()
        micTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkMic() }
    }

    // MARK: Output volume

    private func attachToDefaultDevice() {
        if listenedDevice != AudioService.unknown {
            for var a in Self.levelAddresses {
                AudioObjectRemovePropertyListenerBlock(listenedDevice, &a, listenerQueue, volumeBlock)
            }
        }
        device = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        guard device != AudioService.unknown else { return }
        for var a in Self.levelAddresses {
            if AudioObjectHasProperty(device, &a) {
                AudioObjectAddPropertyListenerBlock(device, &a, listenerQueue, volumeBlock)
            }
        }
        listenedDevice = device
        outputName = Self.name(of: device)
        volume = Self.readVolume(device) ?? 0
        muted = Self.readMute(device)
    }

    private func levelChanged() {
        let v = Self.readVolume(device) ?? volume
        let m = Self.readMute(device)
        guard abs(v - volume) > 0.001 || m != muted else { return }
        volume = v
        muted = m
        // Ignore the burst of callbacks right after launch or a device switch.
        guard Date().timeIntervalSince(started) > 2, Prefs.volumeHUD else { return }
        let pct = Int((v * 100).rounded())
        let symbol: String
        if m || v < 0.01 { symbol = "speaker.slash.fill" }
        else if v < 0.34 { symbol = "speaker.wave.1.fill" }
        else if v < 0.67 { symbol = "speaker.wave.2.fill" }
        else { symbol = "speaker.wave.3.fill" }
        onAlert?(IslandAlert(icon: .symbol(symbol, .white), title: outputName.isEmpty ? "Volume" : outputName,
                             message: m ? "Muted" : "\(pct)%", progress: m ? 0 : Double(v), tint: .white,
                             duration: 1.6, sound: nil, kind: "volume", compact: true))
    }

    // MARK: Microphone

    private func checkMic() {
        guard Prefs.micIndicator else {
            if micInUse { micInUse = false }
            return
        }
        let input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var inUse = false
        if input != AudioService.unknown {
            let status = AudioObjectGetPropertyData(input, &addr, 0, nil, &size, &running)
            inUse = status == noErr && running != 0
        }
        if inUse != micInUse { micInUse = inUse }
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static var levelAddresses: [AudioObjectPropertyAddress] {
        [address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput),
         address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: 1),
         address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)]
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var id = AudioService.unknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = address(selector)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func readVolume(_ dev: AudioObjectID) -> Float? {
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            guard AudioObjectHasProperty(dev, &addr) else { continue }
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v) == noErr { return v }
        }
        return nil
    }

    private static func readMute(_ dev: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(dev, &addr) else { return false }
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &m) == noErr && m != 0
    }

    private static func name(of dev: AudioObjectID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, ptr)
        }
        return status == noErr ? name as String : ""
    }
}
