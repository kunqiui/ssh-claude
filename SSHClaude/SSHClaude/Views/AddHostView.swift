import SwiftUI

/// 添加新主机的表单。
struct AddHostView: View {
    @EnvironmentObject var cm: ConnectionManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("主机或 IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("服务器")
                }

                Section {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                } header: {
                    Text("登录")
                } footer: {
                    Text("密码保存在 iPhone 钥匙串，不会发送给 Apple Watch。")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty || host.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
        }
    }

    private func save() {
        let info = HostInfo(name: name, host: host,
                            port: Int(port) ?? 22,
                            username: username,
                            credentialRef: "keychain")
        do {
            try cm.addHost(info, password: password)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}
