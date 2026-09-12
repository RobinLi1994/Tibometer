import AppKit
import TibometerCore

@MainActor
enum ApplicationMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "Tibometer")
        appMenu.addItem(withTitle: L10n.text("common.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(withTitle: "Tibometer", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: L10n.text("edit.title"))
        edit.addItem(withTitle: L10n.text("edit.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.text("edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.text("edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.text("edit.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(withTitle: edit.title, action: nil, keyEquivalent: "").submenu = edit
        return menu
    }
}
