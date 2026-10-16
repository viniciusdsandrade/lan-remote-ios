import UIKit
import MediaPlayer
import AVFoundation
import Combine

// MARK: - Physical Volume Button Interceptor

@MainActor
final class VolumeButtonHandler: ObservableObject {
    @Published var isListening: Bool = false
    
    private var volumeObserver: NSKeyValueObservation?
    private var lastVolume: Float = 0.5
    private var isAdjustingInternally: Bool = false
    private var hiddenVolumeView: MPVolumeView?
    private var volumeSlider: UISlider?
    
    var onVolumeUp: (() -> Void)?
    var onVolumeDown: (() -> Void)?
    
    init() {
        setupHiddenVolumeView()
    }
    
    deinit {
        volumeObserver?.invalidate()
    }
    
    private func setupHiddenVolumeView() {
        // Invisible MPVolumeView prevents the system volume HUD from popping up
        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView.clipsToBounds = true
        volumeView.alpha = 0.001
        self.hiddenVolumeView = volumeView
        
        // Find slider to programmatically recenter volume
        for subview in volumeView.subviews {
            if let slider = subview as? UISlider {
                self.volumeSlider = slider
                break
            }
        }
    }
    
    func startListening() {
        guard !isListening else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("VolumeButtonHandler: AVAudioSession activation failed: \(error)")
        }
        
        lastVolume = AVAudioSession.sharedInstance().outputVolume
        
        // Center the volume if too close to boundaries so button presses register
        if lastVolume <= 0.05 || lastVolume >= 0.95 {
            recenterVolume(to: 0.5)
            lastVolume = 0.5
        }
        
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, change in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard !self.isAdjustingInternally else { return }
                
                guard let newVolume = change.newValue else { return }
                let diff = newVolume - self.lastVolume
                
                if abs(diff) > 0.001 {
                    if diff > 0 {
                        self.onVolumeUp?()
                    } else {
                        self.onVolumeDown?()
                    }
                    
                    self.lastVolume = newVolume
                    
                    // If volume gets near edges, reset to 0.5 after brief delay
                    if newVolume <= 0.05 || newVolume >= 0.95 {
                        self.recenterVolume(to: 0.5)
                        self.lastVolume = 0.5
                    }
                }
            }
        }
        
        isListening = true
    }
    
    func stopListening() {
        volumeObserver?.invalidate()
        volumeObserver = nil
        isListening = false
    }
    
    private func recenterVolume(to target: Float) {
        isAdjustingInternally = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.volumeSlider?.setValue(target, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.isAdjustingInternally = false
            }
        }
    }
    
    // Attaches the hidden volume view to a host window or view
    func attachHiddenView(to parentView: UIView) {
        if let view = hiddenVolumeView, view.superview == nil {
            parentView.addSubview(view)
        }
    }
}
