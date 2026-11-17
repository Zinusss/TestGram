import Foundation
import SwiftSignalKit
import AudioToolbox
import AppBundle

private func loadSystemSoundFromBundle(name: String) -> SystemSoundID? {
    let bundle = getAppBundle()
    let mainBundle = Bundle.main
    var url: URL?
    
    if let path = bundle.path(forResource: name, ofType: nil) {
        url = URL(fileURLWithPath: path)
    } else if let path = mainBundle.path(forResource: name, ofType: nil) {
        url = URL(fileURLWithPath: path)
    } else if let path = bundle.path(forResource: "Sounds/\(name)", ofType: nil) ?? mainBundle.path(forResource: "Sounds/\(name)", ofType: nil) {
        url = URL(fileURLWithPath: path)
    } else {
        for fb in Bundle.allFrameworks {
            if let path = fb.path(forResource: name, ofType: nil) ?? fb.path(forResource: "Sounds/\(name)", ofType: nil) {
                url = URL(fileURLWithPath: path)
                break
            }
        }
    }
    
    if let url = url {
        var sound: SystemSoundID = 0
        if AudioServicesCreateSystemSoundID(url as CFURL, &sound) == noErr {
            return sound
        }
    }
    return nil
}

public final class ServiceSoundManager {
    private let queue = Queue()
    private var messageDeliverySound: SystemSoundID?
    private var incomingMessageSound: SystemSoundID?
    
    init() {
        self.queue.async {
            self.messageDeliverySound = loadSystemSoundFromBundle(name: "MessageSent.mp3")
            self.incomingMessageSound = loadSystemSoundFromBundle(name: "notification.mp3")
        }
    }
    
    public func playMessageDeliveredSound() {
        self.queue.async {
            if let messageDeliverySound = self.messageDeliverySound {
                AudioServicesPlaySystemSound(messageDeliverySound)
            }
        }
    }
    
    public func playIncomingMessageSound() {
        self.queue.async {
            if let incomingMessageSound = self.incomingMessageSound {
                AudioServicesPlaySystemSound(incomingMessageSound)
            }
        }
    }
    
    public func playVibrationSound() {
        self.queue.async {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
    
    public func playLockSound() {
        self.queue.async {
            AudioServicesPlaySystemSound(1100)
        }
    }
}

public let serviceSoundManager = ServiceSoundManager()
