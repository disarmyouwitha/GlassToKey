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
    private struct SelectedGridKey: Equatable {
        let row: Int
        let column: Int
        let label: String
        let side: TrackpadSide
    }

    @StateObject private var viewModel: ContentViewModel
    @State private var testText = ""
    @State private var displayTouchData = [OMSTouchData]()
    @State private var visualsEnabled = true
    @State private var columnSettings: [ColumnLayoutSettings]
    @State private var leftLayout: ContentViewModel.Layout
    @State private var rightLayout: ContentViewModel.Layout
    @State private var customButtons: [CustomButton] = []
    @State private var selectedButtonID: UUID?
    @State private var selectedColumn: Int?
    @State private var selectedGridKey: SelectedGridKey?
    @State private var resizeStartRects: [UUID: NormalizedRect] = [:]
    @State private var keyMappings: [String: KeyMapping] = [:]
    @AppStorage(GlassToKeyDefaultsKeys.leftDeviceID) private var storedLeftDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.rightDeviceID) private var storedRightDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.visualsEnabled) private var storedVisualsEnabled = true
    @AppStorage(GlassToKeyDefaultsKeys.columnSettings) private var storedColumnSettingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.customButtons) private var storedCustomButtonsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.keyMappings) private var storedKeyMappingsData = Data()
    static let trackpadWidthMM: CGFloat = 160.0
    static let trackpadHeightMM: CGFloat = 114.9
    static let displayScale: CGFloat = 2.7
    static let baseKeyWidthMM: CGFloat = 18.0
    static let baseKeyHeightMM: CGFloat = 17.0
    static let columnCount: Int = 6
    static let rowCount: Int = 3
    static let minCustomButtonSize = CGSize(width: 0.05, height: 0.05)
    private static let resizeHandleSize: CGFloat = 10.0
    private static let columnScaleRange: ClosedRange<Double> = ColumnLayoutDefaults.scaleRange
    private static let columnOffsetPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.offsetPercentRange
    static let rowSpacingPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.rowSpacingPercentRange
    private static let columnScaleFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.columnScaleRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.columnScaleRange.upperBound)
        return formatter
    }()
    private static let columnOffsetFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.columnOffsetPercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.columnOffsetPercentRange.upperBound)
        return formatter
    }()
    private static let rowSpacingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.rowSpacingPercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.rowSpacingPercentRange.upperBound)
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
    private static let legacyKeyScaleKey = "GlassToKey.keyScale"
    private static let legacyKeyOffsetXKey = "GlassToKey.keyOffsetX"
    private static let legacyKeyOffsetYKey = "GlassToKey.keyOffsetY"
    private static let legacyRowSpacingPercentKey = "GlassToKey.rowSpacingPercent"

    static let ThumbAnchorsMM: [CGRect] = [
        CGRect(x: 0, y: 75, width: 40, height: 40),
        CGRect(x: 40, y: 85, width: 40, height: 30),
        CGRect(x: 80, y: 85, width: 40, height: 30),
        CGRect(x: 120, y: 85, width: 40, height: 30)
    ]
    private let trackpadSize: CGSize

    init(viewModel: ContentViewModel = ContentViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
        let size = CGSize(
            width: Self.trackpadWidthMM * Self.displayScale,
            height: Self.trackpadHeightMM * Self.displayScale
        )
        trackpadSize = size
        let initialColumnSettings = ColumnLayoutDefaults.defaultSettings(
            columns: Self.columnCount
        )
        let initialLeftLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: Self.columnCount,
            rows: Self.rowCount,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            columnSettings: initialColumnSettings,
            mirrored: true
        )
        let initialRightLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: Self.columnCount,
            rows: Self.rowCount,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            columnSettings: initialColumnSettings
        )
        _columnSettings = State(initialValue: initialColumnSettings)
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
                            side: .left,
                            touches: visualsEnabled ? displayLeftTouches : [],
                            mirrored: true,
                            labels: Self.mirroredLabels(ContentViewModel.leftGridLabels),
                            customButtons: customButtons.filter { $0.side == .left },
                            visualsEnabled: visualsEnabled
                        )
                        trackpadCanvas(
                            title: "Right Trackpad",
                            side: .right,
                            touches: visualsEnabled ? displayRightTouches : [],
                            mirrored: false,
                            labels: ContentViewModel.rightGridLabels,
                            customButtons: customButtons.filter { $0.side == .right },
                            visualsEnabled: visualsEnabled
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
                            Text("Column Tuning")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let selectedColumn,
                               columnSettings.indices.contains(selectedColumn) {
                                Text("Selected column \(selectedColumn + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                                    GridRow {
                                        Text("Scale")
                                        let scaleBinding = columnScaleBinding(for: selectedColumn)
                                        TextField(
                                            "1.0",
                                            value: scaleBinding,
                                            formatter: Self.columnScaleFormatter
                                        )
                                        .frame(width: 60)
                                        Stepper(
                                            "",
                                            value: scaleBinding,
                                            in: Self.columnScaleRange,
                                            step: 0.05
                                        )
                                        .labelsHidden()
                                    }
                                    GridRow {
                                        Text("Offset X (%)")
                                        let offsetBinding = columnOffsetBinding(
                                            for: selectedColumn,
                                            axis: .x
                                        )
                                        TextField(
                                            "0.0",
                                            value: offsetBinding,
                                            formatter: Self.columnOffsetFormatter
                                        )
                                        .frame(width: 60)
                                        Stepper(
                                            "",
                                            value: offsetBinding,
                                            in: Self.columnOffsetPercentRange,
                                            step: 0.5
                                        )
                                        .labelsHidden()
                                    }
                                    GridRow {
                                        Text("Offset Y (%)")
                                        let offsetBinding = columnOffsetBinding(
                                            for: selectedColumn,
                                            axis: .y
                                        )
                                        TextField(
                                            "0.0",
                                            value: offsetBinding,
                                            formatter: Self.columnOffsetFormatter
                                        )
                                        .frame(width: 60)
                                        Stepper(
                                            "",
                                            value: offsetBinding,
                                            in: Self.columnOffsetPercentRange,
                                            step: 0.5
                                        )
                                        .labelsHidden()
                                    }
                                    GridRow {
                                        Text("Spacing (%)")
                                        let spacingBinding = columnRowSpacingBinding(for: selectedColumn)
                                        TextField(
                                            "0.0",
                                            value: spacingBinding,
                                            formatter: Self.rowSpacingFormatter
                                        )
                                        .frame(width: 60)
                                        Stepper(
                                            "",
                                            value: spacingBinding,
                                            in: Self.rowSpacingPercentRange,
                                            step: 0.5
                                        )
                                        .labelsHidden()
                                    }
                                }
                            } else {
                                Text("Select a column on the trackpad to edit.")
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

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Button Tuning")
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
                                    Grid(alignment: .leading, verticalSpacing: 6) {
                                        GridRow {
                                            Text("X (%)")
                                            let xBinding = positionPercentBinding(
                                                for: selectedIndex,
                                                axis: .x
                                            )
                                            Slider(
                                                value: xBinding,
                                                in: positionPercentRange(
                                                    for: selectedIndex,
                                                    axis: .x
                                                ),
                                                step: 0.5
                                            )
                                            Text(xBinding.wrappedValue, format: .number.precision(.fractionLength(1)))
                                                .monospacedDigit()
                                        }
                                        GridRow {
                                            Text("Y (%)")
                                            let yBinding = positionPercentBinding(
                                                for: selectedIndex,
                                                axis: .y
                                            )
                                            Slider(
                                                value: yBinding,
                                                in: positionPercentRange(
                                                    for: selectedIndex,
                                                    axis: .y
                                                ),
                                                step: 0.5
                                            )
                                            Text(yBinding.wrappedValue, format: .number.precision(.fractionLength(1)))
                                                .monospacedDigit()
                                        }
                                    }
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
                            } else if let gridKey = selectedGridKey {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Selected key: \(gridKey.label)")
                                        .font(.subheadline)
                                        .bold()
                                    Picker("Action", selection: keyActionBinding(for: gridKey.label)) {
                                        ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                            Text(action.label).tag(action)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    Picker("Hold Action", selection: holdActionBinding(for: gridKey.label)) {
                                        Text("None").tag(nil as KeyAction?)
                                        ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                            Text(action.label).tag(action as KeyAction?)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                }
                            } else {
                                Text("Select a button or key on the trackpad to edit.")
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
        .onChange(of: visualsEnabled) { enabled in
            if !enabled {
                selectedButtonID = nil
                selectedColumn = nil
                selectedGridKey = nil
            }
            saveSettings()
            displayTouchData = enabled ? viewModel.snapshotTouchData() : []
        }
        .onChange(of: columnSettings) { newValue in
            applyColumnSettings(newValue)
            saveSettings()
        }
        .onChange(of: customButtons) { newValue in
            viewModel.updateCustomButtons(newValue)
            saveCustomButtons(newValue)
        }
        .onChange(of: keyMappings) { newValue in
            viewModel.updateKeyMappings(newValue)
            saveKeyMappings(newValue)
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
        side: TrackpadSide,
        touches: [OMSTouchData],
        mirrored: Bool,
        labels: [[String]],
        customButtons: [CustomButton],
        visualsEnabled: Bool
    ) -> some View {
        let labelProvider = labelInfoProvider(for: labels)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            Group {
                if visualsEnabled || selectedButtonID != nil {
                    Canvas { context, _ in
                        let layout = mirrored ? leftLayout : rightLayout
                        drawSensorGrid(context: &context, size: trackpadSize, columns: 30, rows: 22)
                        let selectedKeyForCanvas = selectedGridKey?.side == side ? selectedGridKey : nil
                        drawKeyGrid(
                            context: &context,
                            keyRects: layout.keyRects,
                            selectedColumn: selectedColumn,
                            selectedKey: selectedKeyForCanvas
                        )
                        drawCustomButtons(context: &context, buttons: customButtons)
                        drawGridLabels(
                            context: &context,
                            keyRects: layout.keyRects,
                            labels: labels,
                            labelProvider: labelProvider
                        )
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
                    let layout = mirrored ? leftLayout : rightLayout
                    customButtonsOverlay(
                        side: side,
                        layout: layout,
                        buttons: customButtons,
                        selectedButtonID: $selectedButtonID,
                        selectedColumn: $selectedColumn,
                        selectedGridKey: $selectedGridKey,
                        gridLabels: labels
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
        columns: Int,
        rows: Int,
        trackpadWidth: CGFloat,
        trackpadHeight: CGFloat,
        columnAnchorsMM: [CGPoint],
        columnSettings: [ColumnLayoutSettings],
        mirrored: Bool = false
    ) -> ContentViewModel.Layout {
        let scaleX = size.width / trackpadWidth
        let scaleY = size.height / trackpadHeight
        let resolvedSettings = normalizedColumnSettings(
            columnSettings,
            columns: columns
        )
        let columnScales = resolvedSettings.map { CGFloat($0.scale) }
        let adjustedAnchorsMM = scaledColumnAnchorsMM(
            columnAnchorsMM,
            columnScales: columnScales
        )

        var keyRects: [[CGRect]] = Array(
            repeating: Array(repeating: .zero, count: columns),
            count: rows
        )
        for row in 0..<rows {
            for col in 0..<columns {
                let anchorMM = adjustedAnchorsMM[col]
                let scale = columnScales[col]
                let keySize = CGSize(
                    width: keyWidth * scale * scaleX,
                    height: keyHeight * scale * scaleY
                )
                let rowSpacingPercent = resolvedSettings[col].rowSpacingPercent
                let rowSpacing = keySize.height * CGFloat(rowSpacingPercent / 100.0)
                keyRects[row][col] = CGRect(
                    x: anchorMM.x * scaleX,
                    y: anchorMM.y * scaleY + CGFloat(row) * (keySize.height + rowSpacing),
                    width: keySize.width,
                    height: keySize.height
                )
            }
        }

        let columnOffsets = resolvedSettings.map { setting in
            CGSize(
                width: size.width * CGFloat(setting.offsetXPercent / 100.0),
                height: size.height * CGFloat(setting.offsetYPercent / 100.0)
            )
        }
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
            var adjusted = mirroredKeyRects
            let mirroredOffsets = columnOffsets.map { offset in
                CGSize(width: -offset.width, height: offset.height)
            }
            applyColumnOffsets(keyRects: &adjusted, columnOffsets: mirroredOffsets)
            return ContentViewModel.Layout(keyRects: adjusted)
        }

        applyColumnOffsets(keyRects: &keyRects, columnOffsets: columnOffsets)
        return ContentViewModel.Layout(keyRects: keyRects)
    }

    private static func scaledColumnAnchorsMM(
        _ anchors: [CGPoint],
        columnScales: [CGFloat]
    ) -> [CGPoint] {
        guard let originX = anchors.first?.x else { return anchors }
        return anchors.enumerated().map { index, anchor in
            let scale = columnScales.indices.contains(index) ? columnScales[index] : 1.0
            let offsetX = anchor.x - originX
            return CGPoint(x: originX + offsetX * scale, y: anchor.y)
        }
    }

    private static func applyColumnOffsets(
        keyRects: inout [[CGRect]],
        columnOffsets: [CGSize]
    ) {
        guard !columnOffsets.isEmpty else { return }
        for rowIndex in 0..<keyRects.count {
            for colIndex in 0..<keyRects[rowIndex].count {
                let offset = columnOffsets.indices.contains(colIndex)
                    ? columnOffsets[colIndex]
                    : .zero
                keyRects[rowIndex][colIndex] = keyRects[rowIndex][colIndex]
                    .offsetBy(dx: offset.width, dy: offset.height)
            }
        }
    }

    private static func normalizedColumnSettings(
        _ settings: [ColumnLayoutSettings],
        columns: Int
    ) -> [ColumnLayoutSettings] {
        ColumnLayoutDefaults.normalizedSettings(settings, columns: columns)
    }

    private func normalizedColumnScale(_ value: Double) -> Double {
        min(max(value, Self.columnScaleRange.lowerBound), Self.columnScaleRange.upperBound)
    }

    private func normalizedColumnOffsetPercent(_ value: Double) -> Double {
        min(
            max(value, Self.columnOffsetPercentRange.lowerBound),
            Self.columnOffsetPercentRange.upperBound
        )
    }

    private func normalizedRowSpacingPercent(_ value: Double) -> Double {
        min(max(value, Self.rowSpacingPercentRange.lowerBound), Self.rowSpacingPercentRange.upperBound)
    }

    private func updateColumnSetting(
        index: Int,
        update: (inout ColumnLayoutSettings) -> Void
    ) {
        guard columnSettings.indices.contains(index) else { return }
        var setting = columnSettings[index]
        update(&setting)
        columnSettings[index] = setting
    }

    private func applyColumnSettings(_ settings: [ColumnLayoutSettings]) {
        let normalized = Self.normalizedColumnSettings(
            settings,
            columns: Self.columnCount
        )
        if normalized != settings {
            columnSettings = normalized
            return
        }
        rebuildLayouts()
    }

    private func rebuildLayouts() {
        leftLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: Self.columnCount,
            rows: Self.rowCount,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            columnSettings: columnSettings,
            mirrored: true
        )
        rightLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: Self.columnCount,
            rows: Self.rowCount,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            columnSettings: columnSettings
        )
        viewModel.configureLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: Self.mirroredLabels(ContentViewModel.leftGridLabels),
            rightLabels: ContentViewModel.rightGridLabels,
            trackpadSize: trackpadSize
        )
    }

    private func applySavedSettings() {
        visualsEnabled = storedVisualsEnabled
        columnSettings = resolvedStoredColumnSettings()
        loadCustomButtons()
        loadKeyMappings()
        applyColumnSettings(columnSettings)
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
        storedColumnSettingsData = ColumnLayoutStore.encode(columnSettings) ?? Data()
    }

    private func resolvedStoredColumnSettings() -> [ColumnLayoutSettings] {
        if let decoded = ColumnLayoutStore.decode(storedColumnSettingsData),
           decoded.count == Self.columnCount {
            return Self.normalizedColumnSettings(decoded, columns: Self.columnCount)
        }

        let defaults = UserDefaults.standard
        let hasLegacyScale = defaults.object(forKey: Self.legacyKeyScaleKey) != nil
        let hasLegacyOffsetX = defaults.object(forKey: Self.legacyKeyOffsetXKey) != nil
        let hasLegacyOffsetY = defaults.object(forKey: Self.legacyKeyOffsetYKey) != nil
        let hasLegacyRowSpacing = defaults.object(forKey: Self.legacyRowSpacingPercentKey) != nil
        if hasLegacyScale || hasLegacyOffsetX || hasLegacyOffsetY || hasLegacyRowSpacing {
            let keyScale = hasLegacyScale
                ? defaults.double(forKey: Self.legacyKeyScaleKey)
                : 1.0
            let offsetX = hasLegacyOffsetX
                ? defaults.double(forKey: Self.legacyKeyOffsetXKey)
                : 0.0
            let offsetY = hasLegacyOffsetY
                ? defaults.double(forKey: Self.legacyKeyOffsetYKey)
                : 0.0
            let rowSpacingPercent = hasLegacyRowSpacing
                ? defaults.double(forKey: Self.legacyRowSpacingPercentKey)
                : 0.0
            let offsetXPercent = offsetX / Double(Self.trackpadWidthMM) * 100.0
            let offsetYPercent = offsetY / Double(Self.trackpadHeightMM) * 100.0
            let migrated = ColumnLayoutDefaults.defaultSettings(columns: Self.columnCount).map { _ in
                ColumnLayoutSettings(
                    scale: keyScale,
                    offsetXPercent: offsetXPercent,
                    offsetYPercent: offsetYPercent,
                    rowSpacingPercent: rowSpacingPercent
                )
            }
            return Self.normalizedColumnSettings(migrated, columns: Self.columnCount)
        }

        return ColumnLayoutDefaults.defaultSettings(columns: Self.columnCount)
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

    private func loadKeyMappings() {
        if let decoded = KeyActionMappingStore.decode(storedKeyMappingsData) {
            keyMappings = decoded
        } else {
            keyMappings = [:]
        }
        viewModel.updateKeyMappings(keyMappings)
    }

    private func saveKeyMappings(_ mappings: [String: KeyMapping]) {
        storedKeyMappingsData = KeyActionMappingStore.encode(mappings) ?? Data()
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
        side: TrackpadSide,
        layout: ContentViewModel.Layout,
        buttons: [CustomButton],
        selectedButtonID: Binding<UUID?>,
        selectedColumn: Binding<Int?>,
        selectedGridKey: Binding<SelectedGridKey?>,
        gridLabels: [[String]]
    ) -> some View {
        ZStack(alignment: .topLeading) {
            let columnRects = columnRects(for: layout.keyRects, trackpadSize: trackpadSize)
            let selectGesture = DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onEnded { value in
                    let point = value.location
                    if let matched = buttons.last(where: { button in
                        button.rect.rect(in: trackpadSize).contains(point)
                    }) {
                        selectedButtonID.wrappedValue = matched.id
                        selectedColumn.wrappedValue = nil
                        selectedGridKey.wrappedValue = nil
                        return
                    }
                    selectedButtonID.wrappedValue = nil
                    if let key = gridKey(at: point, keyRects: layout.keyRects, labels: gridLabels, side: side) {
                        selectedGridKey.wrappedValue = key
                        selectedColumn.wrappedValue = key.column
                        return
                    }
                    selectedGridKey.wrappedValue = nil
                    let resolvedColumnIndex = columnIndex(for: point, columnRects: columnRects)
                    #if DEBUG
                    logColumnSelection(
                        point: point,
                        columnRects: columnRects,
                        resolvedIndex: resolvedColumnIndex
                    )
                    #endif
                    if let columnIndex = resolvedColumnIndex {
                        selectedColumn.wrappedValue = columnIndex
                    } else {
                        selectedColumn.wrappedValue = nil
                    }
                }
            Color.clear
                .frame(width: trackpadSize.width, height: trackpadSize.height)
                .contentShape(Rectangle())
                .simultaneousGesture(selectGesture)
            ForEach(buttons) { button in
                let rect = button.rect.rect(in: trackpadSize)
                let isSelected = button.id == selectedButtonID.wrappedValue

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
                    .allowsHitTesting(false)

                baseButton
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

    private enum ColumnAxis {
        case x
        case y
    }

    private func columnScaleBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: {
                columnSettings.indices.contains(index)
                    ? columnSettings[index].scale
                    : 1.0
            },
            set: { newValue in
                updateColumnSetting(index: index) { setting in
                    setting.scale = normalizedColumnScale(newValue)
                }
            }
        )
    }

    private func columnOffsetBinding(
        for index: Int,
        axis: ColumnAxis
    ) -> Binding<Double> {
        Binding(
            get: {
                guard columnSettings.indices.contains(index) else { return 0.0 }
                let setting = columnSettings[index]
                return axis == .x ? setting.offsetXPercent : setting.offsetYPercent
            },
            set: { newValue in
                updateColumnSetting(index: index) { setting in
                    let normalized = normalizedColumnOffsetPercent(newValue)
                    if axis == .x {
                        setting.offsetXPercent = normalized
                    } else {
                        setting.offsetYPercent = normalized
                    }
                }
            }
        )
    }

    private func columnRowSpacingBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: {
                columnSettings.indices.contains(index)
                    ? columnSettings[index].rowSpacingPercent
                    : 0.0
            },
            set: { newValue in
                updateColumnSetting(index: index) { setting in
                    setting.rowSpacingPercent = normalizedRowSpacingPercent(newValue)
                }
            }
        )
    }

    private enum CustomButtonAxis {
        case x
        case y
    }

    private func positionPercentBinding(
        for index: Int,
        axis: CustomButtonAxis
    ) -> Binding<Double> {
        Binding(
            get: {
                let rect = customButtons[index].rect
                let value = axis == .x ? rect.x : rect.y
                return Double(value * 100.0)
            },
            set: { newValue in
                let rect = customButtons[index].rect
                let maxNormalized = axis == .x
                    ? (1.0 - rect.width)
                    : (1.0 - rect.height)
                let upper = max(0.0, Double(maxNormalized))
                let normalized = min(max(newValue / 100.0, 0.0), upper)
                var updated = rect
                if axis == .x {
                    updated.x = CGFloat(normalized)
                } else {
                    updated.y = CGFloat(normalized)
                }
                customButtons[index].rect = updated.clamped(
                    minWidth: Self.minCustomButtonSize.width,
                    minHeight: Self.minCustomButtonSize.height
                )
            }
        )
    }

    private func positionPercentRange(
        for index: Int,
        axis: CustomButtonAxis
    ) -> ClosedRange<Double> {
        let rect = customButtons[index].rect
        let maxNormalized = axis == .x
            ? (1.0 - rect.width)
            : (1.0 - rect.height)
        let upper = max(0.0, Double(maxNormalized)) * 100.0
        return 0.0...upper
    }

    private func deviceForID(_ deviceID: String) -> OMSDeviceInfo? {
        guard !deviceID.isEmpty else { return nil }
        return viewModel.availableDevices.first { $0.deviceID == deviceID }
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

    private func drawKeyGrid(
        context: inout GraphicsContext,
        keyRects: [[CGRect]],
        selectedColumn: Int?,
        selectedKey: SelectedGridKey?
    ) {
        if let selectedColumn,
           keyRects.first?.indices.contains(selectedColumn) == true {
            for row in keyRects {
                let rect = row[selectedColumn]
                context.fill(Path(rect), with: .color(Color.accentColor.opacity(0.12)))
            }
        }

        if let key = selectedKey,
           keyRects.indices.contains(key.row),
           keyRects[key.row].indices.contains(key.column) {
            let rect = keyRects[key.row][key.column]
            context.fill(Path(rect), with: .color(Color.accentColor.opacity(0.18)))
        }

        for row in keyRects {
            for rect in row {
                context.stroke(Path(rect), with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            }
        }

        if let selectedColumn,
           keyRects.first?.indices.contains(selectedColumn) == true {
            for row in keyRects {
                let rect = row[selectedColumn]
                context.stroke(Path(rect), with: .color(Color.accentColor.opacity(0.8)), lineWidth: 1.5)
            }
        }

        if let key = selectedKey,
           keyRects.indices.contains(key.row),
           keyRects[key.row].indices.contains(key.column) {
            let rect = keyRects[key.row][key.column]
            context.stroke(Path(rect), with: .color(Color.accentColor.opacity(0.9)), lineWidth: 1.5)
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

    private func columnRects(
        for keyRects: [[CGRect]],
        trackpadSize: CGSize
    ) -> [CGRect] {
        guard let columnCount = keyRects.first?.count else { return [] }

        var rects = Array(repeating: CGRect.null, count: columnCount)
        for row in keyRects {
            for col in 0..<columnCount {
                let rect = row[col]
                rects[col] = rects[col].isNull ? rect : rects[col].union(rect)
            }
        }

        let width = trackpadSize.width
        let height = trackpadSize.height
        let sortedIndices = rects.enumerated()
            .sorted { lhs, rhs in
                let lhsMid = lhs.element.isNull ? 0 : lhs.element.midX
                let rhsMid = rhs.element.isNull ? 0 : rhs.element.midX
                return lhsMid < rhsMid
            }
            .map(\.offset)

        var boundaries = Array(repeating: CGFloat.zero, count: columnCount + 1)
        boundaries[0] = 0

        for physicalIndex in 0..<max(0, sortedIndices.count - 1) {
            let current = rects[sortedIndices[physicalIndex]]
            let next = rects[sortedIndices[physicalIndex + 1]]
            let currentMid = current.isNull ? 0 : current.midX
            let nextMid = next.isNull ? width : next.midX
            boundaries[physicalIndex + 1] = (currentMid + nextMid) / 2.0
        }

        boundaries[columnCount] = width

        let columnHeight = height
        var expandedRects = rects
        for physicalIndex in 0..<sortedIndices.count {
            let colIndex = sortedIndices[physicalIndex]
            let left = boundaries[physicalIndex]
            let right = boundaries[physicalIndex + 1]
            expandedRects[colIndex] = CGRect(
                x: left,
                y: 0,
                width: max(0, right - left),
                height: columnHeight
            )
        }

        return expandedRects
    }

    private func gridKey(
        at point: CGPoint,
        keyRects: [[CGRect]],
        labels: [[String]],
        side: TrackpadSide
    ) -> SelectedGridKey? {
        for rowIndex in 0..<keyRects.count {
            guard rowIndex < labels.count else { continue }
            for colIndex in 0..<keyRects[rowIndex].count {
                guard colIndex < labels[rowIndex].count else { continue }
                let rect = keyRects[rowIndex][colIndex]
                if rect.contains(point) {
                    return SelectedGridKey(
                        row: rowIndex,
                        column: colIndex,
                        label: labels[rowIndex][colIndex],
                        side: side
                    )
                }
            }
        }
        return nil
    }

    private func labelInfo(for label: String) -> (primary: String, hold: String?) {
        let mapping = effectiveKeyMapping(for: label)
        return (primary: mapping.primary.label, hold: mapping.hold?.label)
    }

    private func effectiveKeyMapping(for label: String) -> KeyMapping {
        if let mapping = keyMappings[label] {
            return mapping
        }
        return defaultKeyMapping(for: label) ?? KeyMapping(primary: KeyAction(label: label, keyCode: 0, flags: 0), hold: nil)
    }

    private func updateKeyMapping(
        for label: String,
        _ update: (inout KeyMapping) -> Void
    ) {
        var mapping = keyMappings[label]
            ?? defaultKeyMapping(for: label)
            ?? KeyMapping(primary: KeyAction(label: label, keyCode: 0, flags: 0), hold: nil)
        update(&mapping)
        if let defaultMapping = defaultKeyMapping(for: label),
           defaultMapping == mapping {
            keyMappings.removeValue(forKey: label)
            return
        }
        keyMappings[label] = mapping
    }

    private func defaultKeyMapping(for label: String) -> KeyMapping? {
        guard let primary = KeyActionCatalog.action(for: label) else { return nil }
        return KeyMapping(primary: primary, hold: KeyActionCatalog.holdAction(for: label))
    }

    private func labelInfoProvider(
        for labels: [[String]]
    ) -> (Int, Int) -> (primary: String, hold: String?) {
        { row, col in
            guard row < labels.count,
                  col < labels[row].count else {
                return (primary: "", hold: nil)
            }
            return labelInfo(for: labels[row][col])
        }
    }

    private func keyActionBinding(for label: String) -> Binding<KeyAction> {
        Binding(
            get: {
                effectiveKeyMapping(for: label).primary
            },
            set: { newValue in
                updateKeyMapping(for: label) { $0.primary = newValue }
            }
        )
    }

    private func holdActionBinding(for label: String) -> Binding<KeyAction?> {
        Binding(
            get: {
                effectiveKeyMapping(for: label).hold
            },
            set: { newValue in
                updateKeyMapping(for: label) { $0.hold = newValue }
            }
        )
    }

    private func columnIndex(
        for point: CGPoint,
        columnRects: [CGRect]
    ) -> Int? {
        if let index = columnRects.firstIndex(where: { $0.contains(point) }) {
            return index
        }
        guard trackpadSize.width > 0, Self.columnCount > 0 else { return nil }
        let normalizedX = min(max(point.x / trackpadSize.width, 0.0), 1.0)
        var index = Int(normalizedX * CGFloat(Self.columnCount))
        if index == Self.columnCount {
            index = Self.columnCount - 1
        }
        return index
    }

    #if DEBUG
    private func logColumnSelection(
        point: CGPoint,
        columnRects: [CGRect],
        resolvedIndex: Int?
    ) {
        guard trackpadSize.width > 0, trackpadSize.height > 0 else { return }
        let normalizedX = min(max(point.x / trackpadSize.width, 0.0), 1.0)
        let normalizedY = min(max(point.y / trackpadSize.height, 0.0), 1.0)
        let containsIndex = columnRects.enumerated().first(where: { $0.element.contains(point) })?.offset
        let method = containsIndex == nil ? "fallback" : "rect"
        let formattedPointX = String(format: "%.1f", point.x)
        let formattedPointY = String(format: "%.1f", point.y)
        let formattedNormX = String(format: "%.2f", normalizedX)
        let formattedNormY = String(format: "%.2f", normalizedY)
        print("[ColumnSelection] point=(\(formattedPointX),\(formattedPointY)) norm=(\(formattedNormX),\(formattedNormY)) method=\(method) rectIndex=\(containsIndex.map(String.init) ?? "none") resolved=\(resolvedIndex.map(String.init) ?? "nil")")
    }
    #endif

    private func drawGridLabels(
        context: inout GraphicsContext,
        keyRects: [[CGRect]],
        labels: [[String]],
        labelProvider: (Int, Int) -> (primary: String, hold: String?)
    ) {
        let textStyle = Font.system(size: 10, weight: .semibold, design: .monospaced)

        for row in 0..<keyRects.count {
            for col in 0..<keyRects[row].count {
                guard row < labels.count,
                      col < labels[row].count else { continue }
                let rect = keyRects[row][col]
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let provided = labelProvider(row, col)
                let primaryText = Text(provided.primary)
                    .font(textStyle)
                    .foregroundColor(.secondary)
                context.draw(primaryText, at: CGPoint(x: center.x, y: center.y - 4))
                if let holdLabel = provided.hold {
                    let holdText = Text(holdLabel)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                    context.draw(holdText, at: CGPoint(x: center.x, y: center.y + 6))
                }
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
