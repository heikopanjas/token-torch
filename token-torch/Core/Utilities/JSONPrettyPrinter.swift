import Foundation

/// Re-indents JSON by rewriting whitespace only. Unlike `JSONSerialization`, every token stays
/// byte-for-byte intact, so key order, number spelling (`2.0` vs `2`), and string escapes survive.
public enum JSONPrettyPrinter {
    private static let quote = UInt8(ascii: "\"")
    private static let backslash = UInt8(ascii: "\\")
    private static let comma = UInt8(ascii: ",")
    private static let colon = UInt8(ascii: ":")
    private static let space = UInt8(ascii: " ")
    private static let newline = UInt8(ascii: "\n")
    private static let openers: Set<UInt8> = [UInt8(ascii: "{"), UInt8(ascii: "[")]
    private static let closers: Set<UInt8> = [UInt8(ascii: "}"), UInt8(ascii: "]")]
    private static let whitespace: Set<UInt8> = [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r")]

    public static func prettyPrinted(_ json: Data, indentWidth: Int = 2) -> Data {
        var output = Data()
        output.reserveCapacity(json.count * 2)
        var depth = 0
        var isInString = false
        var isEscaped = false
        var isAfterOpener = false

        for byte in json {
            if isInString == true {
                output.append(byte)
                if isEscaped == true {
                    isEscaped = false
                }
                else if byte == Self.backslash {
                    isEscaped = true
                }
                else if byte == Self.quote {
                    isInString = false
                }
                continue
            }
            if Self.whitespace.contains(byte) == true {
                continue
            }
            if isAfterOpener == true {
                isAfterOpener = false
                // An empty container stays on one line: `{}` / `[]`.
                if Self.closers.contains(byte) == true {
                    depth -= 1
                    output.append(byte)
                    continue
                }
                Self.appendLineBreak(to: &output, depth: depth, indentWidth: indentWidth)
            }

            if Self.openers.contains(byte) == true {
                output.append(byte)
                depth += 1
                isAfterOpener = true
            }
            else if Self.closers.contains(byte) == true {
                depth -= 1
                Self.appendLineBreak(to: &output, depth: depth, indentWidth: indentWidth)
                output.append(byte)
            }
            else if byte == Self.comma {
                output.append(byte)
                Self.appendLineBreak(to: &output, depth: depth, indentWidth: indentWidth)
            }
            else if byte == Self.colon {
                output.append(byte)
                output.append(Self.space)
            }
            else {
                if byte == Self.quote {
                    isInString = true
                }
                output.append(byte)
            }
        }
        output.append(Self.newline)
        return output
    }

    private static func appendLineBreak(to output: inout Data, depth: Int, indentWidth: Int) -> Void {
        output.append(Self.newline)
        output.append(contentsOf: repeatElement(Self.space, count: max(0, depth) * indentWidth))
    }
}
