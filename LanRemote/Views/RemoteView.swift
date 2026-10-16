import SwiftUI

struct RemoteView: View {
    @ObservedObject var client: LGTVClient
    @StateObject private var volumeHandler = VolumeButtonHandler()
    
    @State private var showSettings: Bool = false
    @State private var showDiscovery: Bool = false
    @State private var showKeypad: Bool = false
    @State private var showPowerAlert: Bool = false
    
    var body: some View {
        ZStack {
            // Dark titanium gradient background
            LinearGradient(
                colors: [Color(white: 0.13), Color(white: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Invisible volume view for hardware button interception
            HiddenVolumeViewRepresentable(handler: volumeHandler)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                // MARK: - Top Header & Status Bar
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        // MARK: - Power & Quick Actions
                        topActionsView
                        
                        // MARK: - Collapsible Numeric Keypad
                        if showKeypad {
                            NumericKeypadView(onKey: { key in
                                client.sendKey(key)
                            })
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                        }
                        
                        // MARK: - Navigation Satellites & Circular D-Pad
                        navigationSection
                        
                        // MARK: - Volume, Mute & Channel Rockers
                        rockersSection
                        
                        // MARK: - Smart TV & Function Shortcuts
                        smartShortcutsSection
                        
                        // MARK: - Media Playback Bar
                        mediaSection
                        
                        // MARK: - Color Keys (Red, Green, Yellow, Blue)
                        colorKeysSection
                        
                        // MARK: - Footer Status
                        footerView
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(client: client)
        }
        .sheet(isPresented: $showDiscovery) {
            DiscoveryView(onSelect: { tv in
                client.updateHost(tv.ip, port: tv.port)
                showDiscovery = false
            })
        }
        .alert(isPresented: $showPowerAlert) {
            Alert(
                title: Text("Desligar a TV?"),
                message: Text("Atenção: A TV LG NetCast entra em Standby e não poderá ser ligada novamente pela rede Wi-Fi."),
                primaryButton: .destructive(Text("Desligar TV")) {
                    client.sendKey(.power)
                },
                secondaryButton: .cancel(Text("Cancelar"))
            )
        }
        .onAppear {
            setupPhysicalVolumeButtons()
        }
        .onDisappear {
            volumeHandler.stopListening()
        }
    }
    
    private func setupPhysicalVolumeButtons() {
        volumeHandler.onVolumeUp = {
            client.sendKey(.volumeUp)
        }
        volumeHandler.onVolumeDown = {
            client.sendKey(.volumeDown)
        }
        volumeHandler.startListening()
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            // Online LED Dot
            Circle()
                .fill(client.isConnected ? Color.green : Color.red)
                .frame(width: 9, height: 9)
                .shadow(color: (client.isConnected ? Color.green : Color.red).opacity(0.8), radius: 4)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(client.config.model ?? "LG NetCast")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(client.config.host)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                    
                    if client.isConnected {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.4))
                        
                        Text(client.isMuted ? "MUDO" : "Vol \(client.volumeLevel)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(client.isMuted ? .orange : Color(red: 0.4, green: 0.8, blue: 1.0))
                    }
                }
            }
            
            Spacer()
            
            // Discovery Radar Button
            Button(action: { showDiscovery = true }) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(white: 0.8))
                    .frame(width: 34, height: 34)
                    .background(Color(white: 0.20))
                    .clipShape(Circle())
            }
            
            // Settings Gear Button
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(white: 0.8))
                    .frame(width: 34, height: 34)
                    .background(Color(white: 0.20))
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Top Actions (Power, Source, Keypad toggle)
    private var topActionsView: some View {
        HStack(spacing: 12) {
            // Power Button
            Button(action: {
                HapticManager.shared.warning()
                showPowerAlert = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .bold))
                    Text("Power")
                }
            }
            .buttonStyle(PowerButtonStyle())
            
            // Input / Source Button
            Button(action: { client.sendKey(.input) }) {
                HStack(spacing: 4) {
                    Image(systemName: "tv.and.mediabox")
                    Text("Input")
                }
            }
            .buttonStyle(RemoteButtonStyle(bg: Color(white: 0.22), fg: Color(white: 0.95)))
            
            // 123 Numeric Keypad Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showKeypad.toggle()
                }
                HapticManager.shared.buttonPress()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: showKeypad ? "keyboard.chevron.compact.down" : "circle.grid.3x3.fill")
                    Text("123")
                }
            }
            .buttonStyle(RemoteButtonStyle(
                bg: showKeypad ? Color(red: 0.15, green: 0.35, blue: 0.58) : Color(white: 0.22),
                fg: .white
            ))
        }
    }
    
    // MARK: - Navigation Section (Satellites & Circular D-Pad)
    private var navigationSection: some View {
        VStack(spacing: 10) {
            // Top Satellites: Back & Exit
            HStack(spacing: 12) {
                Button(action: { client.sendKey(.back) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.backward.fill")
                        Text("Voltar")
                    }
                }
                .buttonStyle(RemoteButtonStyle(bg: Color(white: 0.22), height: 38, cornerRadius: 10))
                
                Button(action: { client.sendKey(.exit) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Sair")
                    }
                }
                .buttonStyle(RemoteButtonStyle(bg: Color(white: 0.22), height: 38, cornerRadius: 10))
            }
            
            // Circular D-Pad
            DPadView(onKey: { key in
                client.sendKey(key)
            })
            .padding(.vertical, 4)
            
            // Bottom Satellites: Home & Menu
            HStack(spacing: 12) {
                Button(action: { client.sendKey(.home) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                }
                .buttonStyle(RemoteButtonStyle(
                    bg: Color(red: 0.14, green: 0.36, blue: 0.60),
                    fg: .white,
                    height: 38,
                    cornerRadius: 10
                ))
                
                Button(action: { client.sendKey(.menu) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal")
                        Text("Menu")
                    }
                }
                .buttonStyle(RemoteButtonStyle(bg: Color(white: 0.22), height: 38, cornerRadius: 10))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: 0.16).opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.24), lineWidth: 1))
        )
    }
    
    // MARK: - Rockers Section (Volume, Mute, Channel)
    private var rockersSection: some View {
        HStack(spacing: 16) {
            // Volume Rocker
            RockerSwitchView(
                title: "VOL",
                upKey: .volumeUp,
                downKey: .volumeDown,
                onKey: { key in client.sendKey(key) }
            )
            
            Spacer()
            
            // Center Mute & Live TV
            VStack(spacing: 8) {
                Button(action: { client.sendKey(.mute) }) {
                    VStack(spacing: 4) {
                        Image(systemName: client.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 20))
                        Text(client.isMuted ? "MUTED" : "MUDO")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(client.isMuted ? .white : Color(white: 0.9))
                    .frame(width: 66, height: 60)
                    .background(client.isMuted ? Color.orange : Color(white: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(client.isMuted ? Color.orange.opacity(0.6) : Color(white: 0.30), lineWidth: 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                
                Button(action: { client.sendKey(.liveTv) }) {
                    Text("LIVE TV")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(white: 0.85))
                        .frame(width: 66, height: 36)
                        .background(Color(white: 0.20))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.28), lineWidth: 1))
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            Spacer()
            
            // Channel Rocker
            RockerSwitchView(
                title: "CH",
                upKey: .channelUp,
                downKey: .channelDown,
                onKey: { key in client.sendKey(key) }
            )
        }
        .padding(.horizontal, 8)
    }
    
    // MARK: - Smart TV & Function Shortcuts
    private var smartShortcutsSection: some View {
        HStack(spacing: 8) {
            shortcutButton(label: "Apps", icon: "square.grid.2x2.fill", key: .apps)
            shortcutButton(label: "Info", icon: "info.circle", key: .info)
            shortcutButton(label: "Q.Menu", icon: "slider.horizontal.3", key: .quickMenu)
            shortcutButton(label: "Guia", icon: "list.bullet.rectangle", key: .epg)
        }
    }
    
    private func shortcutButton(label: String, icon: String, key: TVKey) -> some View {
        Button(action: { client.sendKey(key) }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
        }
        .buttonStyle(RemoteButtonStyle(bg: Color(white: 0.20), height: 42, cornerRadius: 10))
    }
    
    // MARK: - Media Playback Controls
    private var mediaSection: some View {
        HStack(spacing: 8) {
            mediaButton(icon: "backward.fill", key: .rewind)
            mediaButton(icon: "play.fill", key: .play)
            mediaButton(icon: "pause.fill", key: .pause)
            mediaButton(icon: "stop.fill", key: .stop)
            mediaButton(icon: "forward.fill", key: .fastForward)
        }
    }
    
    private func mediaButton(icon: String, key: TVKey) -> some View {
        Button(action: { client.sendKey(key) }) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(RemoteButtonStyle(bg: Color(white: 0.18), height: 38, cornerRadius: 8))
    }
    
    // MARK: - Color Keys (Red, Green, Yellow, Blue)
    private var colorKeysSection: some View {
        HStack(spacing: 8) {
            Button(action: { client.sendKey(.red) }) {}
                .buttonStyle(ColorKeyStyle(color: Color(red: 0.85, green: 0.2, blue: 0.2)))
            
            Button(action: { client.sendKey(.green) }) {}
                .buttonStyle(ColorKeyStyle(color: Color(red: 0.2, green: 0.75, blue: 0.3)))
            
            Button(action: { client.sendKey(.yellow) }) {}
                .buttonStyle(ColorKeyStyle(color: Color(red: 0.95, green: 0.75, blue: 0.1)))
            
            Button(action: { client.sendKey(.blue) }) {}
                .buttonStyle(ColorKeyStyle(color: Color(red: 0.2, green: 0.45, blue: 0.9)))
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Text(client.statusMessage)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Color(white: 0.6))
                .lineLimit(1)
            
            Spacer()
            
            if client.isSending {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}
