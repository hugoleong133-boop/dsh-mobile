import Foundation
import UIKit

/// 文字 → Windows VK 码转换，逐字符发 KeyDown/KeyUp（含 Shift 处理）。
enum KeyboardBridge {

    /// 单字符 → (VK 码, 是否需要 Shift)。
    static func vkAndShift(for ch: Character) -> (UInt16, Bool)? {
        // 大写字母
        if let scalar = ch.unicodeScalars.first, scalar.value >= 0x41, scalar.value <= 0x5A {
            return (UInt16(scalar.value), false)
        }
        // 小写字母 → 大写 VK
        if let scalar = ch.unicodeScalars.first, scalar.value >= 0x61, scalar.value <= 0x7A {
            return (UInt16(scalar.value - 0x20), false)
        }
        // 数字
        if let scalar = ch.unicodeScalars.first, scalar.value >= 0x30, scalar.value <= 0x39 {
            return (UInt16(scalar.value), false)
        }
        // Shift + 数字 = 符号
        let shifted: [Character: UInt16] = [
            "!": 0x31, "@": 0x32, "#": 0x33, "$": 0x34, "%": 0x35,
            "^": 0x36, "&": 0x37, "*": 0x38, "(": 0x39, ")": 0x30,
        ]
        if let vk = shifted[ch] { return (vk, true) }

        // 常用符号
        switch ch {
        case " ":  return (0x20, false)
        case "\n": return (0x0D, false)
        case "\t": return (0x09, false)
        case "-":  return (0xBD, false)
        case "_":  return (0xBD, true)
        case "=":  return (0xBB, false)
        case "+":  return (0xBB, true)
        case "[":  return (0xDB, false)
        case "{":  return (0xDB, true)
        case "]":  return (0xDD, false)
        case "}":  return (0xDD, true)
        case "\\": return (0xDC, false)
        case "|":  return (0xDC, true)
        case ";":  return (0xBA, false)
        case ":":  return (0xBA, true)
        case "'":  return (0xDE, false)
        case "\"": return (0xDE, true)
        case ",":  return (0xBC, false)
        case "<":  return (0xBC, true)
        case ".":  return (0xBE, false)
        case ">":  return (0xBE, true)
        case "/":  return (0xBF, false)
        case "?":  return (0xBF, true)
        case "`":  return (0xC0, false)
        case "~":  return (0xC0, true)
        default:   return nil   // 非 ASCII（中文等）不支持逐键，走剪贴板粘贴
        }
    }

    /// 整段文字逐键发送。非 ASCII 字符跳过（提示用剪贴板）。
    static func sendText(_ text: String, session: Session) {
        for ch in text {
            guard let (vk, needShift) = vkAndShift(for: ch) else { continue }
            if needShift { session.sendKey(vk: 0x10, down: true) }
            session.sendKey(vk: vk, down: true)
            session.sendKey(vk: vk, down: false)
            if needShift { session.sendKey(vk: 0x10, down: false) }
            // 键间隔，避免被控端丢键
            usleep(8000)
        }
    }

    /// 发送控制键组合（如 Ctrl+C / Ctrl+V）。
    static func sendCombo(_ vks: [UInt16], session: Session) {
        for vk in vks { session.sendKey(vk: vk, down: true) }
        // 逆序抬起
        for vk in vks.reversed() { session.sendKey(vk: vk, down: false) }
    }
}
