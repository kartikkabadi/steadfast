import Foundation
import XPC
import LightweightCodeRequirements

public enum RuntimeAuthorization {
    public static func requirement(from text: String) throws -> XPCPeerRequirement {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^cdhash H"[a-fA-F0-9]{40}"$"#, options: .regularExpression) != nil else {
            throw Failure("invalid client runtime signing requirement")
        }
        let hex = text.dropFirst(9).dropLast()
        var bytes = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw Failure("invalid client code hash") }
            bytes.append(byte); index = next
        }
        let requirement = try ProcessCodeRequirement.allOf {
            CodeDirectoryHash(bytes)
            ProcessCodeSigningFlags.isSuperset(of: .isDynamicallyValid)
        }
        return .codeRequirement(requirement)
    }
}
