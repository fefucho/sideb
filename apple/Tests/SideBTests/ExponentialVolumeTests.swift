import Foundation
import Testing
@testable import SideB

@MainActor
@Suite("Volumen exponencial opcional")
struct ExponentialVolumeTests {
    @Test("La curva conserva 0 y 1, atenúa hasta 30 dB y es monótona; desactivada es lineal")
    func curve() {
        #expect(AudioPlayerService.outputVolume(forSlider: 0, exponential: true) == 0)
        #expect(AudioPlayerService.outputVolume(forSlider: 1, exponential: true) == 1)
        #expect(AudioPlayerService.outputVolume(forSlider: 0.5, exponential: false) == 0.5)
        // 50 %: extra -15 dB => 0.5 * 10^(-15/20)
        let half = AudioPlayerService.outputVolume(forSlider: 0.5, exponential: true)
        #expect(abs(half - 0.5 * Float(pow(10.0, -15.0 / 20.0))) < 1e-6)
        var previous: Float = 0
        for step in 1...100 {
            let value = AudioPlayerService.outputVolume(forSlider: Float(step) / 100, exponential: true)
            #expect(value > previous)
            #expect(value <= Float(step) / 100)
            previous = value
        }
    }

    @Test("La opción se persiste, está apagada por defecto y no altera el valor del deslizador")
    func preference() {
        let defaults = UserDefaults(suiteName: "ExponentialVolume.\(UUID())")!
        let audio = AudioPlayerService(preferences: defaults, preferencePrefix: "test")
        #expect(audio.exponentialVolume == false)
        audio.volume = 0.5
        audio.exponentialVolume = true
        #expect(audio.volume == 0.5)
        #expect(audio.avPlayer.volume == AudioPlayerService.outputVolume(forSlider: 0.5, exponential: true))
        let reloaded = AudioPlayerService(preferences: defaults, preferencePrefix: "test")
        #expect(reloaded.exponentialVolume)
        #expect(reloaded.volume == 0.5)
        #expect(reloaded.avPlayer.volume == audio.avPlayer.volume)
        audio.exponentialVolume = false
        #expect(audio.avPlayer.volume == 0.5)
        audio.volume = 0
        #expect(audio.avPlayer.volume == 0)
    }
}
