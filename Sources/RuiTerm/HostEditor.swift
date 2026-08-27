import SwiftUI

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostStore: HostStore

    @State private var host: SSHHost
    @State private var password: String
    @State private var hasSavedPassword: Bool
    @State private var keychainError: String?
    let isNew: Bool

    init(host: SSHHost = SSHHost(), isNew: Bool) {
        _host = State(initialValue: host)
        _password = State(initialValue: "")
        _hasSavedPassword = State(initialValue: KeychainStore.containsPassword(for: host.id))
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 24))
                    .foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "新建 SSH 主机" : "编辑 SSH 主机")
                        .font(.title3.bold())
                    Text("连接详情保存在这台 Mac 的本地。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            OverlayScrollView {
                Form {
                    Section {
                        TextField("名称:", text: $host.name, prompt: Text("生产服务器"))
                        TextField("主机:", text: $host.hostname, prompt: Text("主机名或 IP 地址"))
                        TextField("用户名:", text: $host.username, prompt: Text("选填"))
                        TextField("端口:", value: $host.port, format: .number)
                        Picker("分组:", selection: $host.groupID) {
                            Text("未分组").tag(UUID?.none)
                            ForEach(hostStore.groups) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                        LabeledContent("颜色标签:") {
                            ColorTagPicker(selection: $host.colorTag)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Toggle("收藏主机", isOn: $host.isFavorite)
                    } header: {
                        Text("连接")
                    }

                    Section {
                        TextField("私钥文件:", text: $host.identityFile, prompt: Text("可选路径"))
                        TextField("跳板机:", text: $host.proxyJump, prompt: Text("可选跳板机"))
                    } header: {
                        Text("高级")
                    }

                    Section {
                        Toggle("在钥匙串中保存密码", isOn: $host.savesPassword)
                        if host.savesPassword {
                            SecureField(
                                "密码:",
                                text: $password,
                                prompt: Text(hasSavedPassword ? "留空以保留已保存密码" : "SSH 密码")
                            )
                            Text(hasSavedPassword 
                                 ? "密码已保存在钥匙串中"
                                 : "密码将被安全保存"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("认证")
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Divider()

            HStack(spacing: 12) {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                
                Button("保存") {
                    if host.savesPassword {
                        if !password.isEmpty {
                            if let error = KeychainStore.save(password, for: host.id) {
                                keychainError = error
                                return
                            }
                            hasSavedPassword = true
                        } else if !hasSavedPassword {
                            keychainError = "Enter a password before enabling Keychain storage."
                            return
                        }
                    } else if !host.savesPassword {
                        KeychainStore.delete(for: host.id)
                    }
                    isNew ? hostStore.add(host) : hostStore.update(host)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    host.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || host.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !(1...65_535).contains(host.port)
                )
                .opacity(
                    (host.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || host.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !(1...65_535).contains(host.port)) ? 0.5 : 1
                )
            }
            .padding(16)
        }
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(width: 560, height: 610)
        .alert("无法保存密码", isPresented: Binding(
            get: { keychainError != nil },
            set: { if !$0 { keychainError = nil } }
        )) {
            Button("确定") { keychainError = nil }
        } message: {
            Text(keychainError ?? "")
        }
    }
}
