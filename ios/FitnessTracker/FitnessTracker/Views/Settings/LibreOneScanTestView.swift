import SwiftUI

struct LibreOneScanTestView: View {
    @StateObject private var reader = LibreOneNFCReader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Libre 1 · NFC test", systemImage: "wave.3.right")
                        .font(.headline)
                    Text("This reads the sensor directly with your iPhone. It only reads data; it does not start, change, or write to the sensor.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .appCard()

                Button {
                    reader.scan()
                } label: {
                    Label(reader.isScanning ? "Scanning…" : "Scan Libre Sensor", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.appPrimary)
                .disabled(reader.isScanning)

                if let error = reader.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.error)
                        .padding(16)
                        .appCard()
                }

                if let result = reader.result {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Sensor read successfully", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(AppColor.success)

                        LabeledContent("Sensor age", value: ageText(result.sensorAgeMinutes))
                        LabeledContent("Latest raw trend value", value: String(result.latestRawTrend))
                        LabeledContent("Trend points read", value: "\(result.rawTrendValues.count) of 16")
                        LabeledContent("Scanned", value: result.readAt.formatted(date: .omitted, time: .shortened))

                        Text("Raw trend values are sensor data, not a glucose reading in mmol/L. We’ll validate the Libre 1 decoding against this sensor before showing glucose values.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .appCard()
                }

                Text("Use Ultrahuman as your monitor while we validate this test. This screen does not provide glucose readings or alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .appScreen()
        .navigationTitle("Libre 1 Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ageText(_ minutes: Int) -> String {
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h \(minutes % 60)m"
    }
}
