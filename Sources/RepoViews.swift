import SwiftUI

struct NewRepoView: View {
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var desc = ""
    @State private var isPrivate = false
    @State private var addReadme = true
    @State private var license = ""
    @State private var gitignore = ""
    @State private var licenses: [LicenseTemplate] = []
    @State private var ignores: [String] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("仓库名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("描述（可选）", text: $desc)
                Toggle("私有仓库", isOn: $isPrivate)
                Toggle("添加 README", isOn: $addReadme)
            }
            Section("许可证") {
                Picker("许可证", selection: $license) {
                    Text("无").tag("")
                    ForEach(licenses) { l in Text(l.name).tag(l.key) }
                }
            }
            Section(".gitignore") {
                Picker("模板", selection: $gitignore) {
                    Text("无").tag("")
                    ForEach(ignores, id: \.self) { g in Text(g).tag(g) }
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button { Task { await create() } } label: {
                    HStack { if busy { ProgressView() }; Text("创建仓库") }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .navigationTitle("新建仓库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .task {
            licenses = (try? await API.shared.get("/licenses")) ?? []
            ignores = (try? await API.shared.get("/gitignore/templates")) ?? []
        }
    }

    private func create() async {
        busy = true
        error = nil
        var body: [String: Any] = [
            "name": name,
            "description": desc,
            "private": isPrivate,
            "auto_init": addReadme || !license.isEmpty || !gitignore.isEmpty
        ]
        if !license.isEmpty { body["license_template"] = license }
        if !gitignore.isEmpty { body["gitignore_template"] = gitignore }
        do {
            try await API.shared.post("/user/repos", body: body)
            onCreated()
            dismiss()
        } catch { self.error = errText(error) }
        busy = false
    }
}
