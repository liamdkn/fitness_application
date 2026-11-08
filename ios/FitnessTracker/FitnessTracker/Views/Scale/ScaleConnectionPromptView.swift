import CoreBluetooth
import SwiftUI

/// A nearby-device sheet shown on entry when the saved kitchen scale is not connected.
struct ScaleConnectionPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scale = BluetoothScale.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: scale.connectedName == nil ? "scalemass" : "checkmark.circle.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(scale.connectedName == nil ? AppColor.accent : AppColor.success)
                    .padding(22)
                    .background(.ultraThinMaterial, in: Circle())

                Text(scale.connectedName.map { "\($0) is connected" } ?? "Connect your kitchen scale")
                    .font(.title3.weight(.semibold))
                Text(scale.connectedName == nil
                     ? "Wake the scale and close its companion app. You can still log food manually."
                     : "Place your bowl on the scale and start weighing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if scale.connectedName == nil {
                    if scale.state != .poweredOn {
                        Label("Turn on Bluetooth to find your scale.", systemImage: "bluetooth")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if scale.found.isEmpty {
                        ProgressView(scale.isScanning ? "Looking nearby…" : "Ready to look nearby")
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(scale.found.sorted { $0.rssi > $1.rssi }) { device in
                                    Button {
                                        scale.connect(device)
                                    } label: {
                                        HStack {
                                            Image(systemName: "scalemass")
                                            Text(device.name)
                                            Spacer()
                                            Text("Connect").font(.subheadline.weight(.semibold))
                                        }
                                        .padding(12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.appSecondary)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
                    }
                }

                HStack(spacing: 12) {
                    if scale.isPaired && scale.connectedName == nil {
                        Button("Reconnect") { scale.reconnectNow() }
                            .buttonStyle(.appSecondary)
                    }
                    if scale.connectedName == nil {
                        Button(scale.isScanning ? "Scan again" : "Find nearby") { scale.startScan() }
                            .buttonStyle(.appPrimary)
                    }
                    Button("Continue without scale") { dismiss() }
                        .buttonStyle(.appSecondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appScreen()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.appToolbarTint()
                }
            }
            .onAppear {
                if scale.isPaired { scale.reconnectKnown() } else { scale.startScan() }
            }
            .onChange(of: scale.connectedName) { _, name in
                if name != nil { dismiss() }
            }
            .onDisappear { scale.stopScan() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
