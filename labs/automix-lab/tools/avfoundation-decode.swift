// Decodes an audio file the way AVPlayer does (AVAssetReader: edit list and
// CoreAudio priming applied) to a 16-bit stereo 44.1 kHz WAV, as the reference
// for `automix-lab check-decode`.
//
//   swiftc -O tools/avfoundation-decode.swift -o /tmp/avfoundation-decode
//   /tmp/avfoundation-decode out/cache/<id>.m4a /tmp/ref.wav
//   target/release/automix-lab check-decode out/cache/<id>.m4a /tmp/ref.wav   # lag 0
import AVFoundation

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: avfoundation-decode in out.wav") }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let loaded = DispatchSemaphore(value: 0)
var track: AVAssetTrack?
Task { track = try? await asset.loadTracks(withMediaType: .audio).first; loaded.signal() }
loaded.wait()
guard let track else { fatalError("no audio track") }

let reader = try! AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
])
reader.add(output)
reader.startReading()

var pcm = Data()
while let buffer = output.copyNextSampleBuffer() {
    var length = 0
    var pointer: UnsafeMutablePointer<Int8>?
    let block = CMSampleBufferGetDataBuffer(buffer)!
    CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
    pcm.append(UnsafeBufferPointer(start: pointer, count: length).map { UInt8(bitPattern: $0) }, count: length)
}

var header = Data()
func u32(_ v: UInt32) { var x = v.littleEndian; header.append(Data(bytes: &x, count: 4)) }
func u16(_ v: UInt16) { var x = v.littleEndian; header.append(Data(bytes: &x, count: 2)) }
header.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count)); header.append("WAVEfmt ".data(using: .ascii)!)
u32(16); u16(1); u16(2); u32(44100); u32(44100 * 4); u16(4); u16(16)
header.append("data".data(using: .ascii)!); u32(UInt32(pcm.count))
try! (header + pcm).write(to: URL(fileURLWithPath: args[2]))
print("frames", pcm.count / 4)
