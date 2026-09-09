import AppKit
import SwiftTerm

public enum TerminalPrototype {
    public static func verifyFontDiscovery() -> (font: NSFont, matchedName: String) {
        let preferredFamilies = [
            "JetBrainsMono Nerd Font Mono",
            "JetBrains Mono Nerd Font Mono",
            "JetBrainsMonoNL Nerd Font Mono",
            "JetBrainsMono Nerd Font",
            "Menlo"
        ]
        
        let fontManager = NSFontManager.shared
        for family in preferredFamilies {
            if let font = fontManager.font(withFamily: family, traits: [], weight: 5, size: 13) {
                return (font, family)
            }
        }
        return (NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), "SystemMonospaced")
    }
    
    public static func verifyTerminalInstantiation() -> Bool {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        let termView = LocalProcessTerminalView(frame: frame)
        let (font, name) = verifyFontDiscovery()
        termView.font = font
        print("Terminal instantiated with font: \(name) (\(font.fontName))")
        return true
    }
}
