import Foundation
import CommonCrypto
import CryptoKit

// MARK: - Segway-Ninebot "Encryption2" session crypto (v5.1, EXPERIMENTAL, UNTESTED ON HARDWARE)
//
// HackTheScoot's OWN clean-room implementation, written only from the Apache-2.0
// "Segway-Ninebot BLE Protocol" specification by NootNooot
// (https://codeberg.org/nootnooot/segway-ninebot-ble, pages "Encryption" and
// "Authentication"). Licensed to us under the Apache License 2.0; see ACKNOWLEDGEMENTS.md
// and NOTICE. Changes from the spec: none intended; the code below is ours.
//
// NOT derived from scooterhacking/NinebotCrypto (AGPL-3.0). Nobody writing this file
// read that code.
//
// What it is: AES-128 in a CCM-like mode (CTR keystream + 4-byte CBC-MAC tag, 16-bit
// counter on the wire), key = first 16 bytes of SHA-1(key1 ‖ key2).
// Before pairing finishes ("non-SN mode") a simpler static keystream + checksum is used.
//
// Nothing in here is a secret: the session password is made fresh on the phone during
// pairing and kept in the iOS Keychain only (never in code, logs or exports).

enum NBCrypto {

    /// One AES-128 block (ECB on 16 bytes, no padding).
    static func aesBlock(key: [UInt8], _ block: [UInt8]) -> [UInt8] {
        guard key.count == 16, block.count == 16 else { return [UInt8](repeating: 0, count: 16) }
        let outLength = 32
        var out = [UInt8](repeating: 0, count: outLength)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                             key, 16, nil, block, 16, &out, outLength, &moved)
        guard status == CCCryptorStatus(kCCSuccess), moved >= 16 else { return [UInt8](repeating: 0, count: 16) }
        return Array(out[0..<16])
    }

    static func sha1(_ bytes: [UInt8]) -> [UInt8] {
        return Array(Insecure.SHA1.hash(data: Data(bytes)))
    }

    static func pad16(_ b: [UInt8]?) -> [UInt8] {
        guard let b = b, !b.isEmpty else { return [UInt8](repeating: 0, count: 16) }
        return Array((b + [UInt8](repeating: 0, count: 16)).prefix(16))
    }

    /// aes_key = SHA-1(key1 padded to 16 ‖ key2 padded to 16, or 16 zeros)[0..<16]
    static func deriveKey(_ key1: [UInt8], _ key2: [UInt8]?) -> [UInt8] {
        return Array(sha1(pad16(key1) + pad16(key2)).prefix(16))
    }

    /// nonce[13] = counter (4 bytes, big-endian) ‖ auth[0..<8] ‖ 0x00
    static func nonce(counter: UInt32, auth: [UInt8]) -> [UInt8] {
        let c: [UInt8] = [UInt8((counter >> 24) & 0xFF), UInt8((counter >> 16) & 0xFF), UInt8((counter >> 8) & 0xFF), UInt8(counter & 0xFF)]
        return c + Array(pad16(auth).prefix(8)) + [0x00]
    }

    static func xor(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        return zip(a, b).map { $0 ^ $1 }
    }

    /// CTR block A_i = 01 ‖ nonce ‖ 00 ‖ i
    static func ctrBlock(_ nonce: [UInt8], _ i: Int) -> [UInt8] {
        return [0x01] + nonce + [0x00, UInt8(i & 0xFF)]
    }

    /// 4-byte CBC-MAC over the whole plaintext frame (3-byte header as associated data).
    static func cbcMac(key: [UInt8], plain: [UInt8], nonce: [UInt8]) -> [UInt8] {
        guard plain.count >= 3 else { return [0, 0, 0, 0] }
        let payload = Array(plain[3...])
        var x = aesBlock(key: key, [0x59] + nonce + [0x00, UInt8(payload.count & 0xFF)])
        x = aesBlock(key: key, xor(x, Array(plain[0..<3]) + [UInt8](repeating: 0, count: 13)))
        var off = 0
        while off < payload.count {
            var chunk = Array(payload[off..<min(off + 16, payload.count)])
            chunk += [UInt8](repeating: 0, count: 16 - chunk.count)
            x = aesBlock(key: key, xor(x, chunk))
            off += 16
        }
        return Array(x.prefix(4))
    }

    static func ctrApply(key: [UInt8], nonce: [UInt8], _ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        var i = 1
        var off = 0
        while off < data.count {
            let ks = aesBlock(key: key, ctrBlock(nonce, i))
            let end = min(off + 16, data.count)
            for j in off..<end { out.append(data[j] ^ ks[j - off]) }
            off += 16
            i += 1
        }
        return out
    }

    /// SN mode (after PRE_COMM): header ‖ CTR(payload) ‖ enc tag(4) ‖ counter (2, BE).
    static func encryptSN(key: [UInt8], plain: [UInt8], counter: UInt32, auth: [UInt8]) -> [UInt8] {
        guard plain.count >= 3 else { return plain }
        let n = nonce(counter: counter, auth: auth)
        let tag = cbcMac(key: key, plain: plain, nonce: n)
        let ct = ctrApply(key: key, nonce: n, Array(plain[3...]))
        let a0 = aesBlock(key: key, ctrBlock(n, 0))
        let encTag = xor(tag, Array(a0.prefix(4)))
        return Array(plain[0..<3]) + ct + encTag + [UInt8((counter >> 8) & 0xFF), UInt8(counter & 0xFF)]
    }

    /// Inverted 16-bit sum.
    static func checksum16(_ b: [UInt8]) -> UInt16 {
        let total = b.reduce(0) { $0 + Int($1) }
        return UInt16(~total & 0xFFFF)
    }

    /// Non-SN mode (PRE_COMM): every 16-byte block XORed with ONE static keystream block
    /// AES(key, staticBlock), tail = 00 00 cs_lo cs_hi 00 00.
    static func encryptNonSN(key: [UInt8], plain: [UInt8], staticBlock: [UInt8]) -> [UInt8] {
        guard plain.count >= 3 else { return plain }
        let payload = Array(plain[3...])
        let ks = aesBlock(key: key, pad16(staticBlock))
        var ct: [UInt8] = []
        for (i, b) in payload.enumerated() { ct.append(b ^ ks[i % 16]) }
        let cs = checksum16(payload)
        return Array(plain[0..<3]) + ct + [0x00, 0x00, UInt8(cs & 0xFF), UInt8(cs >> 8), 0x00, 0x00]
    }

    enum Decrypted: Equatable {
        case ok(plain: [UInt8], counter: UInt16)
        case badLength
        case badMac
        case badChecksum
    }

    /// Decrypts one whole frame (LEN + 13 bytes). A tail counter of 0 means non-SN mode.
    static func decrypt(key: [UInt8], frame: [UInt8], auth: [UInt8], staticBlock: [UInt8]) -> Decrypted {
        guard frame.count >= 13, frame.count == Int(frame[2]) + 13 else { return .badLength }
        let header = Array(frame[0..<3])
        let body = Array(frame[3..<(frame.count - 6)])
        let tail = Array(frame[(frame.count - 6)...])
        let counter = (UInt16(tail[4]) << 8) | UInt16(tail[5])
        if counter == 0 {
            let ks = aesBlock(key: key, pad16(staticBlock))
            var pt: [UInt8] = []
            for (i, b) in body.enumerated() { pt.append(b ^ ks[i % 16]) }
            let cs = checksum16(pt)
            guard tail[2] == UInt8(cs & 0xFF), tail[3] == UInt8(cs >> 8) else { return .badChecksum }
            return .ok(plain: header + pt, counter: 0)
        }
        let n = nonce(counter: UInt32(counter), auth: auth)
        let pt = ctrApply(key: key, nonce: n, body)
        let a0 = aesBlock(key: key, ctrBlock(n, 0))
        let gotTag = xor(Array(tail[0..<4]), Array(a0.prefix(4)))
        guard gotTag == cbcMac(key: key, plain: header + pt, nonce: n) else { return .badMac }
        return .ok(plain: header + pt, counter: counter)
    }
}

/// The key material of one session, as it changes through pairing.
struct NBCryptoSession: Equatable {
    /// key1: the BLE name during PRE_COMM / SET_PWD, then the session password.
    var key1: [UInt8]
    /// key2: nothing during PRE_COMM, then the device's 16-byte auth parameter.
    var key2: [UInt8]?
    var auth: [UInt8] = []
    /// The ECB input of the non-SN keystream: the spec's fixed Gen2 protocol constant, or
    /// 16 zeros (Gen3). Not a secret (see the spec's "fw_data" section).
    var staticBlock: [UInt8]
    /// 0 = non-SN mode. start() sets 1; the first SN frame then goes out with counter 2.
    var counter: UInt32 = 0
    var lastRxCounter: UInt16 = 0

    init(bleName: String, staticBlock: [UInt8]) {
        key1 = Array(bleName.utf8)
        key2 = nil
        self.staticBlock = staticBlock
    }

    var key: [UInt8] { return NBCrypto.deriveKey(key1, key2) }
    var snMode: Bool { return counter > 0 }

    mutating func startSN(auth: [UInt8]) {
        self.auth = auth
        counter = 1
    }

    mutating func encrypt(_ plain: [UInt8]) -> [UInt8] {
        if counter == 0 { return NBCrypto.encryptNonSN(key: key, plain: plain, staticBlock: staticBlock) }
        counter &+= 1
        if counter > 0xFFFF { counter = 2 }
        return NBCrypto.encryptSN(key: key, plain: plain, counter: counter, auth: auth)
    }

    mutating func decrypt(_ frame: [UInt8]) -> NBCrypto.Decrypted {
        let r = NBCrypto.decrypt(key: key, frame: frame, auth: auth, staticBlock: staticBlock)
        if case .ok(_, let c) = r, c > 0 { lastRxCounter = c }
        return r
    }
}
