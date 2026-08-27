import SwiftUI

struct OptimizationWizardView: View {
    @Binding var isPresented: Bool
    let host: SSHHost
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.largeTitle)
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading) {
                    Text("优化服务器环境")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("只需一次配置，彻底解决你的痛点")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "key.fill",
                    color: .orange,
                    title: "配置免密登录",
                    desc: "自动为你生成并分发本地 RSA 公钥，以后连接无需再输入密码。"
                )
                
                FeatureRow(
                    icon: "location.fill",
                    color: .blue,
                    title: "精准路径跟随 (OSC 7)",
                    desc: "在服务器的 bashrc/zshrc 中注入终端协议，100% 解决含 Tab 补全、别名、软连接的路径追踪失败问题。"
                )
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack {
                Button("不再提示") {
                    onDecline()
                    isPresented = false
                }
                Spacer()
                Button("取消") {
                    isPresented = false
                }
                Button("一键优化") {
                    onAccept()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
