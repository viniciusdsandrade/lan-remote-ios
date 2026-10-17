import SwiftUI

struct SettingsView: View {
    @ObservedObject var client: LGTVClient
    @Environment(\.dismiss) private var dismiss

    @State private var hostInput: String = ""
    @State private var portInput: String = "8080"
    @State private var pairingKeyInput: String = ""
    @State private var boxCodeInput: String = ""
    @State private var boxMACInput: String = ""
    @State private var boxMACInvalid: Bool = false
    @State private var isProcessing: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var showDiscovery: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                boxSection

                // Network Connection
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

                // Pairing
                Section(header: Text("Pareamento com a TV (código de 6 dígitos)").foregroundColor(Color.cyan),
                        footer: Text("Toque em 'Pedir Código na TV' para exibir os 6 dígitos na tela do televisor.")) {
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

                // Device Info & Diagnostics
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
                        Text("Estado")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(stateColor)
                                .frame(width: 8, height: 8)
                            Text(stateText)
                                .foregroundColor(stateColor)
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
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") {
                        saveSettings()
                        client.cancelBoxPairing()
                        dismiss()
                    }
                }
            }
            .onAppear {
                hostInput = client.config.host
                portInput = String(client.config.port)
                pairingKeyInput = client.config.pairingKey ?? ""
                boxMACInput = client.box?.mac ?? ""
                if client.box?.paired != true && client.discoveredBoxes.isEmpty {
                    client.searchBoxes()
                }
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

    // MARK: - Turning the TV on through the TV Box

    private var boxSection: some View {
        Section(header: Text("Ligar a TV pelo app").foregroundColor(Color.cyan), footer: boxFooter) {
            Text("Em standby esta TV desliga a rede, então nenhum comando chega até ela. O app acorda a TV Box ligada no HDMI pelo Wi-Fi e ela liga a TV pelo SIMPLINK (HDMI-CEC). Basta parear uma vez.")
                .font(.footnote)
                .foregroundColor(.secondary)

            if let box = client.box, box.paired {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(box.name)
                            .font(.headline)
                        Text("Pareada · \(box.host)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Text("MAC Wi-Fi")
                        .frame(width: 80, alignment: .leading)
                    TextField(macPlaceholder, text: $boxMACInput)
                        .font(.body.monospaced())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.asciiCapable)
                        .onSubmit(saveBoxMAC)
                        .onChange(of: boxMACInput) { boxMACInvalid = false }
                }
                if boxMACInvalid {
                    Text("Isso não parece um endereço MAC (ex.: 02:00:00:00:00:f8).")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if client.powerState == .off {
                    Button(action: client.turnOn) {
                        Label("Ligar a TV agora", systemImage: "power")
                            .foregroundColor(.green)
                    }
                }

                Button(role: .destructive, action: {
                    boxMACInput = ""
                    client.forgetBox()
                }) {
                    Label("Esquecer TV Box", systemImage: "trash")
                }
            } else {
                boxPairingSteps
            }
        }
    }

    private var macPlaceholder: String {
        if let guess = client.box?.wakeMACs.first { return "provável: \(guess)" }
        return "02:00:00:00:00:f8"
    }

    private var boxFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Se a TV não ligar, confira:")
                .fontWeight(.semibold)
            Text("• Na TV LG: SIMPLINK ligado (botão SIMPLINK do app, ou Configurações › Opções › SIMPLINK).")
            Text("• Na TV Box (HDMI-CEC): Configurações › Tela e som (ou Sistema › Entradas) › HDMI-CEC ativado, e 'Desligar automaticamente' desativado.")
            Text("• Na TV Box (Energia): Configurações › Sistema › Energia e alimentação › Modo de energia em 'Consumo elevado (Sempre conectado)' e timer de desligamento em 'Nunca', para ela não sair do Wi-Fi após horas em espera.")
            Text("• O iPhone não enxerga o MAC do Wi-Fi da TV Box; o app tenta os endereços vizinhos ao do Bluetooth dela. Se não acordar, digite o MAC (Configurações › Sistema › Sobre › Status na TV Box).")
            Text("• Reserve o IP da TV Box no roteador para o endereço não mudar.")
        }
        .font(.footnote)
    }

    @ViewBuilder
    private var boxPairingSteps: some View {
        switch client.boxPairingStage {
        case .searching:
            progressRow("Procurando TV Box na rede Wi-Fi…")
        case .requestingCode:
            progressRow("Pedindo o código para a TV Box…")
        case .waitingForCode, .confirming:
            codeEntry
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundColor(.orange)
            candidates
        case .idle:
            candidates
        }
    }

    @ViewBuilder
    private var candidates: some View {
        if client.discoveredBoxes.isEmpty {
            Text("Nenhuma TV Box encontrada. Ela precisa estar na tomada e no mesmo Wi-Fi do iPhone.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Button(action: client.searchBoxes) {
                Label("Procurar de novo", systemImage: "magnifyingglass")
            }
        } else {
            stepText(1, "Ligue a TV (só desta vez) e coloque na entrada HDMI da TV Box.")
            stepText(2, "Toque em Parear: um código de 6 caracteres aparece na tela da TV.")
            ForEach(client.discoveredBoxes) { candidate in
                HStack(spacing: 12) {
                    Image(systemName: "tv.and.mediabox")
                        .font(.title3)
                        .foregroundColor(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.name)
                            .font(.headline)
                        Text(candidate.host)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Parear") { client.requestBoxCode(for: candidate) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    private var codeEntry: some View {
        Group {
            stepText(3, "Digite o código que apareceu na tela da TV:")
            HStack {
                TextField("Ex.: 4F2A9C", text: $boxCodeInput)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .keyboardType(.asciiCapable)
                    .onChange(of: boxCodeInput) {
                        let cleaned = String(boxCodeInput.uppercased().filter { $0.isHexDigit }.prefix(6))
                        if cleaned != boxCodeInput { boxCodeInput = cleaned }
                    }
                    .onSubmit(confirmBoxCode)
                Button(client.boxPairingStage == .confirming ? "Confirmando…" : "Confirmar", action: confirmBoxCode)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(boxCodeInput.count != 6 || client.boxPairingStage == .confirming)
            }
            if let error = client.boxCodeError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
            Button("Cancelar pareamento") {
                boxCodeInput = ""
                client.cancelBoxPairing()
            }
            .foregroundColor(.secondary)
        }
    }

    private func stepText(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(red: 0.2, green: 0.4, blue: 0.65)))
            Text(text)
                .font(.footnote)
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func confirmBoxCode() {
        guard boxCodeInput.count == 6 else { return }
        client.confirmBoxCode(boxCodeInput)
    }

    private func saveBoxMAC() {
        boxMACInvalid = !client.setBoxMAC(boxMACInput)
        if !boxMACInvalid { boxMACInput = client.box?.mac ?? "" }
    }

    // MARK: - State

    private var stateText: String {
        switch client.powerState {
        case .on: return "Ligada"
        case .off: return "Desligada"
        case .turningOn: return "Ligando…"
        case .unknown: return "Verificando…"
        }
    }

    private var stateColor: Color {
        switch client.powerState {
        case .on: return .green
        case .off: return .red
        case .turningOn: return .blue
        case .unknown: return .gray
        }
    }

    // MARK: - Actions

    private func saveSettings() {
        let cleanHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(portInput) ?? 8080
        if !cleanHost.isEmpty && (cleanHost != client.config.host || port != client.config.port) {
            client.updateHost(cleanHost, port: port)
        }
        if client.box?.paired == true, boxMACInput != (client.box?.mac ?? "") {
            saveBoxMAC()
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
