import AppKit

// MARK: - AppKitCommandSelectors

enum AppKitCommandSelectors {
    static let insertNewline = #selector(NSResponder.insertNewline(_:))
    static let insertLineBreak = #selector(NSResponder.insertLineBreak(_:))
    static let insertNewlineIgnoringFieldEditor =
        #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
    static let insertTab = #selector(NSResponder.insertTab(_:))
    static let insertBacktab = #selector(NSResponder.insertBacktab(_:))
    static let deleteBackward = #selector(NSResponder.deleteBackward(_:))
    static let deleteForward = #selector(NSResponder.deleteForward(_:))
    static let deleteToBeginningOfLine = #selector(NSResponder.deleteToBeginningOfLine(_:))
    static let deleteWordBackward = #selector(NSResponder.deleteWordBackward(_:))
    static let moveUp = #selector(NSResponder.moveUp(_:))
    static let moveDown = #selector(NSResponder.moveDown(_:))
    static let moveLeft = #selector(NSResponder.moveLeft(_:))
    static let moveRight = #selector(NSResponder.moveRight(_:))
    static let moveToBeginningOfLine = #selector(NSResponder.moveToBeginningOfLine(_:))
    static let moveToEndOfLine = #selector(NSResponder.moveToEndOfLine(_:))
    static let moveToBeginningOfLineAndModifySelection =
        #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:))
    static let moveToEndOfLineAndModifySelection =
        #selector(NSResponder.moveToEndOfLineAndModifySelection(_:))
    static let moveWordLeft = #selector(NSResponder.moveWordLeft(_:))
    static let moveWordRight = #selector(NSResponder.moveWordRight(_:))
    static let moveWordLeftAndModifySelection =
        #selector(NSResponder.moveWordLeftAndModifySelection(_:))
    static let moveWordRightAndModifySelection =
        #selector(NSResponder.moveWordRightAndModifySelection(_:))
    static let moveLeftAndModifySelection =
        #selector(NSResponder.moveLeftAndModifySelection(_:))
    static let moveRightAndModifySelection =
        #selector(NSResponder.moveRightAndModifySelection(_:))
    static let moveUpAndModifySelection = #selector(NSResponder.moveUpAndModifySelection(_:))
    static let moveDownAndModifySelection =
        #selector(NSResponder.moveDownAndModifySelection(_:))
    static let cancelOperation = #selector(NSResponder.cancelOperation(_:))
    static let selectAll = #selector(NSResponder.selectAll(_:))
    static let copy = NSSelectorFromString("copy:")
    static let cut = NSSelectorFromString("cut:")
    static let paste = NSSelectorFromString("paste:")
    static let undo = NSSelectorFromString("undo:")
    static let redo = NSSelectorFromString("redo:")
}

// MARK: - AppKitKeyCode

enum AppKitKeyCode {
    static let a: UInt16 = 0
    static let z: UInt16 = 6
    static let x: UInt16 = 7
    static let c: UInt16 = 8
    static let v: UInt16 = 9
    static let `return`: UInt16 = 36
    static let tab: UInt16 = 48
    static let delete: UInt16 = 51
    static let keypadEnter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

// MARK: - Keyboard Mapping

enum AppKitKeyboardCommandMapper {
    static func commandSelector(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> Selector? {
        if isAKey(event), modifiers == .command {
            return AppKitCommandSelectors.selectAll
        }
        if isCKey(event), modifiers == .command {
            return AppKitCommandSelectors.copy
        }
        if isXKey(event), modifiers == .command {
            return AppKitCommandSelectors.cut
        }
        if isVKey(event), modifiers == .command {
            return AppKitCommandSelectors.paste
        }
        if isZKey(event), modifiers == .command {
            return AppKitCommandSelectors.undo
        }
        if isZKey(event), modifiers == [.command, .shift] {
            return AppKitCommandSelectors.redo
        }

        switch (event.keyCode, modifiers) {
        case (AppKitKeyCode.leftArrow, [.command, .shift]):
            return AppKitCommandSelectors.moveToBeginningOfLineAndModifySelection
        case (AppKitKeyCode.rightArrow, [.command, .shift]):
            return AppKitCommandSelectors.moveToEndOfLineAndModifySelection
        case (AppKitKeyCode.leftArrow, [.option, .shift]):
            return AppKitCommandSelectors.moveWordLeftAndModifySelection
        case (AppKitKeyCode.rightArrow, [.option, .shift]):
            return AppKitCommandSelectors.moveWordRightAndModifySelection
        case (AppKitKeyCode.leftArrow, .command):
            return AppKitCommandSelectors.moveToBeginningOfLine
        case (AppKitKeyCode.rightArrow, .command):
            return AppKitCommandSelectors.moveToEndOfLine
        case (AppKitKeyCode.leftArrow, .option):
            return AppKitCommandSelectors.moveWordLeft
        case (AppKitKeyCode.rightArrow, .option):
            return AppKitCommandSelectors.moveWordRight
        case (AppKitKeyCode.delete, .command):
            return AppKitCommandSelectors.deleteToBeginningOfLine
        case (AppKitKeyCode.delete, .option):
            return AppKitCommandSelectors.deleteWordBackward
        case (AppKitKeyCode.leftArrow, .shift):
            return AppKitCommandSelectors.moveLeftAndModifySelection
        case (AppKitKeyCode.rightArrow, .shift):
            return AppKitCommandSelectors.moveRightAndModifySelection
        case (AppKitKeyCode.upArrow, .shift):
            return AppKitCommandSelectors.moveUpAndModifySelection
        case (AppKitKeyCode.downArrow, .shift):
            return AppKitCommandSelectors.moveDownAndModifySelection
        default:
            return nil
        }
    }

    static func isReturnKey(_ event: NSEvent) -> Bool {
        event.keyCode == AppKitKeyCode.return
            || event.keyCode == AppKitKeyCode.keypadEnter
    }

    static func isTabKey(_ event: NSEvent) -> Bool {
        event.keyCode == AppKitKeyCode.tab
    }

    private static func isAKey(_ event: NSEvent) -> Bool {
        event.keyCode == AppKitKeyCode.a
            || event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    private static func isCKey(_ event: NSEvent) -> Bool {
        event.keyCode == AppKitKeyCode.c
            || event.charactersIgnoringModifiers?.lowercased() == "c"
    }

    private static func isVKey(_ event: NSEvent) -> Bool {
        event.keyCode == AppKitKeyCode.v
            || event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    private static func isXKey(_ event: NSEvent) -> Bool {
        event.keyCode == AppKitKeyCode.x
            || event.charactersIgnoringModifiers?.lowercased() == "x"
    }

    private static func isZKey(_ event: NSEvent) -> Bool {
        event.keyCode == AppKitKeyCode.z
            || event.charactersIgnoringModifiers?.lowercased() == "z"
    }
}
