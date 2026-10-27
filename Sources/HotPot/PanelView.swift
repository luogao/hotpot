import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            Divider().opacity(0.25)

            if model.sessions.isEmpty {
                emptyState.padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.sessions, id: \.rootPid) { s in
                        AgentRow(session: s,
                                 cooled: model.isCooled(s),
                                 onToggle: { model.toggleCool(s) })
                        if s.rootPid != model.sessions.last?.rootPid {
                            Divider().opacity(0.12).padding(.leading, 44)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            Divider().opacity(0.25)
            footer.padding(12)
        }
        .frame(width: 330)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.temperature > 0 ? "\(Int(model.temperature.rounded()))°C" : "—°C")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(model.level.label)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(nsColor: model.level.color).opacity(0.16))
                        .foregroundStyle(Color(nsColor: model.level.color))
                        .clipShape(Capsule())
                }
                Text("芯片最高温 · \(model.sensorName.isEmpty ? "读取中" : model.sensorName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.cooled.isEmpty {
                Button("全部降温") { model.coolAll() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color(nsColor: model.level.color))
            } else {
                Button("恢复全速") { model.restoreAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前没有 agent 在跑").font(.system(size: 12, weight: .medium))
            Text("Claude Code / Codex / Cursor 一启动就会出现在这里")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Text("\(model.processCount) 个进程 · \(model.cooled.count) 个已降温")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出")
        }
    }
}

struct AgentRow: View {
    let session: AgentSession
    let cooled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text(session.def.emoji).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.def.name)
                    .font(.system(size: 12, weight: .medium))
                Text("\(session.summary) · \(session.pids.count) 进程")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(String(format: "%.0f%%", session.cpuPercent))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(session.cpuPercent > 50 ? Color(nsColor: .systemOrange) : .secondary)
            Button(action: onToggle) {
                Image(systemName: cooled ? "snowflake.circle.fill" : "snowflake")
                    .font(.system(size: 14))
                    .foregroundStyle(cooled ? Color(nsColor: .systemCyan) : .secondary)
            }
            .buttonStyle(.plain)
            .help(cooled ? "恢复全速" : "降到能效核，不中断任务")
            .disabled(session.hasOtherUid)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .opacity(session.hasOtherUid ? 0.55 : 1)
    }
}
