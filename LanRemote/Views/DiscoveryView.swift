import SwiftUI

struct DiscoveryView: View {
    @StateObject private var discovery = NetworkDiscovery()
    @Environment(\.dismiss) private var dismiss
    
    let onSelect: (DiscoveredTV) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Header status
                VStack(spacing: 8) {
                    HStack {
                        if discovery.isScanning {
                            ProgressView()
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "tv.badge.wifi")
                                .foregroundColor(.blue)
                        }
                        Text(discovery.statusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if discovery.isScanning {
                        ProgressView(value: discovery.scanProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 10)
                
                // Discovered Devices List
                List {
                    if discovery.discoveredDevices.isEmpty && !discovery.isScanning {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "tv.slash")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("Nenhuma TV LG encontrada")
                                    .font(.headline)
                                Text("Verifique se a TV está ligada e conectada na mesma rede Wi-Fi que o seu iPhone.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    } else {
                        Section(header: Text("Aparelhos Encontrados")) {
                            ForEach(discovery.discoveredDevices) { tv in
                                Button(action: {
                                    HapticManager.shared.success()
                                    onSelect(tv)
                                }) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "tv.fill")
                                            .font(.title2)
                                            .foregroundColor(.cyan)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tv.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text("\(tv.ip):\(tv.port) • \(tv.model)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Buscar TV LG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        discovery.stopScan()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        if discovery.isScanning {
                            discovery.stopScan()
                        } else {
                            discovery.startScan()
                        }
                    }) {
                        Text(discovery.isScanning ? "Parar" : "Escanear")
                    }
                }
            }
            .onAppear {
                discovery.startScan()
            }
            .onDisappear {
                discovery.stopScan()
            }
        }
    }
}
