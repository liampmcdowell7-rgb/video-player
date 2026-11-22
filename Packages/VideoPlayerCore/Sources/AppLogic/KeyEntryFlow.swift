/// R364 (compile run of 21 Nov 2026, item 12; made testable by R378): the rules of a key row in Settings > Online Lookup
/// (App/Features/Settings/OnlineLookupSettingsView.swift, `KeyRow`). Done on the key's entry page saves the key; there is
/// no Save Key button. Back without Done saves nothing (the entry page calls the row only on Done, TextEntryPage).
public enum KeyEntryFlow {
    /// The footer line after a save or a removal (rule L3: a result is footer text, not a row).
    public static let savedMessage = "Key saved."
    public static let removedMessage = "Key removed."

    /// Done saves when something was typed and no save is already running.
    public static func savesOnDone(entered: String, working: Bool) -> Bool {
        !entered.isEmpty && !working
    }

    /// The entry row's title: Enter Key without a saved key, Replace Key with one.
    public static func entryTitle(hasKey: Bool) -> String {
        hasKey ? OnlineLookupText.replaceKey : OnlineLookupText.enterKey
    }

    /// The service row's value: On with a saved key, Not set without one.
    public static func status(hasKey: Bool) -> String {
        hasKey ? OnlineLookupText.keyOn : OnlineLookupText.keyNotSet
    }

    /// The section footer: the last result first, then the service's help sentence.
    public static func footer(message: String?, help: String) -> String {
        message.map { $0 + " " + help } ?? help
    }
}
