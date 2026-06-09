import AppKit
import Foundation

enum SoundEffectPlayer {
    enum Effect: String {
        case contextAttached
        case chatOpened

        var resourceBaseNames: [String] {
            switch self {
            case .contextAttached:
                ["collect", "context-attached"]
            case .chatOpened:
                ["chat", "chat-opened"]
            }
        }

        static let supportedExtensions = ["caf", "aiff", "wav", "mp3"]
    }

    static func play(_ effect: Effect) {
        guard isSystemUISoundEnabled, isAppSoundEnabled else { return }
        guard let sound = loadSound(for: effect) else { return }

        sound.volume = 0.65
        sound.play()
    }

    static var isSystemUISoundEnabled: Bool {
        if let enabled = CFPreferencesCopyAppValue("com.apple.sound.uiaudio.enabled" as CFString, kCFPreferencesAnyUser) as? Bool {
            return enabled
        }

        return true
    }

    static var isAppSoundEnabled: Bool {
        AppPreferenceKeys.soundEffectsEnabled
    }

    private static func loadSound(for effect: Effect) -> NSSound? {
        if let cached = cachedSounds[effect] {
            return cached
        }

        guard let url = bundleURL(for: effect) else {
            return nil
        }

        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            return nil
        }

        cachedSounds[effect] = sound
        return sound
    }

    private static var cachedSounds: [Effect: NSSound] = [:]

    private static func bundleURL(for effect: Effect) -> URL? {
        for baseName in effect.resourceBaseNames {
            for fileExtension in Effect.supportedExtensions {
                if let url = Bundle.main.url(
                    forResource: baseName,
                    withExtension: fileExtension,
                    subdirectory: "Resources/Sounds"
                ) {
                    return url
                }

                if let url = Bundle.main.url(forResource: baseName, withExtension: fileExtension) {
                    return url
                }
            }
        }

        return nil
    }
}

enum AppPreferenceKeys {
    static let soundEffectsEnabledKey = "sound-effects-enabled"
    static let hideMainAppOnStartKey = "hide-main-app-on-start"
    static let ocrImagesForLocalModelsKey = "ocr-images-for-local-models"

    static var soundEffectsEnabled: Bool {
        if UserDefaults.standard.object(forKey: soundEffectsEnabledKey) == nil {
            return true
        }

        return UserDefaults.standard.bool(forKey: soundEffectsEnabledKey)
    }

    static var hideMainAppOnStart: Bool {
        UserDefaults.standard.bool(forKey: hideMainAppOnStartKey)
    }

    static var ocrImagesForLocalModels: Bool {
        UserDefaults.standard.bool(forKey: ocrImagesForLocalModelsKey)
    }
}
