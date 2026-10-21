import SwiftUI
import MapKit

/// Strava-ähnliche Heatmap aller GPS-Tracks.
struct HeatmapModule: AppModule {
    let id = "heatmap"
    let title = "Heatmap"
    let symbol = "map.fill"
    let tint = Color.red
    let category = ModuleCategory.feature

    func makeView(store: TrainingStore) -> AnyView { AnyView(HeatmapView()) }
}

struct HeatmapView: View {
    @Environment(TrainingStore.self) private var store
    @State private var filter: Sport? = nil
    @State private var days = 90

    private var tracks: [(id: String, sport: Sport, coords: [CLLocationCoordinate2D])] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return store.activities
            .filter { $0.hasGPS && $0.startDate >= cutoff && (filter == nil || $0.sport == filter) }
            .map { a in
                // auf ~300 Punkte ausdünnen, damit die Karte flüssig bleibt
                let track = a.track
                let step = max(1, track.count / 300)
                return (id: a.id, sport: a.sport, coords: stride(from: 0, to: track.count, by: step).map { track[$0] })
            }
    }

    var body: some View {
        Map {
            ForEach(tracks, id: \.id) { t in
                MapPolyline(coordinates: t.coords)
                    .stroke(t.sport.tint.opacity(0.35), lineWidth: 3)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Picker("Sport", selection: $filter) {
                    Text("Alle").tag(Sport?.none)
                    ForEach([Sport.bike, .run, .swim]) { Text($0.displayName).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                Picker("Zeitraum", selection: $days) {
                    Text("30 T").tag(30); Text("90 T").tag(90); Text("1 J").tag(365)
                }
                .pickerStyle(.segmented)
                Text("\(tracks.count) Aktivitäten").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial)
        }
        .navigationTitle("Heatmap")
    }
}
