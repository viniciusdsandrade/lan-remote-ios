import SwiftUI
import UIKit

struct RemoteView: View {
    @ObservedObject var client: LGTVClient
    @StateObject private var help = HelpCenter()

    @State private var showSettings: Bool = false
    @State private var showDiscovery: Bool = false
    @State private var showGuide: Bool = false
    @State private var showKeypad: Bool = false
    @State private var showPowerAlert: Bool = false

    /// Keys can't reach the TV right now: dim the remote and show how to switch it on.
    private var tvAsleep: Bool { client.powerState == .off || client.powerState == .turningOn }
    /// Keys can't leave the iPhone at all (off Wi-Fi, or local network access denied).
    private var remoteUnavailable: Bool { tvAsleep || client.networkBlock != nil }

    var body: some View {
        ZStack {
            // Dark titanium gradient background
            LinearGradient(
                colors: [Color(white: 0.13), Color(white: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Header & Status Bar
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        // MARK: - What keeps the remote from reaching the TV, and the way out
                        if let block = client.networkBlock {
                            NetworkBlockBanner(block: block, attentionPulse: client.attentionPulse)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else if tvAsleep {
                            PowerBanner(client: client, openSettings: { showSettings = true })
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else if client.needsPairing {
                            PairingBanner(openSettings: { showSettings = true })
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // MARK: - Power & Quick Actions
                        topActionsView

                        // MARK: - Collapsible Numeric Keypad
                        if showKeypad {
                            NumericKeypadView(onKey: client.sendKey)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity.combined(with: .scale(scale: 0.95))
                                ))
                        }

                        VStack(spacing: 14) {
                            navigationSection
                            volumeSection
                            featuresSection
                            mediaSection
                            colorKeysSection
                        }
                        .opacity(remoteUnavailable ? 0.45 : 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .animation(.easeInOut(duration: 0.2), value: remoteUnavailable)
                }

                // MARK: - What the control being held does
                HelpPanel(openGuide: { showGuide = true })
            }
        }
        .environmentObject(help)
        .sheet(isPresented: $showSettings) {
            SettingsView(client: client)
        }
        .sheet(isPresented: $showDiscovery) {
            DiscoveryView(onSelect: { tv in
                client.updateHost(tv.ip, port: tv.port)
                showDiscovery = false
            })
        }
        .sheet(isPresented: $showGuide) {
            ButtonGuideView()
        }
        .alert(isPresented: $showPowerAlert) {
            Alert(
                title: Text("Desligar a TV?"),
                message: Text(client.canTurnOnTV
                    ? "Para ligar de novo, use o botão Ligar do app: a TV Box liga a TV pelo HDMI."
                    : "Esta TV não liga pela rede sozinha. Para ligar pelo app depois, configure a TV Box em Ajustes."),
                primaryButton: .destructive(Text("Desligar")) {
                    client.sendKey(.power)
                },
                secondaryButton: .cancel(Text("Cancelar"))
            )
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            // Online LED Dot
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
                .shadow(color: statusColor.opacity(0.8), radius: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(tvName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if client.powerState == .on, client.notAnswering {
                        Text(statusText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(statusColor)
                            .lineLimit(1)
                            .onTapGesture {
                                help.show(client.ipConflict ? Help.ipConflictStatus : Help.notAnsweringStatus)
                            }
                            .controlHelp(client.ipConflict ? Help.ipConflictStatus : Help.notAnsweringStatus)
                    } else {
                        Text(statusText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(statusColor)
                            .lineLimit(1)
                    }

                    if client.powerState == .on, !client.notAnswering, !client.needsPairing {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.4))

                        Text(client.isMuted ? "Mudo" : "Vol \(client.volumeLevel)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(client.isMuted ? .orange : Color(red: 0.4, green: 0.8, blue: 1.0))
                            .controlHelp(Help.volumeStatus)

                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.4))

                        Text(client.inputSourceName.isEmpty || client.inputSourceName == "---" ? "TV" : client.inputSourceName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(white: 0.85))
                            .controlHelp(Help.inputStatus)
                    }
                }
            }

            Spacer()

            headerButton("antenna.radiowaves.left.and.right", help: Help.discovery) { showDiscovery = true }
            headerButton("questionmark.circle", help: Help.guideSheet) { showGuide = true }
            headerButton("gearshape.fill", help: Help.settings) { showSettings = true }
        }
        .padding(.vertical, 6)
    }

    private var tvName: String {
        let model = (client.config.model ?? "").split(separator: "-").first.map(String.init) ?? ""
        return model.isEmpty ? "TV LG" : "TV LG \(model)"
    }

    private var statusText: String {
        switch client.networkBlock {
        case .offWiFi: return "iPhone fora do Wi-Fi"
        case .localNetworkDenied: return "Sem acesso à rede local"
        case nil: break
        }
        switch client.powerState {
        case .on:
            if client.ipConflict { return "Ligada · conflito de IP" }
            if client.needsPairing { return "Ligada · falta parear" }
            return client.notAnswering ? "Ligada · sem resposta" : "Ligada"
        case .off: return "Desligada"
        case .turningOn: return "Ligando…"
        case .unknown: return "Verificando…"
        }
    }

    private var statusColor: Color {
        if client.networkBlock != nil { return Color.orange }
        switch client.powerState {
        case .on: return client.notAnswering || client.needsPairing ? Color.orange : Color.green
        case .off: return Color(red: 0.95, green: 0.35, blue: 0.3)
        case .turningOn: return Color(red: 0.4, green: 0.7, blue: 1.0)
        case .unknown: return Color(white: 0.55)
        }
    }

    private func headerButton(_ symbol: String, help: ControlHelp, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(white: 0.8))
                .frame(width: 34, height: 34)
                .background(Color(white: 0.20))
                .clipShape(Circle())
        }
        .controlHelp(help)
    }

    // MARK: - Top Actions (Power, Source, Keypad toggle)
    private var topActionsView: some View {
        HStack(spacing: 12) {
            if tvAsleep {
                Button(action: { client.canTurnOnTV ? client.turnOn() : (showSettings = true) }) {
                    ControlLabel(help: Help.powerOn)
                }
                .buttonStyle(PowerButtonStyle(turnsOn: true))
                .disabled(client.powerState == .turningOn)
                .controlHelp(Help.powerOn)
            } else {
                Button(action: {
                    HapticManager.shared.warning()
                    showPowerAlert = true
                }) {
                    ControlLabel(help: Help.powerOff)
                }
                .buttonStyle(PowerButtonStyle())
                .controlHelp(Help.powerOff)
            }

            keyButton(.input, Help.input, bg: Color(white: 0.22), height: 54)

            // Numeric Keypad Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showKeypad.toggle()
                }
                HapticManager.shared.buttonPress()
            }) {
                ControlLabel(help: Help.keypad)
            }
            .buttonStyle(RemoteButtonStyle(
                bg: showKeypad ? Color(red: 0.15, green: 0.35, blue: 0.58) : Color(white: 0.22),
                fg: .white,
                height: 54
            ))
            .controlHelp(Help.keypad)
        }
    }

    private func keyButton(_ key: TVKey, _ help: ControlHelp, bg: Color = Color(white: 0.22),
                           height: CGFloat = 50) -> some View {
        Button(action: { client.sendKey(key) }) {
            ControlLabel(help: help)
        }
        .buttonStyle(RemoteButtonStyle(bg: bg, height: height, cornerRadius: 12))
        .controlHelp(help)
    }

    // MARK: - Navigation Section (Satellites & Circular D-Pad)
    private var navigationSection: some View {
        RemoteSection(title: "Navegação") {
            HStack(spacing: 10) {
                keyButton(.quickMenu, Help.quickMenu)
                keyButton(.home, Help.home, bg: Color(red: 0.14, green: 0.36, blue: 0.60))
                keyButton(.menu, Help.menu)
            }

            DPadView(onKey: client.sendKey)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            HStack(spacing: 10) {
                keyButton(.back, Help.back)
                keyButton(.exit, Help.exit)
                keyButton(.epg, Help.guide)
            }
        }
    }

    // MARK: - Rockers Section (Volume, Mute, Channel)
    private var volumeSection: some View {
        RemoteSection(title: "Volume e canal") {
            HStack(spacing: 12) {
                RockerSwitchView(title: "VOLUME", upSymbol: "plus", downSymbol: "minus",
                                 upKey: .volumeUp, downKey: .volumeDown,
                                 upHelp: Help.volumeUp, downHelp: Help.volumeDown, onKey: client.sendKey)

                VStack(spacing: 10) {
                    Button(action: { client.sendKey(.mute) }) {
                        VStack(spacing: 4) {
                            Image(systemName: client.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(client.isMuted ? .orange : Color.white)
                            Text(client.isMuted ? "Sem som" : Help.mute.label)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                    }
                    .buttonStyle(RemoteButtonStyle(bg: client.isMuted ? Color(red: 0.5, green: 0.25, blue: 0.1) : Color(white: 0.22),
                                                   height: 54, cornerRadius: 12))
                    .controlHelp(Help.mute)

                    keyButton(.liveTv, Help.liveTV, height: 54)
                }
                .frame(maxWidth: .infinity)

                RockerSwitchView(title: "CANAL", upSymbol: "chevron.up", downSymbol: "chevron.down",
                                 upKey: .channelUp, downKey: .channelDown,
                                 upHelp: Help.channelUp, downHelp: Help.channelDown, onKey: client.sendKey)
            }
        }
    }

    // MARK: - Smart TV & Function Shortcuts
    private var featuresSection: some View {
        RemoteSection(title: "Recursos da TV") {
            HStack(spacing: 8) {
                keyButton(.apps, Help.apps, bg: Color(white: 0.20))
                keyButton(.aspectRatio, Help.aspect, bg: Color(white: 0.20))
                keyButton(.key3d, Help.threeD, bg: Color(white: 0.20))
                keyButton(.simplink, Help.simplink, bg: Color(white: 0.20))
            }
        }
    }

    // MARK: - Media Playback Controls
    private var mediaSection: some View {
        RemoteSection(title: "Reprodução") {
            HStack(spacing: 8) {
                mediaButton(.rewind, Help.rewind)
                mediaButton(.play, Help.play, bg: Color(red: 0.15, green: 0.45, blue: 0.25))
                mediaButton(.pause, Help.pause)
                mediaButton(.stop, Help.stop)
                mediaButton(.fastForward, Help.forward)
            }
        }
    }

    private func mediaButton(_ key: TVKey, _ help: ControlHelp, bg: Color = Color(white: 0.18)) -> some View {
        Button(action: { client.sendKey(key) }) {
            Image(systemName: help.symbol)
                .font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(RemoteButtonStyle(bg: bg, height: 40, cornerRadius: 8))
        .controlHelp(help)
    }

    // MARK: - Color Keys (Red, Green, Yellow, Blue)
    private var colorKeysSection: some View {
        RemoteSection(title: "Botões coloridos") {
            HStack(spacing: 8) {
                colorKey(.red, Help.red)
                colorKey(.green, Help.green)
                colorKey(.yellow, Help.yellow)
                colorKey(.blue, Help.blue)
            }
        }
    }

    private func colorKey(_ key: TVKey, _ help: ControlHelp) -> some View {
        Button(action: { client.sendKey(key) }) {}
            .buttonStyle(ColorKeyStyle(color: help.tint ?? Color.gray))
            .controlHelp(help)
    }
}

// MARK: - Power banner

/// Shown while the TV is off: says why the remote is dimmed and offers the way to switch it on.
private struct PowerBanner: View {
    @ObservedObject var client: LGTVClient
    let openSettings: () -> Void
    @State private var nudge = false

    private var turningOn: Bool { client.powerState == .turningOn }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.17, green: 0.25, blue: 0.33))
                        .frame(width: 38, height: 38)
                    if turningOn {
                        ProgressView()
                            .tint(Color(red: 0.55, green: 0.78, blue: 1.0))
                    } else {
                        Image(systemName: "tv")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.55, green: 0.78, blue: 1.0))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(turningOn ? "Ligando a TV…" : "A TV está desligada")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(client.powerOnError != nil && !turningOn ? Color.orange : Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if !turningOn {
                if client.canTurnOnTV {
                    Button(action: client.turnOn) {
                        Label(client.powerOnError == nil ? "Ligar a TV" : "Tentar de novo", systemImage: "power")
                    }
                    .buttonStyle(RemoteButtonStyle(bg: Color(red: 0.13, green: 0.55, blue: 0.27), height: 44, cornerRadius: 11))
                    .controlHelp(Help.powerOn)
                } else {
                    Button(action: openSettings) {
                        Label("Configurar para ligar pelo app", systemImage: "gearshape")
                    }
                    .buttonStyle(RemoteButtonStyle(bg: Color(red: 0.15, green: 0.40, blue: 0.65), height: 44, cornerRadius: 11))
                    .controlHelp(Help.settings)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.11, green: 0.15, blue: 0.19)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(nudge ? Color.orange : Color(red: 0.24, green: 0.36, blue: 0.48), lineWidth: nudge ? 2 : 1)
        )
        .scaleEffect(nudge ? 1.02 : 1)
        .onChange(of: client.attentionPulse) {
            // A key was pressed with the TV off: point at the way out instead of failing silently.
            withAnimation(.easeOut(duration: 0.12)) { nudge = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeIn(duration: 0.25)) { nudge = false }
            }
        }
    }

    private var message: String {
        if turningOn { return client.powerOnStep }
        if let error = client.powerOnError { return error }
        if let box = client.box, box.paired {
            return "Toque em Ligar: a \(box.name) liga a TV pelo HDMI. A imagem volta em segundos; o controle, em até 1 minuto."
        }
        return "Em standby esta TV desliga a rede. Dá para ligá-la pela TV Box ligada no HDMI: configure uma vez."
    }
}

/// The iPhone can't reach the LAN: off Wi-Fi, or iOS denies the app local network access (which looked
/// like a TV that had vanished: "Desligada", and no TV in the search).
private struct NetworkBlockBanner: View {
    let block: NetworkBlock
    let attentionPulse: Int
    @State private var nudge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.33, green: 0.22, blue: 0.10))
                        .frame(width: 38, height: 38)
                    Image(systemName: block == .offWiFi ? "wifi.slash" : "lock.shield")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: openSystemSettings) {
                Label(block == .offWiFi ? "Abrir Ajustes" : "Abrir Ajustes do app", systemImage: "gearshape")
            }
            .buttonStyle(RemoteButtonStyle(bg: Color(red: 0.15, green: 0.40, blue: 0.65), height: 44, cornerRadius: 11))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.19, green: 0.14, blue: 0.09)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(nudge ? Color.orange : Color(red: 0.48, green: 0.33, blue: 0.16), lineWidth: nudge ? 2 : 1)
        )
        .scaleEffect(nudge ? 1.02 : 1)
        .onChange(of: attentionPulse) {
            withAnimation(.easeOut(duration: 0.12)) { nudge = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeIn(duration: 0.25)) { nudge = false }
            }
        }
    }

    private var title: String {
        block == .offWiFi ? "O iPhone está fora do Wi-Fi" : "Permita o acesso à rede local"
    }

    private var message: String {
        switch block {
        case .offWiFi:
            return "O controle fala com a TV pela rede Wi-Fi de casa. Conecte o iPhone à mesma rede da TV."
        case .localNetworkDenied:
            return "O iOS está bloqueando o app na rede de casa, então ele não enxerga a TV. Em Ajustes › Lan Remote, ligue Rede Local. Se já estiver ligada, desligue e ligue de novo."
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// The TV answers but refuses the app: no pairing key saved, or one the TV no longer accepts.
private struct PairingBanner: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.17, green: 0.25, blue: 0.33))
                        .frame(width: 38, height: 38)
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.55, green: 0.78, blue: 1.0))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pareie o app com a TV")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("A TV foi encontrada, mas ainda não aceita este iPhone. Em Ajustes, toque em Pedir Código na TV e digite os 6 números que aparecem na tela.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: openSettings) {
                Label("Parear", systemImage: "key.horizontal")
            }
            .buttonStyle(RemoteButtonStyle(bg: Color(red: 0.15, green: 0.40, blue: 0.65), height: 44, cornerRadius: 11))
            .controlHelp(Help.settings)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.11, green: 0.15, blue: 0.19)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.24, green: 0.36, blue: 0.48), lineWidth: 1))
    }
}
