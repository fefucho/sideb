import Foundation
import AVFoundation
import CoreAudio

// PLAN-024: lo que el empalme necesita saber del sistema de audio y de sus propios reproductores.

// MARK: - Dispositivo de salida

/// Dispositivo de salida predeterminado del sistema (nombre, uid y tipo de transporte). Sirve para decidir cómo se
/// arranca el segundo reproductor: la sincronización por hora de host (`setRate(_:time:atHostTime:)`) sólo se usa con la
/// salida integrada; con un dispositivo virtual (eqMac, Loopback…), USB, Bluetooth o agregado se arranca con `play()`.
struct AudioOutputDevice: Equatable, Sendable {
    var name: String
    var uid: String
    var transportType: UInt32

    var isBuiltIn: Bool { Self.isBuiltIn(transportType: transportType) }

    static func isBuiltIn(transportType: UInt32) -> Bool { transportType == kAudioDeviceTransportTypeBuiltIn }

    var transportName: String { Self.transportName(transportType) }

    static func transportName(_ type: UInt32) -> String {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: "integrada"
        case kAudioDeviceTransportTypeUSB: "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "Bluetooth"
        case kAudioDeviceTransportTypeAggregate: "agregado"
        case kAudioDeviceTransportTypeVirtual: "virtual"
        case kAudioDeviceTransportTypeAirPlay: "AirPlay"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "HDMI/DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: "Thunderbolt"
        case kAudioDeviceTransportTypePCI: "PCI"
        case kAudioDeviceTransportTypeUnknown: "desconocido"
        default: "otro (\(type))"
        }
    }

    var summary: String { "«\(name)» (uid \(uid), transporte \(transportName))" }

    /// Lee el dispositivo de salida predeterminado; nil si el sistema no lo da.
    static func current() -> AudioOutputDevice? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }
        func string(_ selector: AudioObjectPropertySelector) -> String {
            var value: Unmanaged<CFString>?
            var length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(deviceID, &property, 0, nil, &length, &value) == noErr, let value else { return "?" }
            return value.takeRetainedValue() as String
        }
        var transport: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transport)
        return AudioOutputDevice(name: string(kAudioObjectPropertyName), uid: string(kAudioDevicePropertyDeviceUID), transportType: transport)
    }
}

/// Cómo arranca el segundo reproductor en el instante del empalme.
enum AudioSpliceStartMode: String, Equatable, Sendable {
    /// `setRate(_:time:atHostTime:)`: arranque exacto a una hora del reloj de host (sólo con la salida integrada).
    case hostSynced
    /// `play()` a la hora del fundido (dispositivos virtuales, USB, Bluetooth…, o si el arranque sincronizado falló).
    case plain

    /// Interruptor de seguridad: con `true`, cualquier salida que no sea la integrada (virtual, USB, Bluetooth, agregada) arranca
    /// con `play()` en vez de `setRate(_:time:atHostTime:)`. Está apagado porque, medido contra eqMac (salida virtual), el
    /// arranque sincronizado queda a < 1 ms y no cuelga el dispositivo en 70 ciclos de estrés, mientras que el `play()`
    /// mudo alineado por saltos queda a 60–100 ms. Se enciende con `defaults write … sideb.automix.plainStartOnExternalOutput`.
    nonisolated(unsafe) static var preferPlainOnNonBuiltIn = UserDefaults.standard.bool(forKey: "sideb.automix.plainStartOnExternalOutput")

    /// El arranque sincronizado se verifica siempre (¿avanzó el archivo al terminar el fundido?) y, si no avanzó, se repite
    /// con `play()` (`forcePlain`).
    static func choose(device: AudioOutputDevice?, forcePlain: Bool, preferPlainOnNonBuiltIn: Bool = AudioSpliceStartMode.preferPlainOnNonBuiltIn) -> AudioSpliceStartMode {
        if forcePlain { return .plain }
        if preferPlainOnNonBuiltIn, device?.isBuiltIn != true { return .plain }
        return .hostSynced
    }
}

// MARK: - Reproductores vivos

/// Cuenta los `AVPlayer` que crea Side B (el del servicio y los del empalme) para el diagnóstico y para no acumular más
/// de dos a la vez: cada uno con un elemento cargado es un cliente del dispositivo de salida.
enum AutomixPlayerCounter {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var aliveCount = 0
    nonisolated(unsafe) private static var peakCount = 0
    nonisolated(unsafe) private static var createdCount = 0

    struct Snapshot: Equatable, Sendable { var alive: Int; var peak: Int; var created: Int }

    static var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(alive: aliveCount, peak: peakCount, created: createdCount)
    }

    fileprivate static func born() {
        lock.lock(); defer { lock.unlock() }
        aliveCount += 1; createdCount += 1; peakCount = max(peakCount, aliveCount)
    }

    fileprivate static func died() {
        lock.lock(); defer { lock.unlock() }
        aliveCount -= 1
    }
}

/// `AVPlayer` que se cuenta a sí mismo.
final class CountedPlayer: AVPlayer, @unchecked Sendable {
    override init() {
        super.init()
        AutomixPlayerCounter.born()
    }

    deinit { AutomixPlayerCounter.died() }
}

// MARK: - Fin de pista sospechoso

/// Frena el avance automático cuando las pistas «terminan» nada más empezar (la salida de audio no responde, el
/// reproductor informa tiempos falsos…): con ≥ 2 finales seguidos a menos de 5 s de haber empezado, se detiene.
struct PlaybackFailureGuard: Equatable, Sendable {
    static let shortTrackSeconds: TimeInterval = 5
    static let limit = 2

    private(set) var consecutiveShortEnds = 0

    /// `secondsSinceStart`: lo que sonó la pista según el reloj de pared. Devuelve verdadero si hay que parar.
    mutating func trackEnded(secondsSinceStart: TimeInterval, expectedDuration: Double) -> Bool {
        // Una pista corta de verdad (menos de 8 s) no cuenta como fallo.
        guard expectedDuration > 8 else { consecutiveShortEnds = 0; return false }
        if secondsSinceStart < Self.shortTrackSeconds {
            consecutiveShortEnds += 1
        } else {
            consecutiveShortEnds = 0
        }
        return consecutiveShortEnds >= Self.limit
    }

    /// Una acción del usuario (saltar, elegir otra pista, reanudar) o una pista que sonó normal reinicia la cuenta.
    mutating func reset() { consecutiveShortEnds = 0 }
}
