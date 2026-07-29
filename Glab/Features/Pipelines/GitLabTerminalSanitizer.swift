import Foundation

nonisolated enum GitLabTerminalSanitizer {
    private enum ByteState {
        case ground
        case escape
        case csi
        case osc
        case oscEscape
        case stringControl
        case stringControlEscape
    }

    private enum ScalarState {
        case ground
        case csi
        case osc
        case stringControl
    }

    static func sanitize(
        _ data: Data,
        tabWidth: Int = 4
    ) -> String {
        let filteredBytes =
            stripSevenBitControls(data)
        let decoded =
            String(
                decoding: filteredBytes,
                as: UTF8.self
            )
        return stripC1Controls(
            decoded,
            tabWidth: max(1, tabWidth)
        )
    }

    private static func
        stripSevenBitControls(
            _ data: Data
        ) -> Data
    {
        var result = Data()
        result.reserveCapacity(data.count)
        var state = ByteState.ground

        for byte in data {
            switch state {
            case .ground:
                switch byte {
                case 0x1B:
                    state = .escape
                case 0x09:
                    result.append(byte)
                case 0x00...0x1F, 0x7F:
                    continue
                default:
                    result.append(byte)
                }
            case .escape:
                switch byte {
                case 0x1B:
                    continue
                case 0x5B:
                    state = .csi
                case 0x5D:
                    state = .osc
                case 0x50, 0x58, 0x5E, 0x5F:
                    state = .stringControl
                case 0x20...0x2F:
                    continue
                default:
                    state = .ground
                }
            case .csi:
                if byte == 0x1B {
                    state = .escape
                } else if
                    (0x40...0x7E)
                    .contains(byte)
                {
                    state = .ground
                }
            case .osc:
                if byte == 0x07 {
                    state = .ground
                } else if byte == 0x1B {
                    state = .oscEscape
                }
            case .oscEscape:
                if byte == 0x5C {
                    state = .ground
                } else if byte != 0x1B {
                    state = .osc
                }
            case .stringControl:
                if byte == 0x1B {
                    state =
                        .stringControlEscape
                }
            case .stringControlEscape:
                if byte == 0x5C {
                    state = .ground
                } else if byte != 0x1B {
                    state = .stringControl
                }
            }
        }
        return result
    }

    private static func stripC1Controls(
        _ string: String,
        tabWidth: Int
    ) -> String {
        var result = ""
        result.reserveCapacity(
            string.utf8.count
        )
        var state = ScalarState.ground
        var column = 0

        for scalar in string.unicodeScalars {
            let value = scalar.value
            switch state {
            case .ground:
                switch value {
                case 0x9B:
                    state = .csi
                case 0x9D:
                    state = .osc
                case 0x90, 0x98, 0x9E, 0x9F:
                    state = .stringControl
                case 0x09:
                    let spaces =
                        tabWidth
                        - column
                            % tabWidth
                    result.append(
                        String(
                            repeating: " ",
                            count: spaces
                        )
                    )
                    column += spaces
                case 0x00...0x1F,
                     0x7F...0x9F:
                    continue
                default:
                    result.unicodeScalars
                        .append(scalar)
                    column += 1
                }
            case .csi:
                if
                    value >= 0x40,
                    value <= 0x7E
                {
                    state = .ground
                }
            case .osc:
                if
                    value == 0x07
                        || value == 0x9C
                {
                    state = .ground
                }
            case .stringControl:
                if value == 0x9C {
                    state = .ground
                }
            }
        }
        return result
    }
}
