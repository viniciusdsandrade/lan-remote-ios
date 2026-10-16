import Foundation

// MARK: - TV Key Codes (ROAP Protocol)

enum TVKey: Int, CaseIterable, Identifiable, Sendable {
    case power = 1
    case digit0 = 2, digit1 = 3, digit2 = 4, digit3 = 5, digit4 = 6
    case digit5 = 7, digit6 = 8, digit7 = 9, digit8 = 10, digit9 = 11
    case up = 12, down = 13, left = 14, right = 15, ok = 20
    case home = 21, menu = 22, back = 23, exit = 412
    case volumeUp = 24, volumeDown = 25, mute = 26
    case channelUp = 27, channelDown = 28, previousChannel = 403, favoriteChannel = 404
    case blue = 29, green = 30, red = 31, yellow = 32
    case play = 33, pause = 34, stop = 35, fastForward = 36, rewind = 37
    case skipForward = 38, skipBackward = 39, record = 40, recordingList = 41, repeatKey = 42
    case liveTv = 43, epg = 44, info = 45, aspectRatio = 46, input = 47
    case pip = 48, subtitle = 49, programList = 50, teletext = 51, mark = 52
    case key3d = 400, key3dLr = 401, dash = 402, quickMenu = 405, textOption = 406
    case audioDescription = 407, netcast = 408, energySaving = 409, avMode = 410
    case simplink = 411, reservationList = 413, pipChannelUp = 414, pipChannelDown = 415
    case switchVideo = 416, apps = 417
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .power: return "Power"
        case .digit0: return "0"
        case .digit1: return "1"
        case .digit2: return "2"
        case .digit3: return "3"
        case .digit4: return "4"
        case .digit5: return "5"
        case .digit6: return "6"
        case .digit7: return "7"
        case .digit8: return "8"
        case .digit9: return "9"
        case .up: return "Cima"
        case .down: return "Baixo"
        case .left: return "Esquerda"
        case .right: return "Direita"
        case .ok: return "OK"
        case .home: return "Home"
        case .menu: return "Menu"
        case .back: return "Voltar"
        case .exit: return "Sair"
        case .volumeUp: return "Vol +"
        case .volumeDown: return "Vol -"
        case .mute: return "Mudo"
        case .channelUp: return "Canal +"
        case .channelDown: return "Canal -"
        case .previousChannel: return "Canal Ant."
        case .favoriteChannel: return "Favoritos"
        case .blue: return "Azul"
        case .green: return "Verde"
        case .red: return "Vermelho"
        case .yellow: return "Amarelo"
        case .play: return "Play"
        case .pause: return "Pause"
        case .stop: return "Stop"
        case .fastForward: return "Avançar"
        case .rewind: return "Retroceder"
        case .liveTv: return "Live TV"
        case .epg: return "Guia"
        case .info: return "Info"
        case .aspectRatio: return "Formato"
        case .input: return "Entrada"
        case .key3d: return "3D"
        case .quickMenu: return "Q.Menu"
        case .apps: return "Apps"
        case .energySaving: return "Eco"
        case .simplink: return "SIMPLINK"
        default: return "Tecla \(rawValue)"
        }
    }
    
    var iconName: String? {
        switch self {
        case .power: return "power"
        case .up: return "triangle.fill"
        case .down: return "triangle.fill"
        case .left: return "triangle.fill"
        case .right: return "triangle.fill"
        case .home: return "house.fill"
        case .menu: return "line.3.horizontal"
        case .back: return "arrowshape.turn.up.backward.fill"
        case .exit: return "xmark.circle.fill"
        case .volumeUp: return "plus"
        case .volumeDown: return "minus"
        case .mute: return "speaker.slash.fill"
        case .channelUp: return "chevron.up"
        case .channelDown: return "chevron.down"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .stop: return "stop.fill"
        case .fastForward: return "forward.fill"
        case .rewind: return "backward.fill"
        case .input: return "tv.and.mediabox"
        case .info: return "info.circle"
        case .quickMenu: return "slider.horizontal.3"
        case .apps: return "square.grid.2x2.fill"
        default: return nil
        }
    }
    
    var isDigit: Bool {
        return rawValue >= TVKey.digit0.rawValue && rawValue <= TVKey.digit9.rawValue
    }
}
