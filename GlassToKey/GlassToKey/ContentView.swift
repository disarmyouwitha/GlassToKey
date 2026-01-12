//
//  ContentView.swift
//  GlassToKey
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import Combine
import OpenMultitouchSupport
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    @State private var testText = ""
    @State private var displayTouchData = [OMSTouchData]()
    @State private var visualsEnabled = true
    @State private var keyScale = 1.0
    @State private var thumbScale = 1.0
    @State private var pinkyScale = 1.2
    @State private var keyOffsetX = 0.0
    @State private var keyOffsetY = 0.0
    @State private var leftLayout: ContentViewModel.Layout
    @State private var rightLayout: ContentViewModel.Layout
    @State private var customButtons: [CustomButton] = []
    @State private var selectedButtonID: UUID?
    @State private var dragStartRects: [UUID: NormalizedRect] = [:]
    @State private var resizeStartRects: [UUID: NormalizedRect] = [:]
    @AppStorage(GlassToKeyDefaultsKeys.leftDeviceID) private var storedLeftDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.rightDeviceID) private var storedRightDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.visualsEnabled) private var storedVisualsEnabled = true
    @AppStorage(GlassToKeyDefaultsKeys.keyScale) private var storedKeyScale = 1.0
    @AppStorage(GlassToKeyDefaultsKeys.thumbScale) private var storedThumbScale = 1.0
    @AppStorage(GlassToKeyDefaultsKeys.pinkyScale) private var storedPinkyScale = 1.2
    @AppStorage(GlassToKeyDefaultsKeys.keyOffsetX) private var storedKeyOffsetX = 0.0
    @AppStorage(GlassToKeyDefaultsKeys.keyOffsetY) private var storedKeyOffsetY = 0.0
    @AppStorage(GlassToKeyDefaultsKeys.customButtons) private var storedCustomButtonsData = Data()
    static let trackpadWidthMM: CGFloat = 160.0
    static let trackpadHeightMM: CGFloat = 114.9
    static let displayScale: CGFloat = 2.7
    static let baseKeyWidthMM: CGFloat = 18.0
    static let baseKeyHeightMM: CGFloat = 17.0
    static let minCustomButtonSize = CGSize(width: 0.05, height: 0.05)
    private static let resizeHandleSize: CGFloat = 10.0
    private static let keyScaleRange: ClosedRange<Double> = 0.5...2.0
    private static let thumbScaleRange: ClosedRange<Double> = 0.5...2.0
    private static let pinkyScaleRange: ClosedRange<Double> = 0.5...2.0
    private static let keyOffsetRange: ClosedRange<Double> = -30.0...30.0
    private static let keyScaleFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.keyScaleRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.keyScaleRange.upperBound)
        return formatter
    }()
    private static let thumbScaleFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.thumbScaleRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.thumbScaleRange.upperBound)
        return formatter
    }()
    private static let pinkyScaleFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.pinkyScaleRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.pinkyScaleRange.upperBound)
        return formatter
    }()
    private static let keyOffsetFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.keyOffsetRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.keyOffsetRange.upperBound)
        return formatter
    }()
    private let displayRefreshInterval: TimeInterval = 1.0 / 60.0
    // Per-column anchor positions in trackpad mm (top key origin).
    static let ColumnAnchorsMM: [CGPoint] = [
        CGPoint(x: 35.0, y: 20.9),
        CGPoint(x: 53.0, y: 19.2),
        CGPoint(x: 71.0, y: 17.5),
        CGPoint(x: 89.0, y: 19.2),
        CGPoint(x: 107.0, y: 22.6),
        CGPoint(x: 125.0, y: 22.6)
    ]

    static let ThumbAnchorsMM: [CGRect] = [
        CGRect(x: 0, y: 75, width: 40, height: 40),
        CGRect(x: 40, y: 85, width: 40, height: 30),
        CGRect(x: 80, y: 85, width: 40, height: 30),
        CGRect(x: 120, y: 85, width: 40, height: 30)
    ]
    static let typingToggleRectMM = CGRect(x: 135, y: 0, width: 25, height: 75)

    private let trackpadSize: CGSize

    init(viewModel: ContentViewModel = ContentViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
        let size = CGSize(
            width: Self.trackpadWidthMM * Self.displayScale,
            height: Self.trackpadHeightMM * Self.displayScale
        )
        trackpadSize = size
        let initialScale = 1.0
        let initialPinkyScale = 1.2
        let initialKeyOffsetX = 0.0
        let initialKeyOffsetY = 0.0
        let initialLeftLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            keyScale: initialScale,
            labels: Self.mirroredLabels(ContentViewModel.leftGridLabels),
            widthScaleByLabel: Self.outerKeyWidthByLabel(pinkyScale: initialPinkyScale),
            columns: 6,
            rows: 3,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            keyOffsetMM: CGPoint(x: initialKeyOffsetX, y: initialKeyOffsetY),
            mirrored: true
        )
        let initialRightLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            keyScale: initialScale,
            labels: ContentViewModel.rightGridLabels,
            widthScaleByLabel: Self.outerKeyWidthByLabel(pinkyScale: initialPinkyScale),
            columns: 6,
            rows: 3,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            keyOffsetMM: CGPoint(x: -initialKeyOffsetX, y: initialKeyOffsetY)
        )
        _keyScale = State(initialValue: initialScale)
        _thumbScale = State(initialValue: initialScale)
        _pinkyScale = State(initialValue: initialPinkyScale)
        _keyOffsetX = State(initialValue: initialKeyOffsetX)
        _keyOffsetY = State(initialValue: initialKeyOffsetY)
        _leftLayout = State(initialValue: initialLeftLayout)
        _rightLayout = State(initialValue: initialRightLayout)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GlassToKey Studio")
                        .font(.title2)
                        .bold()
                    Text("Arrange, tune, and test")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Visuals", isOn: $visualsEnabled)
                    .toggleStyle(SwitchToggleStyle())
                if viewModel.isListening {
                    Button("Stop") {
                        viewModel.stop()
                        visualsEnabled = false
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start") {
                        viewModel.start()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trackpad Deck")
                        .font(.headline)
                    HStack(alignment: .top, spacing: 16) {
                        trackpadCanvas(
                            title: "Left Trackpad",
                            touches: visualsEnabled ? displayLeftTouches : [],
                            mirrored: true,
                            labels: Self.mirroredLabels(ContentViewModel.leftGridLabels),
                            customButtons: customButtons.filter { $0.side == .left },
                            visualsEnabled: visualsEnabled,
                            typingToggleRect: typingToggleRect(isLeft: true),
                            typingEnabled: viewModel.isTypingEnabled
                        )
                        trackpadCanvas(
                            title: "Right Trackpad",
                            touches: visualsEnabled ? displayRightTouches : [],
                            mirrored: false,
                            labels: ContentViewModel.rightGridLabels,
                            customButtons: customButtons.filter { $0.side == .right },
                            visualsEnabled: visualsEnabled,
                            typingToggleRect: typingToggleRect(isLeft: false),
                            typingEnabled: viewModel.isTypingEnabled
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Devices")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if viewModel.availableDevices.isEmpty {
                            Text("No trackpads detected.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Left Trackpad", selection: Binding(
                                get: { viewModel.leftDevice },
                                set: { device in
                                    viewModel.selectLeftDevice(device)
                                }
                            )) {
                                Text("None")
                                    .tag(nil as OMSDeviceInfo?)
                                ForEach(viewModel.availableDevices, id: \.self) { device in
                                    Text("\(device.deviceName) (ID: \(device.deviceID))")
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())

                            Picker("Right Trackpad", selection: Binding(
                                get: { viewModel.rightDevice },
                                set: { device in
                                    viewModel.selectRightDevice(device)
                                }
                            )) {
                                Text("None")
                                    .tag(nil as OMSDeviceInfo?)
                                ForEach(viewModel.availableDevices, id: \.self) { device in
                                    Text("\(device.deviceName) (ID: \(device.deviceID))")
                                        .tag(device as OMSDeviceInfo?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Layout Tuning")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                                GridRow {
                                    Text("Offset X")
                                    TextField(
                                        "0.0",
                                        value: $keyOffsetX,
                                        formatter: Self.keyOffsetFormatter
                                    )
                                    .frame(width: 60)
                                    Stepper(
                                        "",
                                        value: $keyOffsetX,
                                        in: Self.keyOffsetRange,
                                        step: 0.5
                                    )
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Offset Y")
                                    TextField(
                                        "0.0",
                                        value: $keyOffsetY,
                                        formatter: Self.keyOffsetFormatter
                                    )
                                    .frame(width: 60)
                                    Stepper(
                                        "",
                                        value: $keyOffsetY,
                                        in: Self.keyOffsetRange,
                                        step: 0.5
                                    )
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Key scale")
                                    TextField(
                                        "1.0",
                                        value: $keyScale,
                                        formatter: Self.keyScaleFormatter
                                    )
                                    .frame(width: 60)
                                    Stepper(
                                        "",
                                        value: $keyScale,
                                        in: Self.keyScaleRange,
                                        step: 0.05
                                    )
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Pinky scale")
                                    TextField(
                                        "1.2",
                                        value: $pinkyScale,
                                        formatter: Self.pinkyScaleFormatter
                                    )
                                    .frame(width: 60)
                                    Stepper(
                                        "",
                                        value: $pinkyScale,
                                        in: Self.pinkyScaleRange,
                                        step: 0.05
                                    )
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Thumb scale")
                                    TextField(
                                        "1.0",
                                        value: $thumbScale,
                                        formatter: Self.thumbScaleFormatter
                                    )
                                    .frame(width: 60)
                                    Stepper(
                                        "",
                                        value: $thumbScale,
                                        in: Self.thumbScaleRange,
                                        step: 0.05
                                    )
                                    .labelsHidden()
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.05))
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Custom Buttons")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Button("Add Left") {
                                    addCustomButton(side: .left)
                                }
                                Spacer()
                                Button("Add Right") {
                                    addCustomButton(side: .right)
                                }
                            }
                            if let selectedIndex = customButtons.firstIndex(where: { $0.id == selectedButtonID }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Picker("Side", selection: $customButtons[selectedIndex].side) {
                                        ForEach(TrackpadSide.allCases) { side in
                                            Text(side == .left ? "Left" : "Right")
                                                .tag(side)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    Picker("Action", selection: $customButtons[selectedIndex].action) {
                                        ForEach(KeyActionCatalog.presets, id: \.self) { action in
                                            Text(action.label).tag(action)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    HStack {
                                        Text("Selected")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Delete") {
                                            removeCustomButton(id: customButtons[selectedIndex].id)
                                        }
                                    }
                                }
                            } else {
                                Text("Select a button on the trackpad to edit.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Typing Test")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $testText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                            )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .frame(width: 420)
            }
        }
        .padding()
        .background(
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )
        )
        .frame(minWidth: trackpadSize.width * 2 + 480, minHeight: trackpadSize.height + 200)
        .onAppear {
            applySavedSettings()
            displayTouchData = viewModel.snapshotTouchData()
        }
        .onChange(of: visualsEnabled) { _ in
            saveSettings()
        }
        .onChange(of: visualsEnabled) { enabled in
            displayTouchData = enabled ? viewModel.snapshotTouchData() : []
        }
        .onChange(of: keyScale) { newValue in
            applyKeyScale(newValue)
            saveSettings()
        }
        .onChange(of: thumbScale) { newValue in
            applyThumbScale(newValue)
            saveSettings()
        }
        .onChange(of: pinkyScale) { newValue in
            applyPinkyScale(newValue)
            saveSettings()
        }
        .onChange(of: keyOffsetX) { newValue in
            applyKeyOffsetX(newValue)
            saveSettings()
        }
        .onChange(of: keyOffsetY) { newValue in
            applyKeyOffsetY(newValue)
            saveSettings()
        }
        .onChange(of: customButtons) { newValue in
            viewModel.updateCustomButtons(newValue)
            saveCustomButtons(newValue)
        }
        .task {
            for await _ in Timer.publish(
                every: displayRefreshInterval,
                on: .main,
                in: .common
            )
            .autoconnect()
            .values {
                guard visualsEnabled else { continue }
                displayTouchData = viewModel.snapshotTouchData()
            }
        }
    }

    private func trackpadCanvas(
        title: String,
        touches: [OMSTouchData],
        mirrored: Bool,
        labels: [[String]],
        customButtons: [CustomButton],
        visualsEnabled: Bool,
        typingToggleRect: CGRect?,
        typingEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            Group {
                if visualsEnabled || selectedButtonID != nil {
                    Canvas { context, _ in
                        let layout = mirrored ? leftLayout : rightLayout
                        drawSensorGrid(context: &context, size: trackpadSize, columns: 30, rows: 22)
                        drawKeyGrid(context: &context, keyRects: layout.keyRects)
                        drawCustomButtons(context: &context, buttons: customButtons)
                        if let typingToggleRect {
                            drawTypingToggle(
                                context: &context,
                                rect: typingToggleRect,
                                enabled: typingEnabled
                            )
                        }
                        drawGridLabels(context: &context, keyRects: layout.keyRects, labels: labels)
                        touches.forEach { touch in
                            let path = makeEllipse(touch: touch, size: trackpadSize)
                            context.fill(path, with: .color(.primary.opacity(Double(touch.total))))
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                }
            }
            .frame(width: trackpadSize.width, height: trackpadSize.height)
            .border(Color.primary)
            .overlay {
                if visualsEnabled || selectedButtonID != nil {
                    customButtonsOverlay(
                        buttons: customButtons,
                        selectedButtonID: $selectedButtonID
                    )
                }
            }
        }
    }

    private func makeEllipse(touch: OMSTouchData, size: CGSize) -> Path {
        let x = Double(touch.position.x) * size.width
        let y = Double(1.0 - touch.position.y) * size.height
        let u = size.width / 100.0
        let w = Double(touch.axis.major) * u
        let h = Double(touch.axis.minor) * u
        return Path(ellipseIn: CGRect(x: -0.5 * w, y: -0.5 * h, width: w, height: h))
            .rotation(.radians(Double(-touch.angle)), anchor: .topLeading)
            .offset(x: x, y: y)
            .path(in: CGRect(origin: .zero, size: size))
    }

    static func makeKeyLayout(
        size: CGSize,
        keyWidth: CGFloat,
        keyHeight: CGFloat,
        keyScale: Double,
        labels: [[String]],
        widthScaleByLabel: [String: CGFloat],
        columns: Int,
        rows: Int,
        trackpadWidth: CGFloat,
        trackpadHeight: CGFloat,
        columnAnchorsMM: [CGPoint],
        keyOffsetMM: CGPoint = .zero,
        mirrored: Bool = false
    ) -> ContentViewModel.Layout {
        let scaleX = size.width / trackpadWidth
        let scaleY = size.height / trackpadHeight
        let scaledKeyWidth = keyWidth * CGFloat(keyScale)
        let scaledKeyHeight = keyHeight * CGFloat(keyScale)
        let keySize = CGSize(width: scaledKeyWidth * scaleX, height: scaledKeyHeight * scaleY)
        let adjustedAnchorsMM = scaledColumnAnchorsMM(columnAnchorsMM, scale: CGFloat(keyScale))

        var keyRects: [[CGRect]] = Array(
            repeating: Array(repeating: .zero, count: columns),
            count: rows
        )
        for row in 0..<rows {
            for col in 0..<columns {
                let anchorMM = adjustedAnchorsMM[col]
                keyRects[row][col] = CGRect(
                    x: anchorMM.x * scaleX,
                    y: anchorMM.y * scaleY + CGFloat(row) * keySize.height,
                    width: keySize.width,
                    height: keySize.height
                )
            }
        }
        applyWidthScale(
            keyRects: &keyRects,
            labels: labels,
            widthScaleByLabel: widthScaleByLabel,
            canvasWidth: size.width
        )

        let offsetX = keyOffsetMM.x * scaleX
        let offsetY = keyOffsetMM.y * scaleY
        if mirrored {
            let mirroredKeyRects = keyRects.map { row in
                row.map { rect in
                    CGRect(
                        x: size.width - rect.maxX,
                        y: rect.minY,
                        width: rect.width,
                        height: rect.height
                    )
                }
            }
            return ContentViewModel.Layout(
                keyRects: mirroredKeyRects.map { row in
                    row.map { rect in rect.offsetBy(dx: offsetX, dy: offsetY) }
                }
            )
        }

        return ContentViewModel.Layout(
            keyRects: keyRects.map { row in
                row.map { rect in rect.offsetBy(dx: offsetX, dy: offsetY) }
            }
        )
    }

    private static func applyWidthScale(
        keyRects: inout [[CGRect]],
        labels: [[String]],
        widthScaleByLabel: [String: CGFloat],
        canvasWidth: CGFloat
    ) {
        let midline = canvasWidth / 2.0
        for row in 0..<keyRects.count {
            for col in 0..<keyRects[row].count {
                guard row < labels.count,
                      col < labels[row].count else { continue }
                let label = labels[row][col]
                guard let scale = widthScaleByLabel[label],
                      scale != 1.0 else { continue }
                let rect = keyRects[row][col]
                let extraWidth = rect.width * (scale - 1.0)
                if rect.midX < midline {
                    keyRects[row][col] = CGRect(
                        x: rect.minX - extraWidth,
                        y: rect.minY,
                        width: rect.width + extraWidth,
                        height: rect.height
                    )
                } else {
                    keyRects[row][col] = CGRect(
                        x: rect.minX,
                        y: rect.minY,
                        width: rect.width + extraWidth,
                        height: rect.height
                    )
                }
            }
        }
    }

    private static func scaledColumnAnchorsMM(
        _ anchors: [CGPoint],
        scale: CGFloat
    ) -> [CGPoint] {
        guard let originX = anchors.first?.x else { return anchors }
        return anchors.map { anchor in
            let offsetX = anchor.x - originX
            return CGPoint(x: originX + offsetX * scale, y: anchor.y)
        }
    }

    static func outerKeyWidthByLabel(pinkyScale: Double) -> [String: CGFloat] {
        let scale = CGFloat(pinkyScale)
        return [
            "Esc": scale,
            "Ctrl": scale,
            "Shift": scale,
            "Back": scale,
            "Ret": scale,
            "Tab": scale
        ]
    }

    private func normalizedKeyScale(_ value: Double) -> Double {
        min(max(value, Self.keyScaleRange.lowerBound), Self.keyScaleRange.upperBound)
    }

    private func normalizedThumbScale(_ value: Double) -> Double {
        min(max(value, Self.thumbScaleRange.lowerBound), Self.thumbScaleRange.upperBound)
    }

    private func normalizedPinkyScale(_ value: Double) -> Double {
        min(max(value, Self.pinkyScaleRange.lowerBound), Self.pinkyScaleRange.upperBound)
    }

    private func normalizedKeyOffset(_ value: Double) -> Double {
        min(max(value, Self.keyOffsetRange.lowerBound), Self.keyOffsetRange.upperBound)
    }

    private func applyKeyScale(_ value: Double) {
        let normalized = normalizedKeyScale(value)
        if normalized != value {
            keyScale = normalized
            return
        }
        rebuildLayouts()
    }

    private func applyThumbScale(_ value: Double) {
        let normalized = normalizedThumbScale(value)
        if normalized != value {
            thumbScale = normalized
            return
        }
        rebuildLayouts()
    }

    private func applyPinkyScale(_ value: Double) {
        let normalized = normalizedPinkyScale(value)
        if normalized != value {
            pinkyScale = normalized
            return
        }
        rebuildLayouts()
    }

    private func applyKeyOffsetX(_ value: Double) {
        let normalized = normalizedKeyOffset(value)
        if normalized != value {
            keyOffsetX = normalized
            return
        }
        rebuildLayouts()
    }

    private func applyKeyOffsetY(_ value: Double) {
        let normalized = normalizedKeyOffset(value)
        if normalized != value {
            keyOffsetY = normalized
            return
        }
        rebuildLayouts()
    }

    private func rebuildLayouts() {
        leftLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            keyScale: keyScale,
            labels: Self.mirroredLabels(ContentViewModel.leftGridLabels),
            widthScaleByLabel: Self.outerKeyWidthByLabel(pinkyScale: pinkyScale),
            columns: 6,
            rows: 3,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            keyOffsetMM: CGPoint(x: keyOffsetX, y: keyOffsetY),
            mirrored: true
        )
        rightLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            keyScale: keyScale,
            labels: ContentViewModel.rightGridLabels,
            widthScaleByLabel: Self.outerKeyWidthByLabel(pinkyScale: pinkyScale),
            columns: 6,
            rows: 3,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            keyOffsetMM: CGPoint(x: -keyOffsetX, y: keyOffsetY)
        )
        viewModel.configureLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: Self.mirroredLabels(ContentViewModel.leftGridLabels),
            rightLabels: ContentViewModel.rightGridLabels,
            leftTypingToggleRect: typingToggleRect(isLeft: true),
            rightTypingToggleRect: typingToggleRect(isLeft: false),
            trackpadSize: trackpadSize
        )
    }

    private func applySavedSettings() {
        visualsEnabled = storedVisualsEnabled
        keyScale = storedKeyScale
        thumbScale = storedThumbScale
        pinkyScale = storedPinkyScale
        keyOffsetX = storedKeyOffsetX
        keyOffsetY = storedKeyOffsetY
        loadCustomButtons()
        applyKeyScale(keyScale)
        applyThumbScale(thumbScale)
        applyPinkyScale(pinkyScale)
        applyKeyOffsetX(keyOffsetX)
        applyKeyOffsetY(keyOffsetY)
        if let leftDevice = deviceForID(storedLeftDeviceID) {
            viewModel.selectLeftDevice(leftDevice)
        }
        if let rightDevice = deviceForID(storedRightDeviceID) {
            viewModel.selectRightDevice(rightDevice)
        }
    }

    private func saveSettings() {
        storedLeftDeviceID = viewModel.leftDevice?.deviceID ?? ""
        storedRightDeviceID = viewModel.rightDevice?.deviceID ?? ""
        storedVisualsEnabled = visualsEnabled
        storedKeyScale = keyScale
        storedThumbScale = thumbScale
        storedPinkyScale = pinkyScale
        storedKeyOffsetX = keyOffsetX
        storedKeyOffsetY = keyOffsetY
    }

    private func loadCustomButtons() {
        if let decoded = CustomButtonStore.decode(storedCustomButtonsData),
           !decoded.isEmpty {
            customButtons = decoded
        } else {
            customButtons = CustomButtonDefaults.defaultButtons(
                trackpadWidth: Self.trackpadWidthMM,
                trackpadHeight: Self.trackpadHeightMM,
                thumbAnchorsMM: Self.ThumbAnchorsMM
            )
            saveCustomButtons(customButtons)
        }
        viewModel.updateCustomButtons(customButtons)
    }

    private func saveCustomButtons(_ buttons: [CustomButton]) {
        storedCustomButtonsData = CustomButtonStore.encode(buttons) ?? Data()
    }

    private func addCustomButton(side: TrackpadSide) {
        if !visualsEnabled {
            visualsEnabled = true
        }
        let action = KeyActionCatalog.action(for: "Space") ?? KeyActionCatalog.presets.first
        guard let action else { return }
        let newButton = CustomButton(
            id: UUID(),
            side: side,
            rect: defaultNewButtonRect(),
            action: action
        )
        customButtons.append(newButton)
        selectedButtonID = newButton.id
    }

    private func removeCustomButton(id: UUID) {
        customButtons.removeAll { $0.id == id }
        if selectedButtonID == id {
            selectedButtonID = nil
        }
    }

    private func updateCustomButton(id: UUID, update: (inout CustomButton) -> Void) {
        guard let index = customButtons.firstIndex(where: { $0.id == id }) else { return }
        update(&customButtons[index])
    }

    private func defaultNewButtonRect() -> NormalizedRect {
        let width: CGFloat = 0.18
        let height: CGFloat = 0.14
        let rect = NormalizedRect(
            x: 0.5 - width / 2.0,
            y: 0.5 - height / 2.0,
            width: width,
            height: height
        )
        return rect.clamped(
            minWidth: Self.minCustomButtonSize.width,
            minHeight: Self.minCustomButtonSize.height
        )
    }

    private func customButtonsOverlay(
        buttons: [CustomButton],
        selectedButtonID: Binding<UUID?>
    ) -> some View {
        ZStack(alignment: .topLeading) {
            let selectGesture = SpatialTapGesture()
                .onEnded { value in
                    let point = value.location
                    if let matched = buttons.last(where: { button in
                        button.rect.rect(in: trackpadSize).contains(point)
                    }) {
                        selectedButtonID.wrappedValue = matched.id
                    }
                }
            Color.clear
                .frame(width: trackpadSize.width, height: trackpadSize.height)
                .contentShape(Rectangle())
                .simultaneousGesture(selectGesture)
            ForEach(buttons) { button in
                let rect = button.rect.rect(in: trackpadSize)
                let isSelected = button.id == selectedButtonID.wrappedValue

                let dragGesture = DragGesture()
                    .onChanged { value in
                        let start = dragStartRects[button.id] ?? button.rect
                        dragStartRects[button.id] = start
                        let dx = value.translation.width / trackpadSize.width
                        let dy = value.translation.height / trackpadSize.height
                        let updated = NormalizedRect(
                            x: start.x + dx,
                            y: start.y + dy,
                            width: start.width,
                            height: start.height
                        ).clamped(
                            minWidth: Self.minCustomButtonSize.width,
                            minHeight: Self.minCustomButtonSize.height
                        )
                        updateCustomButton(id: button.id) { $0.rect = updated }
                    }
                    .onEnded { _ in
                        dragStartRects.removeValue(forKey: button.id)
                    }

                let baseButton = RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.9) : Color.clear,
                        lineWidth: 1.5
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(isSelected ? 0.08 : 0.02))
                    )
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .contentShape(Rectangle())

                Group {
                    if isSelected {
                        baseButton.gesture(dragGesture)
                    } else {
                        baseButton
                    }
                }
                if isSelected {
                    Text(button.action.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(
                            width: Self.resizeHandleSize,
                            height: Self.resizeHandleSize
                        )
                        .offset(
                            x: rect.maxX - Self.resizeHandleSize / 2.0,
                            y: rect.maxY - Self.resizeHandleSize / 2.0
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let start = resizeStartRects[button.id] ?? button.rect
                                    resizeStartRects[button.id] = start
                                    let dw = value.translation.width / trackpadSize.width
                                    let dh = value.translation.height / trackpadSize.height
                                    let maxWidth = 1.0 - start.x
                                    let maxHeight = 1.0 - start.y
                                    let width = min(
                                        maxWidth,
                                        max(Self.minCustomButtonSize.width, start.width + dw)
                                    )
                                    let height = min(
                                        maxHeight,
                                        max(Self.minCustomButtonSize.height, start.height + dh)
                                    )
                                    let updated = NormalizedRect(
                                        x: start.x,
                                        y: start.y,
                                        width: width,
                                        height: height
                                    )
                                    updateCustomButton(id: button.id) { $0.rect = updated }
                                }
                                .onEnded { _ in
                                    resizeStartRects.removeValue(forKey: button.id)
                                }
                        )
                }
            }
        }
    }

    private func deviceForID(_ deviceID: String) -> OMSDeviceInfo? {
        guard !deviceID.isEmpty else { return nil }
        return viewModel.availableDevices.first { $0.deviceID == deviceID }
    }

    private func typingToggleRect(isLeft: Bool) -> CGRect {
        let scaleX = trackpadSize.width / Self.trackpadWidthMM
        let scaleY = trackpadSize.height / Self.trackpadHeightMM
        let originXMM = isLeft
            ? Self.typingToggleRectMM.origin.x
            : Self.trackpadWidthMM - Self.typingToggleRectMM.maxX
        return CGRect(
            x: originXMM * scaleX,
            y: Self.typingToggleRectMM.origin.y * scaleY,
            width: Self.typingToggleRectMM.width * scaleX,
            height: Self.typingToggleRectMM.height * scaleY
        )
    }

    private func drawSensorGrid(
        context: inout GraphicsContext,
        size: CGSize,
        columns: Int,
        rows: Int
    ) {
        let strokeColor = Color.secondary.opacity(0.2)
        let lineWidth = CGFloat(0.5)

        let columnWidth = size.width / CGFloat(columns)
        let rowHeight = size.height / CGFloat(rows)

        for col in 0...columns {
            let x = CGFloat(col) * columnWidth
            let path = Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)
        }

        for row in 0...rows {
            let y = CGFloat(row) * rowHeight
            let path = Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)
        }
    }

    private func drawKeyGrid(context: inout GraphicsContext, keyRects: [[CGRect]]) {
        for row in keyRects {
            for rect in row {
                context.stroke(Path(rect), with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            }
        }
    }

    private func drawCustomButtons(
        context: inout GraphicsContext,
        buttons: [CustomButton]
    ) {
        let textStyle = Font.system(size: 10, weight: .semibold, design: .monospaced)
        for button in buttons {
            let rect = button.rect.rect(in: trackpadSize)
            context.fill(Path(rect), with: .color(Color.blue.opacity(0.12)))
            context.stroke(Path(rect), with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            let label = Text(button.action.label)
                .font(textStyle)
                .foregroundColor(.secondary)
            context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    private func drawTypingToggle(
        context: inout GraphicsContext,
        rect: CGRect,
        enabled: Bool
    ) {
        let fillColor = enabled ? Color.green.opacity(0.15) : Color.red.opacity(0.15)
        context.fill(Path(rect), with: .color(fillColor))
        context.stroke(Path(rect), with: .color(.secondary.opacity(0.6)), lineWidth: 1)
    }

    private func drawGridLabels(
        context: inout GraphicsContext,
        keyRects: [[CGRect]],
        labels: [[String]]
    ) {
        let textStyle = Font.system(size: 10, weight: .semibold, design: .monospaced)

        for row in 0..<keyRects.count {
            for col in 0..<keyRects[row].count {
                guard row < labels.count,
                      col < labels[row].count else { continue }
                let rect = keyRects[row][col]
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let text = Text(labels[row][col])
                    .font(textStyle)
                    .foregroundColor(.secondary)
                context.draw(text, at: center)
            }
        }
    }

    static func mirroredLabels(_ labels: [[String]]) -> [[String]] {
        labels.map { Array($0.reversed()) }
    }

    private var displayLeftTouches: [OMSTouchData] {
        touches(for: viewModel.leftDevice, in: displayTouchData)
    }

    private var displayRightTouches: [OMSTouchData] {
        touches(for: viewModel.rightDevice, in: displayTouchData)
    }

    private func touches(
        for device: OMSDeviceInfo?,
        in touches: [OMSTouchData]
    ) -> [OMSTouchData] {
        guard let deviceID = device?.deviceID else { return [] }
        return touches.filter { $0.deviceID == deviceID }
    }
}

#Preview {
    ContentView()
}
