import Foundation

public enum DNS {
    // Only an uncompressed, single-question DNS query is accepted. Replies never amplify it.
    public static func reply(to data: Data, blocks: (String) -> Bool) -> Data? {
        let bytes = Array(data)
        guard bytes.count >= 17, bytes.count <= 4096, bytes[2] & 0xf8 == 0, bytes[4] == 0, bytes[5] == 1 else { return nil }
        var index = 12
        var labels: [String] = []
        while index < bytes.count {
            let length = Int(bytes[index]); index += 1
            if length == 0 { break }
            guard length <= 63, index + length < bytes.count, let label = String(bytes: bytes[index..<(index + length)], encoding: .ascii), label.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { return nil }
            labels.append(label.lowercased()); index += length
        }
        guard !labels.isEmpty, index + 4 <= bytes.count, index <= 266, bytes[index + 2] == 0, bytes[index + 3] == 1 else { return nil }
        let denied = blocks(labels.joined(separator: "."))
        var response = Array(bytes.prefix(index + 4))
        response[2] = 0x80 | (bytes[2] & 0x01)
        // NXDOMAIN for blocked names; SERVFAIL for names routed here unexpectedly.
        response[3] = denied ? 0x03 : 0x02
        response[6] = 0; response[7] = 0; response[8] = 0; response[9] = 0; response[10] = 0; response[11] = 0
        return Data(response)
    }
}
