import CoreNFC
import Combine
import Foundation

struct LibreOneScanResult {
    let sensorAgeMinutes: Int
    let latestRawTrend: Int
    let rawTrendValues: [Int]
    let readAt: Date
}

@MainActor
final class LibreOneNFCReader: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    @Published private(set) var isScanning = false
    @Published private(set) var result: LibreOneScanResult?
    @Published private(set) var errorMessage: String?

    private var session: NFCTagReaderSession?

    func scan() {
        guard NFCReaderSession.readingAvailable else {
            errorMessage = "NFC isn’t enabled in this app build. Xcode reported that your Personal Team can’t use NFC Tag Reading; sign with an Apple Developer Program team and enable that capability to scan the sensor."
            return
        }

        result = nil
        errorMessage = nil
        isScanning = true

        guard let session = NFCTagReaderSession(pollingOption: .iso15693, delegate: self, queue: nil) else {
            isScanning = false
            errorMessage = "NFC scanning couldn’t start on this iPhone."
            return
        }
        session.alertMessage = "Hold the top of your iPhone against the Libre sensor. Keep it still while it reads."
        self.session = session
        session.begin()
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let first = tags.first else { return }
        Task { @MainActor [weak self] in
            await self?.read(first, in: session)
        }
    }

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NFCReaderError.Code.readerSessionInvalidationErrorUserCanceled.rawValue else {
            Task { @MainActor [weak self] in self?.isScanning = false }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isScanning = false
            if self.result == nil, self.errorMessage == nil {
                self.errorMessage = nsError.code == NFCReaderError.Code.readerErrorSecurityViolation.rawValue
                    ? "NFC isn’t enabled for this build. It needs an Apple Developer Program team with Near Field Communication Tag Reading enabled."
                    : error.localizedDescription
            }
        }
    }

    @MainActor
    private func read(_ discoveredTag: NFCTag, in session: NFCTagReaderSession) async {
        guard case .iso15693(let tag) = discoveredTag else {
            let message = "That isn’t a Libre 1 sensor. Try scanning the sensor on your arm."
            errorMessage = message
            session.invalidate(errorMessage: message)
            return
        }

        do {
            try await session.connect(to: discoveredTag)
            var bytes: [UInt8] = []
            // Libre 1 trend and sensor-clock fields fit in the first 43
            // eight-byte blocks. Read-only ISO 15693 command; no writes.
            for firstBlock in stride(from: 0, to: 43, by: 3) {
                let count = min(3, 43 - firstBlock)
                let blocks = try await tag.readMultipleBlocks(
                    requestFlags: [.highDataRate],
                    blockRange: NSRange(location: firstBlock, length: count)
                )
                bytes.append(contentsOf: blocks.flatMap { Array($0) })
            }

            guard bytes.count >= 344 else {
                throw LibreOneReaderError.incompleteRead(bytesRead: bytes.count)
            }
            guard let parsed = Self.parse(bytes, readAt: Date()) else {
                throw LibreOneReaderError.invalidSensorData
            }

            result = parsed
            session.alertMessage = "Libre sensor data read."
            session.invalidate()
        } catch {
            errorMessage = error.localizedDescription
            session.invalidate(errorMessage: error.localizedDescription)
        }
    }

    private static func parse(_ bytes: [UInt8], readAt: Date) -> LibreOneScanResult? {
        guard bytes.count >= 344 else { return nil }
        let pointer = Int(bytes[26])
        guard pointer < 16 else { return nil }

        let sensorAge = Int(bytes[316]) | (Int(bytes[317]) << 8)
        guard sensorAge > 0, sensorAge < 15 * 24 * 60 else { return nil }

        let newestIndex = (pointer + 15) % 16
        let newestOffset = 28 + newestIndex * 6
        let latest = ((Int(bytes[newestOffset + 1]) << 8) | Int(bytes[newestOffset])) & 0x1FFF
        guard latest > 0 else { return nil }

        let values = (0..<16).compactMap { age -> Int? in
            let index = (pointer + 15 - age + 16) % 16
            let offset = 28 + index * 6
            let value = ((Int(bytes[offset + 1]) << 8) | Int(bytes[offset])) & 0x1FFF
            return value == 0 ? nil : value
        }

        return LibreOneScanResult(
            sensorAgeMinutes: sensorAge,
            latestRawTrend: latest,
            rawTrendValues: values,
            readAt: readAt
        )
    }
}

private enum LibreOneReaderError: LocalizedError {
    case incompleteRead(bytesRead: Int)
    case invalidSensorData

    var errorDescription: String? {
        switch self {
        case .incompleteRead(let count):
            return "The sensor read was incomplete (\(count) bytes). Hold the phone still and try again."
        case .invalidSensorData:
            return "The tag was read, but it didn’t contain a ready Libre 1 trend. Check that the sensor has finished warming up, then scan again."
        }
    }
}
