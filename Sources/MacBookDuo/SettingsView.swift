import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: DuoModel
    private let accent = Color(red: 0.69, green: 0.79, blue: 1)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "macbook.gen2").font(.system(size: 23, weight: .light)).foregroundStyle(accent)
                    Text("MacBook Duo").font(.system(size: 19, weight: .semibold))
                    Spacer()
                    Text("LAB / 01").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.gray)
                }.padding(.bottom, 37)
                Text("让界面，\n随屏幕一起展开。").font(.system(size: 37, weight: .medium)).tracking(-1).lineSpacing(5)
                Text("在开合之间，感受玻璃的流动。")
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 13)
                ZStack {
                    RoundedRectangle(cornerRadius: 19).fill(Color.black.opacity(0.28))
                    GlassPreview(model: model)
                        .aspectRatio(1.6, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(12)
                }.overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.10), lineWidth: 1))
                    .padding(.top, 30)
                HStack {
                    Circle().fill(model.live ? Color.green : accent).frame(width: 5, height: 5)
                    Text(model.live ? "LIVE DESKTOP" : "GLASS PREVIEW").tracking(1.8)
                    Spacer()
                    Text("\(Int(model.angle))° / \(Int(model.endpoint))°").monospacedDigit()
                }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).padding(.top, 14)
                HStack(spacing: 10) {
                    Button { model.demo() } label: { Label("播放开合", systemImage: "play.fill") }
                    Button { model.preview() } label: { Label("全屏调试", systemImage: "arrow.up.left.and.arrow.down.right") }
                    Spacer()
                    if model.liveEnabled || model.previewing || model.starting {
                        Button("停止效果") { model.stopAndShow() }.foregroundStyle(.orange)
                    }
                }.buttonStyle(.bordered).controlSize(.large).padding(.top, 25)
                Spacer(minLength: 16)
                HStack {
                    Text("DESIGNED TO UNFOLD").tracking(2)
                    Spacer()
                    Text("原生渲染 · 本地处理")
                }.font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
            }.padding(32).frame(minWidth: 610, maxWidth: .infinity)
                .background(LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.17), Color(red: 0.065, green: 0.075, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("调试设置").font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Text(model.mode).font(.system(size: 10, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 5).background(.white.opacity(0.07), in: Capsule())
                    }
                    group("01", "桌面来源") {
                        Button { model.importImage() } label: {
                            HStack {
                                Image(systemName: "photo.badge.plus").font(.system(size: 20)).foregroundStyle(accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("导入桌面截图").font(.system(size: 12, weight: .medium))
                                    Text(model.imageName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
                            }.padding(13).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                        Text("PNG、JPEG、HEIC 或 TIFF · 自动保留供下次使用")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    group("02", "铰链与展开") {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(String(format: "%.0f", model.angle)).font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                            Text("°").font(.system(size: 23, weight: .light)).foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                HStack(spacing: 5) {
                                    Circle().fill(model.sensorAngle == nil ? Color.orange : Color.green).frame(width: 5, height: 5)
                                    Text(model.sensorAngle == nil ? "传感器不可用" : "传感器已连接")
                                }
                                Text(model.sensorAngle.map { "实际角度 \(Int($0))°" } ?? "可使用手动模拟")
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Picker("角度来源", selection: $model.manual) {
                            Text("手动模拟").tag(true)
                            Text("真实铰链").tag(false)
                        }.pickerStyle(.segmented).disabled(model.live || model.starting)
                        Slider(value: $model.manualAngle, in: 0...180).disabled(!model.manual || model.live)
                            .accessibilityLabel("模拟铰链角度")
                        HStack { Text("0° · 闭合"); Spacer(); Text("180°") }.font(.system(size: 9)).foregroundStyle(.secondary)
                        HStack {
                            Text("展开终点").font(.system(size: 11))
                            Spacer()
                            Text("\(Int(model.endpoint))°").font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
                            Button("保存当前") { model.saveEndpoint() }.controlSize(.small)
                        }.padding(.top, 5)
                    }
                    group("03", "玻璃质感") {
                        parameter("毛玻璃强度", value: $model.frost)
                        parameter("悬浮透视", value: $model.depth)
                        parameter("黑边柔和度", value: $model.edgeSoftness)
                        parameter("色散强度", value: $model.dispersion)
                    }
                    Button { model.toggleLive() } label: {
                        HStack {
                            Image(systemName: model.liveEnabled ? "pause.circle.fill" : "sparkles")
                            Text(model.starting ? "取消连接" : (model.liveEnabled ? "关闭实时效果" : "开启实时桌面"))
                            Spacer()
                            Text("⌘⇧G").opacity(0.65)
                        }.font(.system(size: 12, weight: .medium)).padding(13).foregroundStyle(Color.black.opacity(0.85))
                            .background(accent, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle("开盖后自动恢复", isOn: $model.autoResume)
                            .toggleStyle(.switch).font(.system(size: 11))
                        Text("开启一次实时效果，合盖暂停、开盖接续。请让应用保持在菜单栏运行。")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                    if model.needsCapturePermission {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(model.capturePermissionReady ? "屏幕权限已就绪" : "等待屏幕权限生效", systemImage: model.capturePermissionReady ? "checkmark.circle" : "lock.display")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                            Text(model.capturePermissionReady ? "可以再次点击「开启实时桌面」。" : "若系统开关已打开，先重新启动应用。更新构建后仍无效时，请将 MacBook Duo 的录屏开关关闭再开启，并按系统提示重启。")
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                            Button("授权后重试") { model.retryLive() }.controlSize(.small)
                            HStack {
                                Button("打开录屏设置") { model.openCaptureSettings() }
                                Button("重新启动") { model.restartApp?() }
                            }.controlSize(.small)
                        }.padding(12).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(spacing: 9) {
                        shortcut("开关实时效果", "⌘ ⇧ G")
                        shortcut("停止并返回设置", "⌘ ⇧ Esc")
                        shortcut("保存当前铰链终点", "⌘ ⇧ K")
                        shortcut("调试时隐藏 / 恢复面板", "⌘ H")
                    }
                    Text("实时模式首次使用需要屏幕录制权限。画面仅在本机 GPU 处理，不录音、不上传。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(4)
                }.padding(25)
            }.frame(width: 335).background(Color(red: 0.085, green: 0.092, blue: 0.11))
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .tint(accent)
        .accentColor(accent)
        .preferredColorScheme(.dark)
        .frame(minWidth: 960, minHeight: 730)
        .alert("MacBook Duo", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    private func group<Content: View>(_ number: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Text(number).foregroundStyle(accent.opacity(0.7)).font(.system(size: 10, design: .monospaced))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            content()
        }
    }
    private func parameter(_ label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 6) {
            HStack { Text(label); Spacer(); Text("\(Int(value.wrappedValue * 100))%").monospacedDigit().foregroundStyle(.secondary) }.font(.system(size: 11))
            Slider(value: value, in: 0...1).accessibilityLabel(label)
        }
    }
    private func shortcut(_ label: String, _ key: String) -> some View {
        HStack { Text(label); Spacer(); Text(key).font(.system(size: 10, design: .monospaced)) }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}
