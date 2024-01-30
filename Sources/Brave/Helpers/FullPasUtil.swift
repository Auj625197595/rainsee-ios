//
//  File.swift
//  
//
//  Created by jinjian on 2024/1/20.
//

import Foundation
import CommonCrypto

class FullPasUtil {
    public static func base64Decode(encodedString: String) -> Data? {
        if let data = Data(base64Encoded: encodedString) {
            return data
        } else {
            print("Base64 decoding failed.")
            return nil
        }
    }
    public static func decryptAES(input: String, key: String) -> String? {
        let keyData = key.data(using: .utf8)!
        let inputData = Data(base64Encoded: input, options: [])!

        var outputData: Data?

        let keyLength = kCCKeySizeAES128
        let dataLength = inputData.count
        var bytesDecrypted = 0

        var cryptStatus: CCCryptorStatus = 0
        var decryptBytes = [UInt8](repeating: 0, count: dataLength + keyLength)

        keyData.withUnsafeBytes { keyBytes in
            inputData.withUnsafeBytes { dataBytes in
                cryptStatus = CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyBytes.baseAddress,
                    keyLength,
                    nil,
                    dataBytes.baseAddress,
                    dataLength,
                    &decryptBytes,
                    dataLength + keyLength,
                    &bytesDecrypted
                )
            }
        }

        if cryptStatus == kCCSuccess {
            // Remove PKCS7 padding
            decryptBytes.removeLast(keyLength - (dataLength % keyLength))

            outputData = Data(bytes: decryptBytes, count: bytesDecrypted)
            return String(data: outputData!, encoding: .utf8)
        } else {
            print("Error in decryption: \(cryptStatus)")
            return nil
        }
    }
}
