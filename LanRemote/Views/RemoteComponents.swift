import SwiftUI
import UIKit

// MARK: - Remote Button Styles

struct RemoteButtonStyle: ButtonStyle {
    var bg: Color = Color(white: 0.20)
    var fg: Color = Color(white: 0.95)
    var height: CGFloat = 44
    var cornerRadius: CGFloat = 12
    var border: Color = Color(white: 0.28)
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(configuration.isPressed ? bg.opacity(0.65) : bg)
                    .shadow(color: Color.black.opacity(configuration.isPressed ? 0.1 : 0.4), radius: 3, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(configuration.isPressed ? Color.white.opacity(0.3) : border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct PowerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.red.opacity(0.7) : Color(red: 0.78, green: 0.12, blue: 0.12))
                    .shadow(color: Color.red.opacity(0.4), radius: 5, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct ColorKeyStyle: ButtonStyle {
    var color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(configuration.isPressed ? color.opacity(0.7) : color)
            .frame(height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: color.opacity(0.35), radius: 3, y: 1.5)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.07), value: configuration.isPressed)
    }
}

// MARK: - Circular D-Pad Layout

struct DPadView: View {
    let onKey: (TVKey) -> Void
    
    var body: some View {
        ZStack {
            // Outer background disc
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 188, height: 188)
                .shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 4)
                .overlay(Circle().stroke(Color(white: 0.28), lineWidth: 1.5))
            
            // Up
            Button(action: { onKey(.up) }) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(white: 0.9))
                    .frame(width: 70, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .offset(y: -58)
            
            // Down
            Button(action: { onKey(.down) }) {
                Image(systemName: "triangle.fill")
                    .rotationEffect(.degrees(180))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(white: 0.9))
                    .frame(width: 70, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .offset(y: 58)
            
            // Left
            Button(action: { onKey(.left) }) {
                Image(systemName: "triangle.fill")
                    .rotationEffect(.degrees(-90))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(white: 0.9))
                    .frame(width: 50, height: 70)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: -58)
            
            // Right
            Button(action: { onKey(.right) }) {
                Image(systemName: "triangle.fill")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(white: 0.9))
                    .frame(width: 50, height: 70)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 58)
            
            // Center OK button
            Button(action: { onKey(.ok) }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.14, green: 0.42, blue: 0.72), Color(red: 0.08, green: 0.30, blue: 0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.2))
                    
                    Text("OK")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .frame(width: 196, height: 196)
    }
}

// MARK: - Rocker Switch Component (Volume / Channel)

struct RockerSwitchView: View {
    let title: String
    let upKey: TVKey
    let downKey: TVKey
    let onKey: (TVKey) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { onKey(upKey) }) {
                VStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color(white: 0.22))
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            
            Divider()
                .background(Color(white: 0.32))
            
            Button(action: { onKey(downKey) }) {
                VStack(spacing: 3) {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color(white: 0.22))
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .frame(width: 72)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(white: 0.32), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 4, y: 2)
    }
}

// MARK: - Numeric Keypad View

struct NumericKeypadView: View {
    let onKey: (TVKey) -> Void
    
    private let digits: [[TVKey]] = [
        [.digit1, .digit2, .digit3],
        [.digit4, .digit5, .digit6],
        [.digit7, .digit8, .digit9],
        [.dash, .digit0, .previousChannel]
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<digits.count, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(digits[row]) { key in
                        Button(action: { onKey(key) }) {
                            Text(key.label)
                        }
                        .buttonStyle(RemoteButtonStyle(
                            bg: Color(white: 0.24),
                            height: 42,
                            cornerRadius: 10
                        ))
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.16))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 0.26), lineWidth: 1))
        )
    }
}

// MARK: - Hidden Volume View Representable

struct HiddenVolumeViewRepresentable: UIViewRepresentable {
    let handler: VolumeButtonHandler
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        handler.attachHiddenView(to: container)
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
