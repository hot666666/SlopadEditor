#if DEBUG
    import Foundation
    import SlopadEditorAppKitUI

    @MainActor
    final class DebugNativeInputTraceWriter {
        private static let prefix = "SLOPADEDITOR_NATIVE_INPUT_TRACE "

        private let encoder: JSONEncoder
        private let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        private let declaredHeadSHA: String
        private let sourceState: DebugNativeInputTraceLine.SourceState
        private let bundleVersion: String?
        private var sequence: UInt64 = 0

        init(environment: [String: String] = ProcessInfo.processInfo.environment) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            self.encoder = encoder
            declaredHeadSHA = Self.validatedBuildSHA(environment["SLOPADEDITOR_BUILD_SHA"])
            sourceState =
                DebugNativeInputTraceLine.SourceState(
                    rawValue: environment["SLOPADEDITOR_BUILD_STATE"] ?? ""
                ) ?? .unverified
            bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        }

        var handler: AppKitNativeInputTraceHandler {
            { event in
                self.write(recordType: .event, event: event)
            }
        }

        func writeProvenance() {
            write(recordType: .provenance, event: nil)
        }

        private func write(
            recordType: DebugNativeInputTraceLine.RecordType,
            event: AppKitNativeInputTraceEvent?
        ) {
            let line = DebugNativeInputTraceLine(
                recordType: recordType,
                sequence: sequence,
                uptimeSeconds: ProcessInfo.processInfo.systemUptime,
                operatingSystem: operatingSystem,
                buildConfiguration: "debug",
                declaredHeadSHA: declaredHeadSHA,
                sourceState: sourceState,
                bundleVersion: bundleVersion,
                inputSourceID: event?.inputSourceID,
                event: event
            )
            sequence += 1

            guard
                let data = try? encoder.encode(line),
                let json = String(data: data, encoding: .utf8)
            else {
                fputs(
                    "\(Self.prefix){\"recordType\":\"encodingFailure\",\"schemaVersion\":1}\n",
                    stderr
                )
                return
            }
            fputs("\(Self.prefix)\(json)\n", stderr)
        }

        private static func validatedBuildSHA(_ candidate: String?) -> String {
            guard let candidate, (7...64).contains(candidate.count) else { return "unknown" }
            let hexadecimal = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            guard candidate.unicodeScalars.allSatisfy(hexadecimal.contains) else {
                return "unknown"
            }
            return candidate.lowercased()
        }
    }

    private struct DebugNativeInputTraceLine: Encodable {
        enum RecordType: String, Encodable {
            case provenance
            case event
        }

        enum SourceState: String, Encodable {
            case clean
            case dirty
            case unverified
        }

        let schemaVersion = 1
        let recordType: RecordType
        let sequence: UInt64
        let uptimeSeconds: TimeInterval
        let operatingSystem: String
        let buildConfiguration: String
        let declaredHeadSHA: String
        let sourceState: SourceState
        let bundleVersion: String?
        let inputSourceID: String?
        let event: AppKitNativeInputTraceEvent?
    }
#endif
