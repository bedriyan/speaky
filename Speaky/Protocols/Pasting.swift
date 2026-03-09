import Foundation

enum PasteResult {
    case pasted
    case clipboardOnly
    case skipped
}

/// Abstraction over clipboard paste operations for testability.
protocol Pasting: AnyObject {
    @discardableResult
    func paste(_ text: String) -> PasteResult
}

extension PasteService: Pasting {}
