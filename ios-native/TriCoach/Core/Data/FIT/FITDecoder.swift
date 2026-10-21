import Foundation

/// Schlanker Decoder für Garmin-FIT-Dateien (Activity-Files).
/// Liest nur numerische Felder, die die App braucht. Feldnummern laut FIT SDK „Profile.xlsx“.
/// Für den produktiven Einsatz alternativ das offizielle FIT SDK (Swift) einbinden.
struct FITDecoder {
    struct Message {
        let global: UInt16
        var values: [UInt8: Int64]
        subscript(_ field: UInt8) -> Int64? { values[field] }
    }

    enum FITError: Error { case invalidHeader, missingDefinition, truncated }

    private struct FieldDef { let number: UInt8; let size: Int; let baseType: UInt8 }
    private struct Definition { let global: UInt16; let bigEndian: Bool; let fields: [FieldDef]; let devSize: Int }

    static let epochOffset: TimeInterval = 631_065_600 // 1989-12-31 UTC

    static func date(fromFIT seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds) + epochOffset)
    }

    static func decode(_ data: Data) throws -> [Message] {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { throw FITError.invalidHeader }
        let headerSize = Int(bytes[0])
        guard bytes.count >= headerSize, headerSize >= 12,
              String(bytes: bytes[8..<12], encoding: .ascii) == ".FIT" else { throw FITError.invalidHeader }
        let dataSize = Int(UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24)
        let end = min(bytes.count, headerSize + dataSize)

        var i = headerSize
        var definitions: [UInt8: Definition] = [:]
        var messages: [Message] = []
        var lastTimestamp: UInt32 = 0

        while i < end {
            let header = bytes[i]
            i += 1
            if header & 0x80 != 0 {
                // Compressed-Timestamp-Header
                let local = (header >> 5) & 0x03
                let offset = UInt32(header & 0x1F)
                guard let def = definitions[local] else { throw FITError.missingDefinition }
                var msg = try readData(def, bytes: bytes, index: &i, end: end)
                var ts = (lastTimestamp & 0xFFFF_FFE0) + offset
                if offset < (lastTimestamp & 0x1F) { ts &+= 0x20 }
                lastTimestamp = ts
                msg.values[253] = Int64(ts)
                messages.append(msg)
            } else if header & 0x40 != 0 {
                // Definition Message
                let local = header & 0x0F
                let hasDeveloperData = header & 0x20 != 0
                guard i + 5 <= end else { throw FITError.truncated }
                let bigEndian = bytes[i + 1] == 1
                let global = bigEndian
                    ? UInt16(bytes[i + 2]) << 8 | UInt16(bytes[i + 3])
                    : UInt16(bytes[i + 3]) << 8 | UInt16(bytes[i + 2])
                let count = Int(bytes[i + 4])
                i += 5
                var fields: [FieldDef] = []
                for _ in 0..<count {
                    guard i + 3 <= end else { throw FITError.truncated }
                    fields.append(FieldDef(number: bytes[i], size: Int(bytes[i + 1]), baseType: bytes[i + 2]))
                    i += 3
                }
                var devSize = 0
                if hasDeveloperData {
                    guard i < end else { throw FITError.truncated }
                    let devCount = Int(bytes[i])
                    i += 1
                    for _ in 0..<devCount {
                        guard i + 3 <= end else { throw FITError.truncated }
                        devSize += Int(bytes[i + 1])
                        i += 3
                    }
                }
                definitions[local] = Definition(global: global, bigEndian: bigEndian, fields: fields, devSize: devSize)
            } else {
                // Data Message
                let local = header & 0x0F
                guard let def = definitions[local] else { throw FITError.missingDefinition }
                let msg = try readData(def, bytes: bytes, index: &i, end: end)
                if let ts = msg.values[253] { lastTimestamp = UInt32(truncatingIfNeeded: ts) }
                messages.append(msg)
            }
        }
        return messages
    }

    private static func readData(_ def: Definition, bytes: [UInt8], index i: inout Int, end: Int) throws -> Message {
        var values: [UInt8: Int64] = [:]
        for field in def.fields {
            guard i + field.size <= end else { throw FITError.truncated }
            let base = field.baseType & 0x1F
            if field.size == typeSize(base), let v = readInt(bytes, at: i, size: field.size, bigEndian: def.bigEndian, base: base) {
                values[field.number] = v
            }
            i += field.size
        }
        guard i + def.devSize <= end else { throw FITError.truncated }
        i += def.devSize
        return Message(global: def.global, values: values)
    }

    private static func typeSize(_ base: UInt8) -> Int {
        switch base {
        case 0, 1, 2, 7, 10, 13: return 1
        case 3, 4, 11: return 2
        case 5, 6, 8, 12: return 4
        case 9, 14, 15, 16: return 8
        default: return -1
        }
    }

    /// Liefert nil für „invalid“-Werte des jeweiligen Basistyps.
    private static func readInt(_ bytes: [UInt8], at i: Int, size: Int, bigEndian: Bool, base: UInt8) -> Int64? {
        guard base != 7, base != 8, base != 9 else { return nil } // String/Float nicht benötigt
        var raw: UInt64 = 0
        for k in 0..<size {
            let b = UInt64(bigEndian ? bytes[i + k] : bytes[i + size - 1 - k])
            raw = raw << 8 | b
        }
        let bits = UInt64(size * 8)
        let allOnes: UInt64 = bits == 64 ? .max : (1 << bits) - 1
        switch base {
        case 1, 3, 5, 14: // signed
            let signedMax = allOnes >> 1
            if raw == signedMax { return nil }
            let shift = 64 - bits
            return Int64(bitPattern: raw << shift) >> Int64(shift)
        case 10, 11, 12, 16: // uint*z – 0 ist invalid
            return raw == 0 ? nil : Int64(truncatingIfNeeded: raw)
        default:
            return raw == allOnes ? nil : Int64(truncatingIfNeeded: raw)
        }
    }
}

/// Wandelt FIT-Messages in eine `Activity` um.
enum FITActivityMapper {
    // Globale Message-Nummern
    static let session: UInt16 = 18, lap: UInt16 = 19, record: UInt16 = 20, length: UInt16 = 101

    static func activity(from messages: [FITDecoder.Message], fileID: String) -> Activity? {
        guard let session = messages.first(where: { $0.global == Self.session }),
              let startRaw = session[2] else { return nil }

        let start = FITDecoder.date(fromFIT: startRaw)
        let sport: Sport
        switch session[5] {
        case 1?: sport = .run
        case 2?: sport = .bike
        case 5?: sport = .swim
        case 4?, 10?, 20?: sport = .strength
        default: sport = .other
        }

        let records = messages.filter { $0.global == record }
        let samples: [Sample] = records.compactMap { r in
            guard let ts = r[253] else { return nil }
            let lat = r[0].map { Double($0) * 180 / 2_147_483_648 }
            let lon = r[1].map { Double($0) * 180 / 2_147_483_648 }
            let speed = (r[73] ?? r[6]).map { Double($0) / 1000 }
            let altitude = r[78].map { Double($0) / 5 - 500 } ?? r[2].map { Double($0) / 5 - 500 }
            var cadence = r[4].map { Int($0) }
            if sport == .run, let c = cadence { cadence = c * 2 } // FIT speichert Doppelschritte/min
            return Sample(
                offset: FITDecoder.date(fromFIT: ts).timeIntervalSince(start),
                heartRate: r[3].map { Int($0) },
                speed: speed,
                power: r[7].map { Int($0) },
                cadence: cadence,
                altitude: altitude,
                distance: r[5].map { Double($0) / 100 },
                location: (lat != nil && lon != nil) ? GeoPoint(latitude: lat!, longitude: lon!) : nil,
                groundContactTime: r[41].map { Double($0) / 10 },
                verticalOscillation: r[39].map { Double($0) / 100 },   // mm·10 → cm
                strideLength: r[85].map { Double($0) / 10_000 }        // mm·10 → m
            )
        }

        let lapMessages = messages.filter { $0.global == lap }
        let hasRest = lapMessages.contains { [1, 4].contains($0[23] ?? 0) }
        let laps: [Lap] = lapMessages.enumerated().compactMap { index, l in
            guard let lStart = l[2] else { return nil }
            let duration = Double(l[8] ?? l[7] ?? 0) / 1000
            let distance = Double(l[9] ?? 0) / 100
            let intensity = l[23] ?? 0
            return Lap(index: index,
                       startOffset: FITDecoder.date(fromFIT: lStart).timeIntervalSince(start),
                       duration: duration, distance: distance,
                       avgHeartRate: l[15].map { Int($0) },
                       avgSpeed: (l[110] ?? l[13]).map { Double($0) / 1000 },
                       avgPower: l[19].map { Int($0) },
                       isInterval: intensity == 5 || (intensity == 0 && hasRest))
        }

        var activity = Activity(
            id: "fit-\(fileID)",
            sport: sport,
            name: sport.displayName,
            startDate: start,
            duration: Double(session[8] ?? session[7] ?? 0) / 1000,
            distance: Double(session[9] ?? 0) / 100,
            avgHeartRate: session[16].map { Int($0) },
            maxHeartRate: session[17].map { Int($0) },
            calories: session[11].map { Int($0) },
            elevationGain: session[22].map { Double($0) },
            aerobicTrainingEffect: session[24].map { Double($0) / 10 },
            anaerobicTrainingEffect: session[137].map { Double($0) / 10 },
            source: .fitFile,
            samples: samples,
            laps: laps
        )

        switch sport {
        case .run:
            let gct = samples.compactMap(\.groundContactTime)
            let vo = samples.compactMap(\.verticalOscillation)
            let stride = samples.compactMap(\.strideLength)
            activity.run = RunDynamics(
                avgCadence: samples.compactMap { $0.cadence.map(Double.init) }.mean,
                avgStrideLength: stride.mean,
                avgGroundContactTime: gct.mean,
                avgVerticalOscillation: vo.mean,
                avgVerticalRatio: (vo.mean != nil && stride.mean != nil) ? vo.mean! / (stride.mean! * 100) * 100 : nil,
                avgPower: samples.compactMap { $0.power.map(Double.init) }.mean
            )
        case .bike:
            let powers = samples.map { Double($0.power ?? 0) }
            let dt = SeriesMath.sampleInterval(samples)
            activity.bike = BikeMetrics(
                avgPower: session[20].map { Int($0) },
                normalizedPower: session[34].map { Int($0) } ?? SeriesMath.normalizedPower(values: powers, interval: dt).map { Int($0) },
                maxPower: session[21].map { Int($0) },
                avgCadence: session[18].map { Int($0) },
                elevationGain: activity.elevationGain,
                powerCurve: SeriesMath.powerCurve(samples: samples)
            )
        case .swim:
            let lengths: [SwimLength] = messages.filter { $0.global == length && ($0[12] ?? 1) == 1 }
                .enumerated().map { index, m in
                    SwimLength(index: index,
                               duration: Double(m[4] ?? 0) / 1000,
                               strokes: Int(m[5] ?? 0),
                               strokeType: StrokeType.fromFIT(m[7]))
                }
            let pool = session[44].map { Double($0) / 100 }
            let freestyle = lengths.filter { $0.strokes > 0 }
            activity.swim = SwimMetrics(
                poolLength: pool,
                totalStrokes: lengths.reduce(0) { $0 + $1.strokes },
                avgSwolf: freestyle.map { Double($0.swolf) }.mean,
                avgStrokeRate: freestyle.map(\.strokeRate).mean,
                lengths: lengths
            )
        default:
            break
        }
        return activity
    }
}

extension StrokeType {
    static func fromFIT(_ value: Int64?) -> StrokeType {
        switch value {
        case 0?: return .freestyle
        case 1?: return .backstroke
        case 2?: return .breaststroke
        case 3?: return .butterfly
        case 4?: return .drill
        default: return .mixed
        }
    }
}
