import Foundation

/// Una canción del setlist: qué preset usa y, si quieres, a qué tempo.
struct Song: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var slot: Int            // posición del preset en el pedal (0-based)
    var bpm: Int?            // nil = no tocar el tempo
}

struct Setlist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var songs: [Song] = []
}

/// Setlists guardados en el iPad (Documentos/Setlists.json) y cuál está activo en Live.
@MainActor
@Observable
final class SetlistStore {
    private(set) var setlists: [Setlist] = []
    private(set) var activeID: UUID?
    private(set) var songIndex = 0

    private static var file: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Setlists.json")
    }
    private static let activeKey = "setlist.active"

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode([Setlist].self, from: data) {
            setlists = saved
        }
        if let s = UserDefaults.standard.string(forKey: Self.activeKey), let id = UUID(uuidString: s),
           setlists.contains(where: { $0.id == id }) {
            activeID = id
        }
    }

    var active: Setlist? { setlists.first { $0.id == activeID } }
    var currentSong: Song? {
        guard let a = active, a.songs.indices.contains(songIndex) else { return nil }
        return a.songs[songIndex]
    }
    func song(offset: Int) -> Song? {
        guard let a = active, a.songs.indices.contains(songIndex + offset) else { return nil }
        return a.songs[songIndex + offset]
    }

    // MARK: Edición

    func create(named name: String) -> Setlist {
        let s = Setlist(name: name.isEmpty ? "Setlist \(setlists.count + 1)" : name)
        setlists.append(s); save()
        return s
    }

    func update(_ setlist: Setlist) {
        guard let i = setlists.firstIndex(where: { $0.id == setlist.id }) else { return }
        setlists[i] = setlist
        if setlist.id == activeID { songIndex = min(songIndex, max(0, setlist.songs.count - 1)) }
        save()
    }

    func delete(_ id: UUID) {
        setlists.removeAll { $0.id == id }
        if activeID == id { activeID = nil; songIndex = 0; saveActive() }
        save()
    }

    func moveSetlists(from: IndexSet, to: Int) {
        setlists.move(fromOffsets: from, toOffset: to); save()
    }

    // MARK: Live

    /// Activa un setlist (o ninguno) y va a la primera canción.
    func activate(_ id: UUID?, store: ControllerStore) {
        activeID = id
        songIndex = 0
        saveActive()
        if id != nil { go(to: 0, store: store) }
    }

    func go(to index: Int, store: ControllerStore) {
        guard let a = active, a.songs.indices.contains(index) else { return }
        songIndex = index
        let song = a.songs[index]
        if store.presets.indices.contains(song.slot) { store.selectPreset(song.slot) }
        if let bpm = song.bpm { store.setBPM(Double(bpm)) }
    }

    func next(store: ControllerStore) { go(to: songIndex + 1, store: store) }
    func previous(store: ControllerStore) { go(to: songIndex - 1, store: store) }

    private func save() {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted]
        if let data = try? e.encode(setlists) { try? data.write(to: Self.file, options: .atomic) }
    }

    private func saveActive() {
        UserDefaults.standard.set(activeID?.uuidString, forKey: Self.activeKey)
    }
}
