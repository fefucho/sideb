import Foundation

/// A real, loadable, silent (60 s) audio file for tests that need an item AVFoundation will keep as `currentItem`
/// (a queue player drops an item whose file does not exist).
enum TestAudioFixture {
    static let silentWAV: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sideb-test-silence-\(UUID().uuidString).wav")
        let rate = 44_100, samples = rate * 60
        var data = Data()
        func le32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func le16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
        data.append(contentsOf: Array("RIFF".utf8)); le32(36 + samples * 2); data.append(contentsOf: Array("WAVEfmt ".utf8))
        le32(16); le16(1); le16(1); le32(rate); le32(rate * 2); le16(2); le16(16)
        data.append(contentsOf: Array("data".utf8)); le32(samples * 2); data.append(Data(count: samples * 2))
        try? data.write(to: url)
        return url
    }()
}
