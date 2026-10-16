import SwiftUI

struct SettingsView: View {
    @ObservedObject var client: LGTVClient
    @Environment(\.dismiss) private var dismiss
    
    @State private var hostInput: String = ""
    @State private var portInput: String = "8080"
    @State private var pairingKeyInput: String = ""
    @State private var isProcessing: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var showDiscovery: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Network Connection
                Section(header: Text("Conexão com a TV").foregroundColor(Color.cyan)) {
                    HStack {
                        Text("IP da TV")
                            .frame(width: 80, alignment: .leading)
                        TextField("192.168.1.100", text: $hostInput)
                            .keyboardType(.numbersAndPunctuation)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    HStack {
                        Text("Porta")
                            .frame(width: 80, alignment: .leading)
                        TextField("8080", text: $portInput)
                            .keyboardType(.numberPad)
                    }
                    
                    Button(action: { showDiscovery = true }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Buscar TVs na Rede Wi-Fi")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: saveAndTestConnection) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(isProcessing ? "Testando..." : "Salvar e Testar Conexão")
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(isProcessing)
                }
                
                // Section 2: Pairing
                Section(header: Text("Pareamento (Chave de 6 Dígitos)").foregroundColor(Color.cyan),
                        footer: Text("Clique em 'Pedir Código na TV' para exibir os 6 dígitos na tela física do televisor.")) {
                    Button(action: requestPairingCode) {
                        HStack {
                            Image(systemName: "tv")
                            Text(isProcessing ? "Solicitando..." : "Pedir Código na TV")
                        }
                        .foregroundColor(.indigo)
                    }
                    .disabled(isProcessing)
                    
                    HStack {
                        Text("Código")
                            .frame(width: 80, alignment: .leading)
                        TextField("6 dígitos", text: $pairingKeyInput)
                            .keyboardType(.numberPad)
                    }
                    
                    Button(action: confirmPairing) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(isProcessing ? "Confirmando..." : "Confirmar Pareamento")
                        }
                        .foregroundColor(.green)
                    }
                    .disabled(isProcessing || pairingKeyInput.count < 6)
                }
                
                // Section 3: Device Info & Diagnostics
                Section(header: Text("Informações do Aparelho").foregroundColor(Color.cyan)) {
                    HStack {
                        Text("Modelo")
                        Spacer()
                        Text(client.config.model ?? "LG NetCast")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Protocolo")
                        Spacer()
                        Text(client.config.protocolType.uppercased())
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(client.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(client.isConnected ? "Conectado" : "Desconectado")
                                .foregroundColor(client.isConnected ? .green : .red)
                        }
                    }
                    
                    if let session = client.config.session, !session.isEmpty {
                        HStack {
                            Text("Sessão")
                            Spacer()
                            Text(session)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Configurações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .onAppear {
                hostInput = client.config.host
                portInput = String(client.config.port)
                pairingKeyInput = client.config.pairingKey ?? ""
            }
            .sheet(isPresented: $showDiscovery) {
                DiscoveryView(onSelect: { tv in
                    hostInput = tv.ip
                    portInput = String(tv.port)
                    saveSettings()
                    showDiscovery = false
                })
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func saveSettings() {
        let cleanHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(portInput) ?? 8080
        if !cleanHost.isEmpty {
            client.updateHost(cleanHost, port: port)
        }
    }
    
    private func saveAndTestConnection() {
        saveSettings()
        isProcessing = true
        Task {
            await client.refreshStatus()
            isProcessing = false
            alertTitle = client.isConnected ? "Conectado!" : "Falha na Conexão"
            alertMessage = client.isConnected ?
                "Comunicação com a TV em \(client.config.host) estabelecida com sucesso." :
                "Não foi possível contactar a TV em \(client.config.host):\(client.config.port). Verifique se ela está ligada e na mesma rede Wi-Fi."
            showAlert = true
        }
    }
    
    private func requestPairingCode() {
        saveSettings()
        isProcessing = true
        Task {
            let res = await client.requestPairingKeyOnTV()
            isProcessing = false
            alertTitle = res.success ? "Código Solicitado" : "Erro"
            alertMessage = res.message
            showAlert = true
        }
    }
    
    private func confirmPairing() {
        saveSettings()
        isProcessing = true
        Task {
            let res = await client.confirmPairing(key: pairingKeyInput)
            isProcessing = false
            alertTitle = res.success ? "Pareamento Concluído" : "Falha no Pareamento"
            alertMessage = res.message
            showAlert = true
        }
    }
}
