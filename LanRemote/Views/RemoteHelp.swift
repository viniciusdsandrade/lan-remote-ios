import SwiftUI

// What every control does, in plain words. One catalog feeds the hold-to-learn panel, the button
// guide and VoiceOver, so they never disagree.

struct ControlHelp: Identifiable, Equatable {
    let id: String
    let label: String        // caption on the button itself
    let title: String        // heading in the help panel and in the guide
    let detail: String
    let symbol: String
    var tip: String? = nil   // small badge, e.g. the phone's side buttons
    var tint: Color? = nil   // color keys
}

enum Help {
    // Power and source
    static let powerOff = ControlHelp(id: "power", label: "Desligar", title: "Desligar a TV",
        detail: "Coloca a TV em standby. Para ligar de novo sem levantar, use o botão Ligar do app.",
        symbol: "power")
    static let powerOn = ControlHelp(id: "power-on", label: "Ligar", title: "Ligar a TV",
        detail: "Acorda a TV Box pelo Wi-Fi e ela liga a TV pelo HDMI (SIMPLINK). A imagem volta em segundos; o controle, em até 1 minuto.",
        symbol: "power")
    static let input = ControlHelp(id: "input", label: "Entrada", title: "Entrada (fonte da imagem)",
        detail: "Troca entre TV (antena/cabo), HDMI 1, HDMI 2, AV… Cada toque passa para a próxima.",
        symbol: "rectangle.on.rectangle")
    static let keypad = ControlHelp(id: "keypad", label: "Números", title: "Teclado numérico",
        detail: "Mostra os números para ir direto a um canal: toque 1 e 3 para o canal 13.",
        symbol: "circle.grid.3x3.fill")
    static let digit = ControlHelp(id: "digit", label: "", title: "Número do canal",
        detail: "Digita o número do canal. Espere um instante depois do último dígito.",
        symbol: "number")
    static let previousChannel = ControlHelp(id: "previous", label: "Último", title: "Último canal",
        detail: "Volta para o canal que você estava vendo antes. Bom para alternar entre dois canais.",
        symbol: "arrow.uturn.backward.circle")
    static let info = ControlHelp(id: "info", label: "Info", title: "Informações",
        detail: "Mostra o nome do programa, o horário e os dados do canal atual.",
        symbol: "info.circle")

    // Navigation
    static let quickMenu = ControlHelp(id: "qmenu", label: "Ajuste rápido", title: "Ajuste rápido (Q.Menu)",
        detail: "Atalhos sem sair do que está vendo: modo de imagem, modo de som, formato da tela e timer para desligar.",
        symbol: "slider.horizontal.3")
    static let home = ControlHelp(id: "home", label: "Início", title: "Início (Smart TV)",
        detail: "Abre a tela inicial da LG, com os aplicativos, as entradas e os ajustes.",
        symbol: "house.fill")
    static let menu = ControlHelp(id: "menu", label: "Configurações", title: "Configurações da TV",
        detail: "Menu completo: imagem, som, canais, rede, horário e opções como o SIMPLINK.",
        symbol: "gearshape")
    static let arrows = ControlHelp(id: "arrows", label: "", title: "Setas",
        detail: "Movem a seleção nos menus e nos aplicativos da TV.",
        symbol: "arrow.up.and.down.and.arrow.left.and.right")
    static let ok = ControlHelp(id: "ok", label: "OK", title: "OK (confirmar)",
        detail: "Confirma o item selecionado no menu ou no aplicativo.",
        symbol: "checkmark.circle")
    static let back = ControlHelp(id: "back", label: "Voltar", title: "Voltar",
        detail: "Volta um passo: fecha a tela ou o menu que está aberto agora.",
        symbol: "arrow.uturn.backward")
    static let exit = ControlHelp(id: "exit", label: "Sair", title: "Sair dos menus",
        detail: "Fecha todos os menus de uma vez e volta direto para o que você estava assistindo.",
        symbol: "xmark")
    static let guide = ControlHelp(id: "epg", label: "Programação", title: "Guia de programação",
        detail: "Mostra o que está passando agora e o que vem depois em cada canal da TV aberta.",
        symbol: "calendar")

    // Volume and channels
    static let volumeUp = ControlHelp(id: "vol+", label: "", title: "Aumentar volume",
        detail: "Aumenta o volume da TV um ponto por toque.", symbol: "speaker.plus", tip: "Botão lateral +")
    static let volumeDown = ControlHelp(id: "vol-", label: "", title: "Diminuir volume",
        detail: "Diminui o volume da TV um ponto por toque.", symbol: "speaker.minus", tip: "Botão lateral −")
    static let volume = ControlHelp(id: "vol", label: "Volume", title: "Volume + / −",
        detail: "Aumenta ou diminui o volume da TV, um ponto por toque. Os botões laterais do iPhone também funcionam.",
        symbol: "speaker.wave.2", tip: "Botões laterais")
    static let mute = ControlHelp(id: "mute", label: "Mudo", title: "Mudo",
        detail: "Corta o som na hora. Toque de novo para o som voltar no mesmo volume.",
        symbol: "speaker.slash.fill")
    static let liveTV = ControlHelp(id: "live", label: "TV ao vivo", title: "TV ao vivo",
        detail: "Sai do aplicativo ou do menu e volta para os canais da antena ou do cabo.",
        symbol: "antenna.radiowaves.left.and.right")
    static let channelUp = ControlHelp(id: "ch+", label: "", title: "Próximo canal",
        detail: "Passa para o próximo canal da lista.", symbol: "chevron.up")
    static let channelDown = ControlHelp(id: "ch-", label: "", title: "Canal anterior",
        detail: "Volta para o canal anterior da lista.", symbol: "chevron.down")
    static let channel = ControlHelp(id: "ch", label: "Canal", title: "Canal ˄ / ˅",
        detail: "Passa para o próximo canal da lista ou volta para o anterior.", symbol: "list.number")

    // TV features
    static let apps = ControlHelp(id: "apps", label: "Apps", title: "Aplicativos",
        detail: "Abre a lista de aplicativos da Smart TV, como YouTube e o navegador.",
        symbol: "square.grid.2x2.fill")
    static let aspect = ControlHelp(id: "ratio", label: "Formato", title: "Formato da imagem",
        detail: "Muda entre 16:9, 4:3, zoom e ajustar à tela. Use quando a imagem estiver esticada ou com faixas pretas.",
        symbol: "aspectratio")
    static let threeD = ControlHelp(id: "3d", label: "3D", title: "Modo 3D",
        detail: "Liga ou desliga o modo 3D. Só faz efeito em TVs e vídeos com 3D.",
        symbol: "cube")
    static let simplink = ControlHelp(id: "simplink", label: "SIMPLINK", title: "SIMPLINK (HDMI-CEC)",
        detail: "Abre o menu dos aparelhos ligados no HDMI (TV Box, PS5). Deixe ativado: é por ele que o app liga a TV.",
        symbol: "link")

    // Playback
    static let rewind = ControlHelp(id: "rew", label: "", title: "Retroceder",
        detail: "Volta o vídeo ou a música que está tocando na TV (pen drive, apps da LG).", symbol: "backward.fill")
    static let play = ControlHelp(id: "play", label: "", title: "Reproduzir",
        detail: "Começa ou retoma o vídeo ou a música que está tocando na TV.", symbol: "play.fill")
    static let pause = ControlHelp(id: "pause", label: "", title: "Pausar",
        detail: "Pausa o vídeo ou a música. Toque em Reproduzir para continuar.", symbol: "pause.fill")
    static let stop = ControlHelp(id: "stop", label: "", title: "Parar",
        detail: "Encerra a reprodução e volta para a lista de arquivos.", symbol: "stop.fill")
    static let forward = ControlHelp(id: "ff", label: "", title: "Avançar",
        detail: "Adianta o vídeo ou a música que está tocando na TV.", symbol: "forward.fill")
    static let media = ControlHelp(id: "media", label: "", title: "Reprodução",
        detail: "Retroceder, reproduzir, pausar, parar e avançar: para vídeos e músicas tocando na TV (pen drive, apps da LG).",
        symbol: "playpause.fill")

    // Color keys: their meaning comes from whatever is on screen.
    private static let colorDetail = "Faz o que a TV mostrar na parte de baixo da tela para essa cor (no guia, nos arquivos do pen drive)."
    static let red = ControlHelp(id: "red", label: "", title: "Botão vermelho", detail: colorDetail,
        symbol: "circle.fill", tint: Color(red: 0.85, green: 0.2, blue: 0.2))
    static let green = ControlHelp(id: "green", label: "", title: "Botão verde", detail: colorDetail,
        symbol: "circle.fill", tint: Color(red: 0.2, green: 0.75, blue: 0.3))
    static let yellow = ControlHelp(id: "yellow", label: "", title: "Botão amarelo", detail: colorDetail,
        symbol: "circle.fill", tint: Color(red: 0.95, green: 0.75, blue: 0.1))
    static let blue = ControlHelp(id: "blue", label: "", title: "Botão azul", detail: colorDetail,
        symbol: "circle.fill", tint: Color(red: 0.2, green: 0.45, blue: 0.9))
    static let colors = ControlHelp(id: "colors", label: "", title: "Botões coloridos",
        detail: "Mudam conforme a tela: quando servem para algo, a TV mostra embaixo o que cada cor faz (no guia, nos arquivos do pen drive).",
        symbol: "circle.grid.2x1.fill")

    // App
    static let discovery = ControlHelp(id: "discovery", label: "", title: "Buscar TV na rede",
        detail: "Procura a TV LG no Wi-Fi e preenche o IP sozinho.", symbol: "antenna.radiowaves.left.and.right")
    static let refresh = ControlHelp(id: "refresh", label: "", title: "Atualizar",
        detail: "Pergunta de novo à TV se ela está ligada, o volume e a entrada atual.", symbol: "arrow.clockwise")
    static let guideSheet = ControlHelp(id: "guide-sheet", label: "", title: "Guia dos botões",
        detail: "Abre a lista com o que cada botão do controle faz.", symbol: "questionmark.circle")
    static let settings = ControlHelp(id: "settings", label: "", title: "Ajustes do app",
        detail: "IP da TV, pareamento e a TV Box que liga a TV pelo HDMI.", symbol: "gearshape.fill")
    static let volumeStatus = ControlHelp(id: "vol-status", label: "", title: "Volume atual",
        detail: "Volume que a TV informou agora (ou Mudo).", symbol: "speaker.wave.2.fill")
    static let inputStatus = ControlHelp(id: "input-status", label: "", title: "Entrada atual",
        detail: "Fonte que a TV está mostrando: TV, HDMI, AV…", symbol: "tv")
}

struct GuideSection: Identifiable {
    let title: String
    let items: [ControlHelp]
    var id: String { title }

    static let all: [GuideSection] = [
        GuideSection(title: "Ligar e escolher a fonte",
                     items: [Help.powerOn, Help.powerOff, Help.input, Help.keypad, Help.previousChannel, Help.info]),
        GuideSection(title: "Navegação",
                     items: [Help.quickMenu, Help.home, Help.menu, Help.arrows, Help.ok, Help.back, Help.exit,
                             Help.guide]),
        GuideSection(title: "Volume e canal", items: [Help.volume, Help.mute, Help.liveTV, Help.channel]),
        GuideSection(title: "Recursos da TV", items: [Help.apps, Help.aspect, Help.threeD, Help.simplink]),
        GuideSection(title: "Reprodução", items: [Help.media]),
        GuideSection(title: "Botões coloridos", items: [Help.colors]),
        GuideSection(title: "O app", items: [Help.discovery, Help.refresh, Help.guideSheet, Help.settings]),
    ]
}

// MARK: - Hold to learn

/// The control being explained right now (a finger held on it); clears itself after a while.
@MainActor
final class HelpCenter: ObservableObject {
    @Published var current: ControlHelp?
    private var hideTask: Task<Void, Never>?

    func show(_ help: ControlHelp) {
        HapticManager.shared.selectionChanged()
        withAnimation(.easeOut(duration: 0.15)) { current = help }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { current = nil }
    }
}

private struct HoldForHelp: ViewModifier {
    @EnvironmentObject private var center: HelpCenter
    let help: ControlHelp

    func body(content: Content) -> some View {
        content
            // A long press wins over the button's tap, so holding explains without sending anything.
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in center.show(help) })
            .accessibilityLabel(Text(help.title))
            .accessibilityHint(Text(help.detail))
    }
}

extension View {
    /// Explains this control in the help panel while a finger is held on it.
    func controlHelp(_ help: ControlHelp) -> some View {
        modifier(HoldForHelp(help: help))
    }
}

struct HelpIcon: View {
    let help: ControlHelp
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27)
            .fill(Color(white: 0.22))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: help.symbol)
                    .font(.system(size: size * (help.tint == nil ? 0.45 : 0.5), weight: .semibold))
                    .foregroundColor(help.tint ?? Color(white: 0.9))
            )
    }
}

struct TipBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(Color(white: 0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.24)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.34), lineWidth: 1))
    }
}

/// Fixed strip under the remote: explains the control being held, or says how to ask.
struct HelpPanel: View {
    @EnvironmentObject private var center: HelpCenter
    let openGuide: () -> Void

    var body: some View {
        Group {
            if let help = center.current {
                HStack(alignment: .top, spacing: 12) {
                    HelpIcon(help: help)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(help.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let tip = help.tip {
                                TipBadge(text: tip)
                            }
                        }
                        Text(help.detail)
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: center.hide) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(white: 0.45))
                    }
                    .accessibilityLabel("Fechar explicação")
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: center.hide)
                .transition(.opacity)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.35))
                    Text("Segure um botão para saber o que ele faz.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button(action: openGuide) {
                        Text("Ver guia")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(red: 0.45, green: 0.72, blue: 1.0))
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Color(white: 0.11))
        .overlay(Rectangle().fill(Color(white: 0.22)).frame(height: 1), alignment: .top)
    }
}

// MARK: - Button guide (the legend)

struct ButtonGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(GuideSection.all) { section in
                    Section(header: Text(section.title)) {
                        ForEach(section.items) { item in
                            GuideRow(help: item)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Guia dos botões")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct GuideRow: View {
    let help: ControlHelp

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if help.id == "colors" {
                ColorKeysIcon()
            } else {
                HelpIcon(help: help, size: 32)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(help.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    if let tip = help.tip {
                        TipBadge(text: tip)
                    }
                }
                Text(help.detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ColorKeysIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8.5)
            .fill(Color(white: 0.22))
            .frame(width: 32, height: 32)
            .overlay(
                VStack(spacing: 3) {
                    HStack(spacing: 3) { dot(Help.red.tint); dot(Help.green.tint) }
                    HStack(spacing: 3) { dot(Help.yellow.tint); dot(Help.blue.tint) }
                }
            )
    }

    private func dot(_ color: Color?) -> some View {
        Circle().fill(color ?? .gray).frame(width: 8, height: 8)
    }
}
