import Foundation

final class WAVWriter: @unchecked Sendable {
    private let outputURL: URL
    private let sampleRate: Double
    private let channels: UInt32
    private var fileHandle: FileHandle?
    private var dataSize: UInt32 = 0

    init(outputURL: URL, sampleRate: Double, channels: UInt32) {
        self.outputURL = outputURL
        self.sampleRate = sampleRate
        self.channels = channels
    }

    func prepareHeader() throws {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: outputURL)
        // Write placeholder WAV header (44 bytes)
        let header = Data(count: 44)
        fileHandle?.write(header)
    }

    func write(samples: [Float]) {
        guard let fh = fileHandle else { return }
        let data = samples.withUnsafeBytes { Data($0) }
        fh.write(data)
        dataSize += UInt32(data.count)
    }

    func finalize() throws {
        guard let fh = fileHandle else { return }

        // Seek to beginning and write proper WAV header
        fh.seek(toFileOffset: 0)

        var header = Data()

        let bytesPerSample: UInt32 = 4 // Float32
        let blockAlign = UInt16(channels * bytesPerSample)
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let fileSize = 36 + dataSize

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(uint32: fileSize)
        header.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(uint32: 16) // chunk size
        header.append(uint16: 3)  // format: IEEE float
        header.append(uint16: UInt16(channels))
        header.append(uint32: UInt32(sampleRate))
        header.append(uint32: byteRate)
        header.append(uint16: blockAlign)
        header.append(uint16: UInt16(bytesPerSample * 8))

        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(uint32: dataSize)

        fh.write(header)
        fh.closeFile()
        fileHandle = nil
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func append(uint32 value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
