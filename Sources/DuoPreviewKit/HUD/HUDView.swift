import Observation
import SwiftUI

@MainActor
@Observable
final class HUDModel {
    @ObservationIgnored unowned let runtime: DuoRuntime
    @ObservationIgnored var onCollapsedChange: (() -> Void)?

    private(set) var state: DuoState
    private(set) var animationKind: DuoAnimation.Kind
    var sliderAngle: Double
    var customWidth = ""
    var customHeight = ""
    var stressCycles: Int
    var status = ""
    var isBusy = false
    /// Narrow window (iPhone): only presets, fold and the 0/90/180 buttons.
    var compact = false
    /// Observable mirror of the runtime options (runtime itself is not observable).
    var options: DuoOptions {
        didSet {
            if runtime.options != options { runtime.options = options }
            if oldValue.hudAdvanced != options.hudAdvanced { onCollapsedChange?() }
        }
    }
    var collapsed: Bool {
        didSet {
            runtime.options.hudCollapsed = collapsed
            onCollapsedChange?()
        }
    }

    init(runtime: DuoRuntime) {
        self.runtime = runtime
        state = runtime.state
        animationKind = runtime.animation.kind
        sliderAngle = runtime.state.hingeAngle
        stressCycles = runtime.config.tools.stressCycles
        collapsed = runtime.options.hudCollapsed
        options = runtime.options
    }

    var config: DuoConfiguration { runtime.config }
    var layout: DuoLayout { state.layout(in: config) }

    func refresh() {
        state = runtime.state
        animationKind = runtime.animation.kind
        sliderAngle = state.hingeAngle
        options = runtime.options
    }

    // MARK: Options


    // MARK: Actions

    var animation: DuoAnimation {
        DuoAnimation(kind: animationKind)
    }

    func setAnimationKind(_ kind: DuoAnimation.Kind) {
        animationKind = kind
        runtime.animation = animation
    }

    func selectPreset(_ id: String) {
        DuoPreview.setPreset(id, animation: animation)
    }

    func toggleFold() {
        runtime.toggleFold()
    }

    func setAngle(_ angle: Double, animated: Bool) {
        var s = runtime.state
        s.hingeAngle = angle
        DuoPreview.set(s, animation: animated ? animation : .none)
    }

    func applyCustomSize() {
        guard let w = Double(customWidth), let h = Double(customHeight), w > 0, h > 0 else {
            status = "Custom size: enter width and height"
            return
        }
        var s = runtime.state
        s.customSize = CGSize(width: w, height: h)
        DuoPreview.set(s, animation: animation)
    }

    func clearCustomSize() {
        var s = runtime.state
        s.customSize = nil
        DuoPreview.set(s, animation: animation)
    }

    func captureAll() {
        guard !isBusy else { return }
        isBusy = true
        status = "Capturing…"
        Task {
            let url = await DuoPreview.captureAllStates()
            status = url.map { "Saved: \($0.lastPathComponent)" } ?? "Capture failed"
            isBusy = false
        }
    }

    func runStressTest() {
        guard !isBusy else { return }
        isBusy = true
        status = "Stress test running…"
        var configuration = DuoStressTestConfiguration(config: config, animation: animation)
        configuration.cycles = stressCycles
        Task {
            let url = await DuoPreview.runStressTest(configuration)
            status = url.map { "Report: \($0.deletingLastPathComponent().lastPathComponent)" } ?? "Stress test failed"
            isBusy = false
        }
    }
}

/// Wide, low panel docked above the device. Simple mode shows the everyday controls; advanced adds the rest.
struct HUDView: View {
    @Bindable var model: HUDModel

    private var advanced: Bool { model.options.hudAdvanced }

    var body: some View {
        if model.compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                Text("Duo Preview").font(.system(size: 15, weight: .semibold))
                Text("\(Int(model.layout.contentFrame.width))×\(Int(model.layout.contentFrame.height)) · \(Int(model.state.hingeAngle))°")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    model.collapsed = true
                } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 22))
                }
                .accessibilityLabel("Collapse")
            }
            .frame(height: 40)
            ScrollView(.horizontal, showsIndicators: false) {
                presets
            }
            HStack(spacing: 8) {
                postureControl
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .controlSize(.regular)
        .background(.regularMaterial)
        .environment(\.colorScheme, .dark)
        .font(.system(size: 14))
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 12) {
                presets
                divider
                postureControl
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                animation
                divider
                optionToggle("Blur", \.blurOnFold, tint: .orange)
                divider
                optionToggle("3D", \.show3D, tint: .orange)
                    .accessibilityLabel("3D view (half-open)")
                divider
                angle
            }
            if advanced {
                HStack(spacing: 12) {
                    customSize
                    divider
                    optionToggle("Frame", \.showFrame)
                    optionToggle("Hinge", \.showHinge)
                    optionToggle("Sizes", \.showSizes)
                    divider
                    optionToggle("Right toolbar", \.sideToolbar)
                        .accessibilityHint("Moves navigation bar buttons to the right edge in Open Landscape and Outer")
                    optionToggle("Line", \.safeAreaLine)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .controlSize(.large)
        .background(.regularMaterial)
        .environment(\.colorScheme, .dark)
        .font(.system(size: 16))
    }

    private var divider: some View {
        Rectangle().fill(.quaternary).frame(width: 1, height: 40)
    }

    private var header: some View {
        let layout = model.layout
        var info = "\(Int(layout.contentFrame.width))×\(Int(layout.contentFrame.height)) · "
            + "\(layout.posture.rawValue) \(Int(model.state.hingeAngle))°"
        if advanced {
            info += " · h:\(layout.sizeClass.horizontal.rawValue) v:\(layout.sizeClass.vertical.rawValue) · "
                + "\(layout.display.rawValue) · hinge \(layout.hingeRect.isNull ? "null" : "\(layout.hingeRect.integral)")"
        }
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            Text("Duo Preview").font(.system(size: 18, weight: .semibold))
            Text(info)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if !model.status.isEmpty {
                Text(model.status).font(.system(size: 13)).foregroundStyle(.orange).lineLimit(1).truncationMode(.middle)
            }
            Button {
                model.captureAll()
            } label: {
                Label("Screenshots", systemImage: "camera")
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)
            .fixedSize()
            if advanced {
                Menu {
                    Stepper("Stress cycles: \(model.stressCycles)", value: $model.stressCycles, in: 1...100)
                    Button("Run stress test", systemImage: "arrow.triangle.2.circlepath") { model.runStressTest() }
                } label: {
                    Label("Stress test", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
                .fixedSize()
            }
            Toggle(isOn: $model.options.hudAdvanced) {
                Label("Advanced", systemImage: "slider.horizontal.3")
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(advanced ? .indigo : .gray)
            .fixedSize()
            Button {
                model.collapsed = true
            } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 26))
            }
            .accessibilityLabel("Collapse")
        }
        .frame(height: 56)
    }

    private var presets: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.config.presets.enumerated()), id: \.element.id) { index, preset in
                let selected = model.state.customSize == nil && model.layout.preset.id == preset.id
                Button {
                    model.selectPreset(preset.id)
                } label: {
                    VStack(spacing: 0) {
                        Text(preset.displayTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1).fixedSize()
                        if advanced {
                            Text("\(Int(preset.width))×\(Int(preset.height))").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(selected ? .indigo : .gray)
                .accessibilityHint("⌘\(index + 1)")
            }
        }
    }

    /// Closed / half-open / open, the three postures the API reports.
    private var postureControl: some View {
        HStack(spacing: 6) {
            postureButton("Closed", systemImage: "book.closed", angle: model.config.angles.closed, posture: .closed)
            postureButton("Half-open", systemImage: "book.pages", angle: model.config.angles.halfOpen, posture: .halfOpen)
            postureButton("Open", systemImage: "book", angle: model.config.angles.open, posture: .open)
        }
    }

    private func postureButton(_ title: String, systemImage: String, angle: Double, posture: DuoPosture) -> some View {
        let selected = model.layout.posture == posture
        return Button {
            model.setAngle(angle, animated: true)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .indigo : .gray)
        .font(.system(size: 15, weight: selected ? .semibold : .regular))
        .fixedSize()
    }

    private var animation: some View {
        HStack(spacing: 6) {
            Text("Animation").foregroundStyle(.secondary).fixedSize().padding(.leading, 10)
            // realistic: snapshot leaves fold in 3D; none: instant.
            ForEach([(DuoAnimation.Kind.realistic, "3D fold"), (.none, "Instant")], id: \.0) { kind, title in
                Button(title) { model.setAnimationKind(kind) }
                    .buttonStyle(.bordered)
                    .tint(model.animationKind == kind ? .indigo : .gray)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize()
            }

        }
    }

    private var angle: some View {
        HStack(spacing: 10) {
            Text("Angle").foregroundStyle(.secondary).fixedSize()
            Slider(value: $model.sliderAngle, in: 0...180, step: 1) { _ in }
                .frame(width: 200)
                .onChange(of: model.sliderAngle) { _, value in
                    if Int(value) != Int(model.state.hingeAngle) { model.setAngle(value, animated: false) }
                }
            Text("\(Int(model.sliderAngle))°").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }

    private var customSize: some View {
        HStack(spacing: 4) {
            TextField("W", text: $model.customWidth).keyboardType(.numberPad).frame(width: 72)
            Text("×").foregroundStyle(.secondary)
            TextField("H", text: $model.customHeight).keyboardType(.numberPad).frame(width: 72)
            Button("Apply") { model.applyCustomSize() }.buttonStyle(.bordered)
            if model.state.customSize != nil {
                Button("Reset") { model.clearCustomSize() }.buttonStyle(.bordered)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func optionToggle(_ title: String, _ keyPath: WritableKeyPath<DuoOptions, Bool>, tint: Color = .indigo) -> some View {
        Toggle(isOn: $model.options[dynamicMember: keyPath]) {
            Text(title).font(.system(size: 15, weight: .semibold))
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .tint(model.options[keyPath: keyPath] ? tint : .gray)
        .fixedSize()
    }
}
