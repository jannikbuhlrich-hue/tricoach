import SwiftUI
import UniformTypeIdentifiers
import AppIntents

struct SettingsView: View {
    @Environment(TrainingStore.self) private var store
    @AppStorage("appearance") private var appearance: AppearanceMode = .dark
    @AppStorage("useLLMCoach") private var useLLMCoach = false
    @State private var showImporter = false
    @State private var message: String? = nil
    @State private var garminBusy = false
    @State private var garminConnected = GarminConfig.isConnected

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Profil & Schwellenwerte") {
                TextField("Name", text: $store.profile.name)
                LabeledContent("Gewicht (kg)") {
                    TextField("kg", value: $store.profile.weightKg, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                }
                Stepper("FTP: \(store.profile.ftp) W", value: $store.profile.ftp, in: 100...500, step: 5)
                Stepper("Laktatschwelle HF: \(store.profile.lactateThresholdHR)", value: $store.profile.lactateThresholdHR, in: 120...210)
                Stepper("Max. HF: \(store.profile.maxHeartRate)", value: $store.profile.maxHeartRate, in: 140...230)
                Stepper("Ruhepuls: \(store.profile.restingHeartRate)", value: $store.profile.restingHeartRate, in: 30...90)
                Stepper("Schwellenpace: \(Fmt.paceValue(store.profile.thresholdPace)) /km",
                        value: $store.profile.thresholdPace, in: 180...420, step: 1)
                Stepper("CSS: \(Fmt.paceValue(store.profile.css)) /100m", value: $store.profile.css, in: 60...180, step: 1)
                Button("Trainingsbelastung neu berechnen") { store.recalculateLoad() }
            }

            Section {
                garminRow
                Toggle(isOn: sourceBinding(.healthKit)) {
                    Label("Apple Health", systemImage: "heart.text.square.fill")
                }
                Toggle(isOn: sourceBinding(.fitFile)) {
                    Label("FIT-Dateien", systemImage: "doc.badge.arrow.up")
                }
                if store.enabledSources.contains(.fitFile) {
                    Button("FIT-Dateien importieren …") { showImporter = true }
                }
                Toggle(isOn: sourceBinding(.mock)) {
                    Label("Demo-Daten", systemImage: "wand.and.stars")
                }
            } header: {
                Text("Datenquellen")
            } footer: {
                Text("Forerunner 265 → Garmin Connect → (a) Garmin-API über dein Backend, (b) Apple Health (Basisdaten) oder (c) FIT-Export (volle Details inkl. SWOLF & Laufdynamik).")
            }

            Section("Synchronisation") {
                Button {
                    Task { await store.sync() }
                } label: {
                    HStack {
                        Text("Jetzt synchronisieren")
                        Spacer()
                        if store.isSyncing { ProgressView() }
                    }
                }
                if let last = store.lastSync {
                    LabeledContent("Letzter Sync", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Aktivitäten", value: "\(store.activities.count)")
                ForEach(store.lastErrors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
            }

            Section("Kalender") {
                Toggle("Mit Apple Kalender synchronisieren", isOn: Binding(
                    get: { store.calendarSyncEnabled },
                    set: { enabled in
                        Task {
                            if enabled {
                                let granted = await CalendarSyncService.shared.requestAccess()
                                store.calendarSyncEnabled = granted
                                if granted { await CalendarSyncService.shared.syncAll(store: store) }
                                else { message = "Kalenderzugriff verweigert – in den iOS-Einstellungen erlauben." }
                            } else {
                                store.calendarSyncEnabled = false
                            }
                        }
                    }
                ))
            }

            Section {
                Toggle("KI-Coach über Backend", isOn: $useLLMCoach)
                    .disabled(GarminConfig.backendURL == nil)
            } header: {
                Text("Coaching")
            } footer: {
                Text("Ohne Backend nutzt die App die lokale Regel-Engine (TSB, Bereitschaft, Schwächen, Taper).")
            }

            Section("Siri") {
                SiriTipView(intent: ShowTodayWorkoutIntent())
                SiriTipView(intent: WeeklyDistanceIntent())
                Text("„Hey Siri, plane eine Radeinheit für morgen in TriCoach“").font(.subheadline)
            }

            Section("Darstellung") {
                Picker("Modus", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.displayName).tag($0) }
                }
            }
        }
        .navigationTitle("Einstellungen")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: "fit") ?? .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                do {
                    let count = try FITImportDataSource.importFiles(urls)
                    message = "\(count) FIT-Datei(en) importiert."
                    Task { await store.sync() }
                } catch {
                    message = error.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    @ViewBuilder
    private var garminRow: some View {
        HStack {
            Label("Garmin Connect", systemImage: "applewatch.radiowaves.left.and.right")
            Spacer()
            if garminBusy {
                ProgressView()
            } else if garminConnected {
                Button("Trennen", role: .destructive) {
                    Task {
                        await GarminAuthService.shared.disconnect()
                        garminConnected = false
                        store.enabledSources.remove(.garmin)
                    }
                }
            } else {
                Button("Verbinden") {
                    Task {
                        garminBusy = true
                        defer { garminBusy = false }
                        do {
                            try await GarminAuthService.shared.connect()
                            garminConnected = true
                            store.enabledSources.insert(.garmin)
                            SyncService.shared.registerForPush()
                            await store.sync()
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .disabled(!GarminConfig.isConfigured)
            }
        }
        if !GarminConfig.isConfigured {
            Text("Garmin-API benötigt eine freigeschaltete App im Garmin Connect Developer Program + Backend (siehe README).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func sourceBinding(_ kind: DataSourceKind) -> Binding<Bool> {
        Binding(
            get: { store.enabledSources.contains(kind) },
            set: { enabled in
                if enabled {
                    store.enabledSources.insert(kind)
                    if kind == .healthKit {
                        Task {
                            do {
                                try await HealthKitDataSource().requestAuthorization()
                                SyncService.shared.startHealthKitObserver()
                            } catch {
                                message = error.localizedDescription
                            }
                            await store.sync()
                        }
                        return
                    }
                } else {
                    store.enabledSources.remove(kind)
                }
                Task { await store.sync() }
            }
        )
    }
}
