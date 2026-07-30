//
//  UntitledScriptTitle.swift
//  ShuoCore
//
//  Created by Justin Chow on 30/07/26.
//

import Foundation

/// The naming scheme for a script the user never titled: `Untitled Script 1`,
/// `Untitled Script 2`, and so on.
///
/// Lives in the domain rather than in a Feature package because two of them need it and
/// neither may depend on the other (CLAUDE.md §4): Input Script mints the name, and the
/// analysis screen restores it when the user clears the title field. It replaces a private
/// `static let untitledTitle` that was duplicated in both view models — a name that has to
/// be *recognised* as generated, not just written, cannot survive being defined twice.
public enum UntitledScriptTitle {
    /// The unnumbered stem every generated name is built from.
    ///
    /// Not itself a legal generated name — numbering starts at 1, so there is exactly one
    /// format to produce and to parse.
    public static let prefix = "Untitled Script"

    /// The name given when nothing numbered is stored yet.
    public static var first: String {
        named(1)
    }

    /// The generated name for `number`.
    public static func named(_ number: Int) -> String {
        "\(prefix) \(number)"
    }

    /// The number in `title`, or `nil` when `title` is not a name this type produced.
    ///
    /// Deliberately strict — exactly the stem, one space, then ASCII digits — and
    /// case-sensitive, so only the app's own names influence numbering. A user who titles
    /// a script "Untitled Script ideas", "untitled script 4", or plain "Untitled Script"
    /// owns that name and is left alone by both `next(after:)` and `isGenerated(_:)`.
    ///
    /// The digit count is bounded so that a hand-edited or imported title cannot overflow
    /// the `+ 1` in `next(after:)`; anything longer is not a name this type wrote.
    public static func number(in title: String) -> Int? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }

        let remainder = trimmed.dropFirst(prefix.count)
        guard remainder.hasPrefix(" ") else { return nil }

        let digits = remainder.dropFirst()
        guard !digits.isEmpty, digits.count <= 18,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(digits), number > 0
        else { return nil }

        return number
    }

    /// True when `title` is a name this type produced.
    ///
    /// This is how callers tell "never named" apart from "named that on purpose" — the
    /// distinction Input Script needs so that stepping back from analysis does not paste a
    /// placeholder into the title field as if the user had typed it.
    public static func isGenerated(_ title: String) -> Bool {
        number(in: title) != nil
    }

    /// The next name after every generated name in `titles`: the highest number found plus
    /// one, or `first` when there are none.
    ///
    /// Highest-plus-one rather than lowest-unused, so a number freed by a rename or a
    /// deletion is never handed out a second time — two scripts that were both called
    /// `Untitled Script 3` at different times would be indistinguishable in the library.
    public static func next(after titles: some Sequence<String>) -> String {
        let highest = titles.compactMap { number(in: $0) }.max() ?? 0
        return named(highest + 1)
    }
}
