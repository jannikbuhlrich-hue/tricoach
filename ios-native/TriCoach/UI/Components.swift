import SwiftUI

/// Große Trainingskachel
struct MetricTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var subtitle: String? = nil
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let unit {
                    Text(unit).font(.headline).foregroundStyle(.secondary)
                }
            }
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(tint.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

/// Container-Karte mit Titel
struct Card<Content: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title).font(.headline)
            } icon: {
                if let symbol { Image(systemName: symbol) }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

struct RingGauge: View {
    let value: Double   // 0…1
    let label: String
    let caption: String
    var tint: Color = Theme.accent
    var size: CGFloat = 110

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label).font(.system(.title2, design: .rounded).weight(.bold))
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut, value: value)
    }
}

struct ProgressRow: View {
    let title: String
    let progress: Double
    let detail: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, max(0, progress))).tint(tint)
        }
    }
}

struct InsightRow: View {
    let insight: Insight

    private var symbol: String {
        switch insight.kind {
        case .strength: return "arrow.up.circle.fill"
        case .weakness: return "target"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch insight.kind {
        case .strength: return .green
        case .weakness: return .orange
        case .warning: return .yellow
        case .info: return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title).font(.subheadline.weight(.semibold))
                Text(insight.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.sport.symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(activity.sport.tint.opacity(0.2), in: Circle())
                .foregroundStyle(activity.sport.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name).font(.subheadline.weight(.semibold))
                Text("\(Fmt.shortDate(activity.startDate)) · \(Fmt.hoursMinutes(activity.duration))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(activity.sport == .swim ? Fmt.meters(activity.distance) : Fmt.km(activity.distance))
                    .font(.subheadline.monospacedDigit())
                if let tss = activity.tss {
                    Text("TSS \(Int(tss))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Adaptive Kachelraster: iPhone 2 Spalten, iPad 3–4
struct TileGrid<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 200 : 150), spacing: 12)], spacing: 12) {
            content
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}
