import SwiftUI
import SideBCore

struct PlaylistEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let core: SideBCore
    let playlist: PlaylistDetailRecord?
    let onSaved: (String) -> Void

    @State private var name: String
    @State private var description: String
    @State private var privacy: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(core: SideBCore, playlist: PlaylistDetailRecord?, onSaved: @escaping (String) -> Void) {
        self.core = core
        self.playlist = playlist
        self.onSaved = onSaved
        _name = State(initialValue: playlist?.title ?? "")
        _description = State(initialValue: playlist?.description ?? "")
        _privacy = State(initialValue: playlist?.privacy ?? "PRIVATE")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(playlist == nil ? "detail.playlistEditor.createTitle" : "detail.playlistEditor.editTitle"))
                .font(.title2.bold())

            TextField(L10n.text("detail.playlistEditor.name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(L10n.text("detail.playlistEditor.name"))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("detail.playlistEditor.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .frame(height: 90)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            Picker(L10n.text("detail.playlistEditor.visibility"), selection: $privacy) {
                Text(L10n.text("detail.playlistEditor.private")).tag("PRIVATE")
                Text(L10n.text("detail.playlistEditor.unlisted")).tag("UNLISTED")
                Text(L10n.text("detail.playlistEditor.public")).tag("PUBLIC")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) { dismiss() }
                    .disabled(isSaving)
                Button(L10n.text(playlist == nil ? "common.create" : "common.save")) {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            let id: String
            if let existing = playlist?.id {
                id = existing
                try await core.editPlaylistDetails(
                    playlistId: id,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description,
                    privacy: privacy
                )
            } else {
                id = try await core.createPlaylist(
                    title: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: description,
                    privacy: privacy
                )
            }
            NotificationCenter.default.post(name: .sideBPlaylistsChanged, object: nil)
            onSaved(id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
