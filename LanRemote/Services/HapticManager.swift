import UIKit

// MARK: - Haptic Feedback Manager

@MainActor
final class HapticManager {
    static let shared = HapticManager()
    
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    
    private init() {
        prepareAll()
    }
    
    func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        notification.prepare()
        selection.prepare()
    }
    
    func buttonPress() {
        mediumImpact.impactOccurred()
    }
    
    func directionTap() {
        rigidImpact.impactOccurred()
    }
    
    func okTap() {
        heavyImpact.impactOccurred()
    }
    
    func powerTap() {
        heavyImpact.impactOccurred(intensity: 1.0)
    }
    
    func rockerTap() {
        mediumImpact.impactOccurred()
    }
    
    func digitTap() {
        lightImpact.impactOccurred()
    }
    
    func selectionChanged() {
        selection.selectionChanged()
    }
    
    func success() {
        notification.notificationOccurred(.success)
    }
    
    func error() {
        notification.notificationOccurred(.error)
    }
    
    func warning() {
        notification.notificationOccurred(.warning)
    }
}
