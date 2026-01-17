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

        var position: GridKeyPosition {
            GridKeyPosition(side: side, row: row, column: column)
        }

        var storageKey: String {
            position.storageKey
        }
    }

    private struct GridLabel: Equatable {
        let primary: String
        let hold: String?
    }

    @StateObject private var viewModel: ContentViewModel
    @State private var testText = ""
    @State private var visualsEnabled = true
    @State private var editModeEnabled = false
    @State private var columnSettings: [ColumnLayoutSettings]
    @State private var leftLayout: ContentViewModel.Layout
    @State private var rightLayout: ContentViewModel.Layout
    @State private var customButtons: [CustomButton] = []
    @State private var selectedButtonID: UUID?
    @State private var selectedColumn: Int?
    @State private var selectedGridKey: SelectedGridKey?
    @State private var keyMappingsByLayer: LayeredKeyMappings = [:]
    @State private var layoutOption: TrackpadLayoutPreset = .sixByThree
    @State private var leftGridLabelInfo: [[GridLabel]] = []
    @State private var rightGridLabelInfo: [[GridLabel]] = []
    @AppStorage(GlassToKeyDefaultsKeys.leftDeviceID) private var storedLeftDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.rightDeviceID) private var storedRightDeviceID = ""
    @AppStorage(GlassToKeyDefaultsKeys.visualsEnabled) private var storedVisualsEnabled = true
    @AppStorage(GlassToKeyDefaultsKeys.columnSettings) private var storedColumnSettingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.layoutPreset) private var storedLayoutPreset = TrackpadLayoutPreset.sixByThree.rawValue
    @AppStorage(GlassToKeyDefaultsKeys.customButtons) private var storedCustomButtonsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.keyMappings) private var storedKeyMappingsData = Data()
    @AppStorage(GlassToKeyDefaultsKeys.tapHoldDuration) private var tapHoldDurationMs: Double = 200.0
    @AppStorage(GlassToKeyDefaultsKeys.twoFingerTapInterval) private var twoFingerTapIntervalMs: Double = 80.0
    @AppStorage(GlassToKeyDefaultsKeys.dragCancelDistance) private var dragCancelDistanceSetting: Double = 2.5
    @AppStorage(GlassToKeyDefaultsKeys.forceClickThreshold) private var forceClickThresholdSetting: Double = 0.7
    @AppStorage(GlassToKeyDefaultsKeys.forceClickHoldDuration) private var forceClickHoldDurationMs: Double = 0.0
    static let trackpadWidthMM: CGFloat = 160.0
    static let trackpadHeightMM: CGFloat = 114.9
    static let displayScale: CGFloat = 2.7
    static let baseKeyWidthMM: CGFloat = 18.0
    static let baseKeyHeightMM: CGFloat = 17.0
    static let minCustomButtonSize = CGSize(width: 0.05, height: 0.05)
    private static let columnScaleRange: ClosedRange<Double> = ColumnLayoutDefaults.scaleRange
    private static let columnOffsetPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.offsetPercentRange
    static let rowSpacingPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.rowSpacingPercentRange
    private static let dragCancelDistanceRange: ClosedRange<Double> = 0.5...15.0
    private static let tapHoldDurationRange: ClosedRange<Double> = 50.0...600.0
    private static let twoFingerTapIntervalRange: ClosedRange<Double> = 0.0...250.0
    private static let forceClickThresholdRange: ClosedRange<Double> = 0.0...1.0
    private static let forceClickHoldDurationRange: ClosedRange<Double> = 0.0...250.0
    private static let keyCornerRadius: CGFloat = 6.0
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
    private static let tapHoldDurationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.tapHoldDurationRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.tapHoldDurationRange.upperBound)
        return formatter
    }()
    private static let twoFingerTapIntervalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.twoFingerTapIntervalRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.twoFingerTapIntervalRange.upperBound)
        return formatter
    }()
    private static let dragCancelDistanceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.dragCancelDistanceRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.dragCancelDistanceRange.upperBound)
        return formatter
    }()
    private static let forceClickThresholdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.forceClickThresholdRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.forceClickThresholdRange.upperBound)
        return formatter
    }()
    private static let forceClickHoldDurationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.forceClickHoldDurationRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.forceClickHoldDurationRange.upperBound)
        return formatter
    }()
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
    private var layoutColumns: Int { layoutOption.columns }
    private var layoutRows: Int { layoutOption.rows }
    private var layoutColumnAnchors: [CGPoint] { layoutOption.columnAnchors }
    private var leftGridLabels: [[String]] { layoutOption.leftLabels }
    private var rightGridLabels: [[String]] { layoutOption.rightLabels }
    private var layoutSelectionBinding: Binding<TrackpadLayoutPreset> {
        Binding(
            get: { layoutOption },
            set: { handleLayoutOptionChange($0) }
        )
    }

    init(viewModel: ContentViewModel = ContentViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
        let size = CGSize(
            width: Self.trackpadWidthMM * Self.displayScale,
            height: Self.trackpadHeightMM * Self.displayScale
        )
        trackpadSize = size
        let defaultLayout = TrackpadLayoutPreset.sixByThree
        let initialColumnSettings = ColumnLayoutDefaults.defaultSettings(
            columns: defaultLayout.columns
        )
        let initialLeftLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: defaultLayout.columns,
            rows: defaultLayout.rows,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: defaultLayout.columnAnchors,
            columnSettings: initialColumnSettings,
            mirrored: true
        )
        let initialRightLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: defaultLayout.columns,
            rows: defaultLayout.rows,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: defaultLayout.columnAnchors,
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
                Button(action: {
                    viewModel.loadDevices(preserveSelection: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(.bordered)
                .help("Refresh trackpad list")
                Toggle("Edit", isOn: $editModeEnabled)
                    .toggleStyle(SwitchToggleStyle())
                Toggle("Visuals", isOn: $visualsEnabled)
                    .toggleStyle(SwitchToggleStyle())
                HStack(spacing: 6) {
                    Text("Layer 0")
                    Toggle("", isOn: layerToggleBinding)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                    Text("Layer 1")
                }
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
                    TrackpadDeckView(
                        viewModel: viewModel,
                        trackpadSize: trackpadSize,
                        leftLayout: leftLayout,
                        rightLayout: rightLayout,
                        leftGridLabelInfo: leftGridLabelInfo,
                        rightGridLabelInfo: rightGridLabelInfo,
                        leftGridLabels: leftGridLabels,
                        rightGridLabels: rightGridLabels,
                        customButtons: customButtons,
                        editModeEnabled: $editModeEnabled,
                         visualsEnabled: $visualsEnabled,
                        selectedButtonID: $selectedButtonID,
                        selectedColumn: $selectedColumn,
                        selectedGridKey: $selectedGridKey
                    )
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
                            HStack {
                                Text("Layout")
                                Spacer()
                                Picker("", selection: layoutSelectionBinding) {
                                    ForEach(TrackpadLayoutPreset.allCases) { preset in
                                        Text(preset.rawValue).tag(preset)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            if layoutOption.hasGrid {
                                if let selectedColumn,
                                   columnSettings.indices.contains(selectedColumn) {
                                    Text("Selected column \(selectedColumn + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 14) {
                                        ColumnTuningRow(
                                            title: "Scale",
                                            value: columnScaleBinding(for: selectedColumn),
                                            formatter: Self.columnScaleFormatter,
                                            range: Self.columnScaleRange,
                                            sliderStep: 0.05,
                                            showSlider: false
                                        )
                                        ColumnTuningRow(
                                            title: "X (%)",
                                            value: columnOffsetBinding(
                                                for: selectedColumn,
                                                axis: .x
                                            ),
                                            formatter: Self.columnOffsetFormatter,
                                            range: Self.columnOffsetPercentRange,
                                            sliderStep: 1.0,
                                            buttonStep: 0.5,
                                            showSlider: false
                                        )
                                        ColumnTuningRow(
                                            title: "Y (%)",
                                            value: columnOffsetBinding(
                                                for: selectedColumn,
                                                axis: .y
                                            ),
                                            formatter: Self.columnOffsetFormatter,
                                            range: Self.columnOffsetPercentRange,
                                            sliderStep: 1.0,
                                            buttonStep: 0.5,
                                            showSlider: false
                                        )
                                        ColumnTuningRow(
                                            title: "Pad",
                                            value: columnRowSpacingBinding(for: selectedColumn),
                                            formatter: Self.rowSpacingFormatter,
                                            range: Self.rowSpacingPercentRange,
                                            sliderStep: 1.0,
                                            buttonStep: 0.5,
                                            showSlider: false
                                        )
                                    }
                                } else {
                                    Text("Select a column on the trackpad to edit.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Layout has no grid. Pick one of the presets to show keys.")
                                    .font(.caption2)
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
                                    Picker("Action", selection: $customButtons[selectedIndex].action) {
                                        Text(KeyActionCatalog.noneLabel)
                                            .tag(KeyActionCatalog.noneAction)
                                        ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                            pickerLabel(for: action).tag(action)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    Picker("Hold Action", selection: customButtonHoldBinding(for: selectedIndex)) {
                                        Text("None").tag(nil as KeyAction?)
                                        ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                            pickerLabel(for: action).tag(action as KeyAction?)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    VStack(alignment: .leading, spacing: 14) {
                                        let xBinding = positionPercentBinding(
                                            for: selectedIndex,
                                            axis: .x
                                        )
                                        ColumnTuningRow(
                                            title: "X (%)",
                                            value: xBinding,
                                            formatter: Self.columnOffsetFormatter,
                                            range: positionPercentRange(
                                                for: selectedIndex,
                                                axis: .x
                                            ),
                                            sliderStep: 1.0,
                                            buttonStep: 0.5,
                                            showSlider: false
                                        )
                                        let yBinding = positionPercentBinding(
                                            for: selectedIndex,
                                            axis: .y
                                        )
                                        ColumnTuningRow(
                                            title: "Y (%)",
                                            value: yBinding,
                                            formatter: Self.columnOffsetFormatter,
                                            range: positionPercentRange(
                                                for: selectedIndex,
                                                axis: .y
                                            ),
                                            sliderStep: 1.0,
                                            buttonStep: 0.5,
                                            showSlider: false
                                        )
                                        let widthBinding = sizePercentBinding(
                                            for: selectedIndex,
                                            dimension: .width
                                        )
                                        ColumnTuningRow(
                                            title: "Width (%)",
                                            value: widthBinding,
                                            formatter: Self.columnOffsetFormatter,
                                            range: sizePercentRange(
                                                for: selectedIndex,
                                                dimension: .width
                                            ),
                                            sliderStep: 1.0,
                                            buttonStep: 0.5,
                                            showSlider: false
                                        )
                                        let heightBinding = sizePercentBinding(
                                            for: selectedIndex,
                                            dimension: .height
                                        )
                                        ColumnTuningRow(
                                            title: "Height (%)",
                                            value: heightBinding,
                                            formatter: Self.columnOffsetFormatter,
                                            range: sizePercentRange(
                                                for: selectedIndex,
                                                dimension: .height
                                            ),
                                            sliderStep: 1.0,
                                            buttonStep: 0.5,
                                            showSlider: false
                                        )
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
                                    Picker("Action", selection: keyActionBinding(for: gridKey)) {
                                        Text(KeyActionCatalog.noneLabel)
                                            .tag(KeyActionCatalog.noneAction)
                                        ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                            pickerLabel(for: action).tag(action)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    Picker("Hold Action", selection: holdActionBinding(for: gridKey)) {
                                        Text("None").tag(nil as KeyAction?)
                                        ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                            pickerLabel(for: action).tag(action as KeyAction?)
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
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                viewModel.clearTouchState()
                            }
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Typing Behavior")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("Tap/Hold (ms)")
                                TextField(
                                    "200",
                                    value: $tapHoldDurationMs,
                                    formatter: Self.tapHoldDurationFormatter
                                )
                                .frame(width: 60)
                                Slider(
                                    value: $tapHoldDurationMs,
                                    in: Self.tapHoldDurationRange,
                                    step: 10
                                )
                                .frame(minWidth: 120)
                            }
                            GridRow {
                                Text("Drag Cancel")
                                TextField(
                                    "2.5",
                                    value: $dragCancelDistanceSetting,
                                    formatter: Self.dragCancelDistanceFormatter
                                )
                                .frame(width: 60)
                                Slider(
                                    value: $dragCancelDistanceSetting,
                                    in: Self.dragCancelDistanceRange,
                                    step: 0.5
                                )
                                .frame(minWidth: 120)
                            }
                            GridRow {
                                Text("2-Finger Tap (ms)")
                                TextField(
                                    "80",
                                    value: $twoFingerTapIntervalMs,
                                    formatter: Self.twoFingerTapIntervalFormatter
                                )
                                .frame(width: 60)
                                Slider(
                                    value: $twoFingerTapIntervalMs,
                                    in: Self.twoFingerTapIntervalRange,
                                    step: 10
                                )
                                .frame(minWidth: 120)
                            }
                            GridRow {
                                Text("Force Delta")
                                TextField(
                                    "0.70",
                                    value: $forceClickThresholdSetting,
                                    formatter: Self.forceClickThresholdFormatter
                                )
                                .frame(width: 60)
                                Slider(
                                    value: $forceClickThresholdSetting,
                                    in: Self.forceClickThresholdRange,
                                    step: 0.05
                                )
                                .frame(minWidth: 120)
                            }
                            GridRow {
                                Text("Force Guard (ms)")
                                TextField(
                                    "0",
                                    value: $forceClickHoldDurationMs,
                                    formatter: Self.forceClickHoldDurationFormatter
                                )
                                .frame(width: 60)
                                Slider(
                                    value: $forceClickHoldDurationMs,
                                    in: Self.forceClickHoldDurationRange,
                                    step: 10
                                )
                                .frame(minWidth: 120)
                            }
                        }
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
        .frame(minWidth: trackpadSize.width * 2 + 520, minHeight: trackpadSize.height + 240)
        .onAppear {
            applySavedSettings()
        }
        .onChange(of: visualsEnabled) { enabled in
            if !enabled {
                selectedButtonID = nil
                selectedColumn = nil
                selectedGridKey = nil
            }
            saveSettings()
        }
        .onChange(of: editModeEnabled) { enabled in
            if enabled {
                visualsEnabled = true
            } else {
                selectedButtonID = nil
                selectedColumn = nil
                selectedGridKey = nil
            }
        }
        .onChange(of: columnSettings) { newValue in
            applyColumnSettings(newValue)
            saveSettings()
        }
        .onChange(of: customButtons) { newValue in
            viewModel.updateCustomButtons(newValue)
            saveCustomButtons(newValue)
        }
        .onChange(of: viewModel.activeLayer) { _ in
            selectedButtonID = nil
            selectedColumn = nil
            selectedGridKey = nil
            updateGridLabelInfo()
        }
        .onChange(of: keyMappingsByLayer) { newValue in
            viewModel.updateKeyMappings(newValue)
            saveKeyMappings(newValue)
            updateGridLabelInfo()
        }
        .onChange(of: tapHoldDurationMs) { newValue in
            viewModel.updateHoldThreshold(newValue / 1000.0)
        }
        .onChange(of: twoFingerTapIntervalMs) { newValue in
            viewModel.updateTwoFingerTapInterval(newValue / 1000.0)
        }
        .onChange(of: dragCancelDistanceSetting) { newValue in
            viewModel.updateDragCancelDistance(CGFloat(newValue))
        }
        .onChange(of: forceClickThresholdSetting) { newValue in
            viewModel.updateForceClickThreshold(newValue)
        }
        .onChange(of: forceClickHoldDurationMs) { newValue in
            viewModel.updateForceClickHoldDuration(newValue / 1000.0)
        }
    }

    private struct TrackpadDeckView: View {
        @ObservedObject var viewModel: ContentViewModel
        let trackpadSize: CGSize
        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        let leftGridLabelInfo: [[GridLabel]]
        let rightGridLabelInfo: [[GridLabel]]
        let leftGridLabels: [[String]]
        let rightGridLabels: [[String]]
        let customButtons: [CustomButton]
        @Binding var editModeEnabled: Bool
        @Binding var visualsEnabled: Bool
        @Binding var selectedButtonID: UUID?
        @Binding var selectedColumn: Int?
        @Binding var selectedGridKey: SelectedGridKey?
        @State private var displayTouchData = [OMSTouchData]()
        @State private var lastTouchRevision: UInt64 = 0
        private let displayRefreshInterval: TimeInterval = 1.0 / 60.0

        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                trackpadCanvas(
                    title: "Left Trackpad",
                    side: .left,
                    touches: visualsEnabled ? displayLeftTouches : [],
                    mirrored: true,
                    labelInfo: leftGridLabelInfo,
                    labels: leftGridLabels,
                    customButtons: customButtons(for: .left),
                    visualsEnabled: visualsEnabled,
                    selectedButtonID: selectedButtonID
                )
                trackpadCanvas(
                    title: "Right Trackpad",
                    side: .right,
                    touches: visualsEnabled ? displayRightTouches : [],
                    mirrored: false,
                    labelInfo: rightGridLabelInfo,
                    labels: rightGridLabels,
                    customButtons: customButtons(for: .right),
                    visualsEnabled: visualsEnabled,
                    selectedButtonID: selectedButtonID
                )
            }
            .onAppear {
                refreshTouchSnapshot(resetRevision: true)
            }
            .onChange(of: visualsEnabled) { enabled in
                if enabled {
                    refreshTouchSnapshot(resetRevision: true)
                } else {
                    displayTouchData = []
                }
            }
            .task(id: visualsEnabled) {
                guard visualsEnabled else { return }
                for await _ in Timer.publish(
                    every: displayRefreshInterval,
                    on: .main,
                    in: .common
                )
                .autoconnect()
                .values {
                    refreshTouchSnapshot(resetRevision: false)
                }
            }
        }

        private func refreshTouchSnapshot(resetRevision: Bool) {
            let sinceRevision: UInt64 = resetRevision ? 0 : lastTouchRevision
            if let snapshot = viewModel.snapshotTouchDataIfUpdated(since: sinceRevision) {
                displayTouchData = snapshot.data
                lastTouchRevision = snapshot.revision
            } else if resetRevision {
                displayTouchData = viewModel.snapshotTouchData()
            }
        }

        private var displayLeftTouches: [OMSTouchData] {
            touches(for: viewModel.leftDevice, in: displayTouchData)
        }

        private var displayRightTouches: [OMSTouchData] {
            touches(for: viewModel.rightDevice, in: displayTouchData)
        }

        private func customButtons(for side: TrackpadSide) -> [CustomButton] {
            customButtons.filter { $0.side == side && $0.layer == viewModel.activeLayer }
        }

        private func touches(
            for device: OMSDeviceInfo?,
            in touches: [OMSTouchData]
        ) -> [OMSTouchData] {
            guard let deviceID = device?.deviceID else { return [] }
            return touches.filter { $0.deviceID == deviceID }
        }

        private func trackpadCanvas(
            title: String,
            side: TrackpadSide,
            touches: [OMSTouchData],
            mirrored: Bool,
            labelInfo: [[GridLabel]],
            labels: [[String]],
            customButtons: [CustomButton],
            visualsEnabled: Bool,
            selectedButtonID: UUID?
        ) -> some View {
            return VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                Group {
                    if visualsEnabled || selectedButtonID != nil {
                        let layout = mirrored ? leftLayout : rightLayout
                        let selectedKeyForCanvas = selectedGridKey?.side == side ? selectedGridKey : nil
                        ZStack {
                            TrackpadBaseLayer(
                                keyRects: layout.keyRects,
                                labelInfo: labelInfo,
                                customButtons: customButtons,
                                trackpadSize: trackpadSize
                            )
                            .equatable()
                        TrackpadSelectionLayer(
                            keyRects: layout.keyRects,
                            selectedColumn: editModeEnabled ? selectedColumn : nil,
                            selectedKey: editModeEnabled ? selectedKeyForCanvas : nil
                        )
                        .equatable()
                        if visualsEnabled {
                            TrackpadTouchLayer(
                                revision: lastTouchRevision,
                                    touches: touches,
                                    trackpadSize: trackpadSize
                                )
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
                if editModeEnabled {
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
                        viewModel.clearTouchState()
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

                    let baseButton = RoundedRectangle(cornerRadius: ContentView.keyCornerRadius)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.9) : Color.clear,
                            lineWidth: 1.5
                        )
                        .background(
                            RoundedRectangle(cornerRadius: ContentView.keyCornerRadius)
                                .fill(Color.accentColor.opacity(isSelected ? 0.08 : 0.02))
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)

                    baseButton
                    if isSelected {
                        VStack(spacing: 2) {
                            Text(button.action.label)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let holdLabel = button.hold?.label {
                                Text(holdLabel)
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.7))
                            }
                        }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                    }
                }
            }
        }

        private func columnRects(
            for keyRects: [[CGRect]],
            trackpadSize: CGSize
        ) -> [CGRect] {
            guard let columnCount = keyRects.first?.count else { return [] }
            var rects = Array(repeating: CGRect.null, count: columnCount)
            for row in 0..<keyRects.count {
                for col in 0..<columnCount {
                    let rect = keyRects[row][col]
                    rects[col] = rects[col].union(rect)
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

        private func columnIndex(
            for point: CGPoint,
            columnRects: [CGRect]
        ) -> Int? {
            if let index = columnRects.firstIndex(where: { $0.contains(point) }) {
                return index
            }
            let columnCount = columnRects.count
            guard trackpadSize.width > 0, columnCount > 0 else { return nil }
            let normalizedX = min(max(point.x / trackpadSize.width, 0), 1)
            var index = Int(normalizedX * CGFloat(columnCount))
            if index == columnCount {
                index = columnCount - 1
            }
            return index
        }

        private func logColumnSelection(
            point: CGPoint,
            columnRects: [CGRect],
            resolvedIndex: Int?
        ) {
            #if DEBUG
            var debugInfo = "Point: \(point)"
            if let resolvedIndex {
                debugInfo += " resolvedIndex=\(resolvedIndex)"
            }
            debugInfo += " columnRects="
            let rectStrings = columnRects.enumerated().map { index, rect in
                "\(index):\(rect)"
            }
            debugInfo += rectStrings.joined(separator: ",")
            print(debugInfo)
            #endif
        }
    }

    private struct TrackpadBaseLayer: View, Equatable {
        let keyRects: [[CGRect]]
        let labelInfo: [[GridLabel]]
        let customButtons: [CustomButton]
        let trackpadSize: CGSize

        var body: some View {
            Canvas { context, _ in
                ContentView.drawSensorGrid(
                    context: &context,
                    size: trackpadSize,
                    columns: 30,
                    rows: 22
                )
                ContentView.drawKeyGrid(context: &context, keyRects: keyRects)
                ContentView.drawCustomButtons(
                    context: &context,
                    buttons: customButtons,
                    trackpadSize: trackpadSize
                )
                ContentView.drawGridLabels(
                    context: &context,
                    keyRects: keyRects,
                    labelInfo: labelInfo
                )
            }
        }
    }

    private struct TrackpadSelectionLayer: View, Equatable {
        let keyRects: [[CGRect]]
        let selectedColumn: Int?
        let selectedKey: SelectedGridKey?

        var body: some View {
            Canvas { context, _ in
                ContentView.drawKeySelection(
                    context: &context,
                    keyRects: keyRects,
                    selectedColumn: selectedColumn,
                    selectedKey: selectedKey
                )
            }
        }
    }

    private struct TrackpadTouchLayer: View {
        let revision: UInt64
        let touches: [OMSTouchData]
        let trackpadSize: CGSize

        var body: some View {
            Canvas { context, _ in
                touches.forEach { touch in
                    let path = ContentView.makeEllipse(touch: touch, size: trackpadSize)
                    context.fill(path, with: .color(.primary.opacity(Double(touch.total))))
                }
            }
        }
    }

    private static func makeEllipse(touch: OMSTouchData, size: CGSize) -> Path {
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
        guard columns > 0,
              rows > 0,
              columnAnchorsMM.count == columns else {
            return ContentViewModel.Layout(keyRects: [])
        }
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
            columns: layoutColumns
        )
        if normalized != settings {
            columnSettings = normalized
            return
        }
        rebuildLayouts()
    }

    private func handleLayoutOptionChange(_ newLayout: TrackpadLayoutPreset) {
        layoutOption = newLayout
        storedLayoutPreset = newLayout.rawValue
        selectedColumn = nil
        selectedGridKey = nil
        selectedButtonID = nil
        columnSettings = columnSettings(for: newLayout)
        updateGridLabelInfo()
        applyColumnSettings(columnSettings)
        saveSettings()
    }

    private func rebuildLayouts() {
        guard layoutColumns > 0,
              layoutRows > 0,
              layoutColumnAnchors.count == layoutColumns else {
            leftLayout = ContentViewModel.Layout(keyRects: [])
            rightLayout = ContentViewModel.Layout(keyRects: [])
            viewModel.configureLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: leftGridLabels,
                rightLabels: rightGridLabels,
                trackpadSize: trackpadSize
            )
            return
        }
        leftLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: layoutColumns,
            rows: layoutRows,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: layoutColumnAnchors,
            columnSettings: columnSettings,
            mirrored: true
        )
        rightLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: Self.baseKeyWidthMM,
            keyHeight: Self.baseKeyHeightMM,
            columns: layoutColumns,
            rows: layoutRows,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: layoutColumnAnchors,
            columnSettings: columnSettings
        )
        viewModel.configureLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: leftGridLabels,
            rightLabels: rightGridLabels,
            trackpadSize: trackpadSize
        )
    }

    private func applySavedSettings() {
        visualsEnabled = storedVisualsEnabled
        let resolvedLayout = TrackpadLayoutPreset(rawValue: storedLayoutPreset) ?? .sixByThree
        layoutOption = resolvedLayout
        selectedColumn = nil
        selectedGridKey = nil
        selectedButtonID = nil
        columnSettings = columnSettings(for: resolvedLayout)
        loadCustomButtons()
        loadKeyMappings()
        updateGridLabelInfo()
        applyColumnSettings(columnSettings)
        if let leftDevice = deviceForID(storedLeftDeviceID) {
            viewModel.selectLeftDevice(leftDevice)
        }
        if let rightDevice = deviceForID(storedRightDeviceID) {
        viewModel.selectRightDevice(rightDevice)
        }
        viewModel.updateHoldThreshold(tapHoldDurationMs / 1000.0)
        viewModel.updateTwoFingerTapInterval(twoFingerTapIntervalMs / 1000.0)
        viewModel.updateDragCancelDistance(CGFloat(dragCancelDistanceSetting))
        viewModel.updateForceClickThreshold(forceClickThresholdSetting)
        viewModel.updateForceClickHoldDuration(forceClickHoldDurationMs / 1000.0)
    }

    private func saveSettings() {
        storedLeftDeviceID = viewModel.leftDevice?.deviceID ?? ""
        storedRightDeviceID = viewModel.rightDevice?.deviceID ?? ""
        storedVisualsEnabled = visualsEnabled
        storedLayoutPreset = layoutOption.rawValue
        saveCurrentColumnSettings()
    }

    private func columnSettings(
        for layout: TrackpadLayoutPreset
    ) -> [ColumnLayoutSettings] {
        if let stored = LayoutColumnSettingsStorage.settings(
            for: layout,
            from: storedColumnSettingsData
        ) {
            return Self.normalizedColumnSettings(stored, columns: layout.columns)
        }
        if let migrated = legacyColumnSettings(for: layout) {
            return migrated
        }
        return ColumnLayoutDefaults.defaultSettings(columns: layout.columns)
    }

    private func legacyColumnSettings(for layout: TrackpadLayoutPreset) -> [ColumnLayoutSettings]? {
        let columns = layout.columns
        guard columns > 0 else { return nil }
        let defaults = UserDefaults.standard
        let hasLegacyScale = defaults.object(forKey: Self.legacyKeyScaleKey) != nil
        let hasLegacyOffsetX = defaults.object(forKey: Self.legacyKeyOffsetXKey) != nil
        let hasLegacyOffsetY = defaults.object(forKey: Self.legacyKeyOffsetYKey) != nil
        let hasLegacyRowSpacing = defaults.object(forKey: Self.legacyRowSpacingPercentKey) != nil
        guard hasLegacyScale || hasLegacyOffsetX || hasLegacyOffsetY || hasLegacyRowSpacing else {
            return nil
        }
        let keyScale = hasLegacyScale ? defaults.double(forKey: Self.legacyKeyScaleKey) : 1.0
        let offsetX = hasLegacyOffsetX ? defaults.double(forKey: Self.legacyKeyOffsetXKey) : 0.0
        let offsetY = hasLegacyOffsetY ? defaults.double(forKey: Self.legacyKeyOffsetYKey) : 0.0
        let rowSpacingPercent = hasLegacyRowSpacing
            ? defaults.double(forKey: Self.legacyRowSpacingPercentKey)
            : 0.0
        let offsetXPercent = offsetX / Double(Self.trackpadWidthMM) * 100.0
        let offsetYPercent = offsetY / Double(Self.trackpadHeightMM) * 100.0
        let migrated = ColumnLayoutDefaults.defaultSettings(columns: columns).map { _ in
            ColumnLayoutSettings(
                scale: keyScale,
                offsetXPercent: offsetXPercent,
                offsetYPercent: offsetYPercent,
                rowSpacingPercent: rowSpacingPercent
            )
        }
        return ColumnLayoutDefaults.normalizedSettings(migrated, columns: columns)
    }

    private func saveCurrentColumnSettings() {
        var map = LayoutColumnSettingsStorage.decode(from: storedColumnSettingsData) ?? [:]
        map[layoutOption.rawValue] = Self.normalizedColumnSettings(
            columnSettings,
            columns: layoutColumns
        )
        if let encoded = LayoutColumnSettingsStorage.encode(map) {
            storedColumnSettingsData = encoded
        } else {
            storedColumnSettingsData = Data()
        }
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
            keyMappingsByLayer = normalizedLayerMappings(decoded)
        } else {
            keyMappingsByLayer = [0: [:], 1: [:]]
        }
        viewModel.updateKeyMappings(keyMappingsByLayer)
    }

    private func saveKeyMappings(_ mappings: LayeredKeyMappings) {
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
            ,
            hold: nil,
            layer: viewModel.activeLayer
        )
        customButtons.append(newButton)
        selectedButtonID = newButton.id
    }

    private func customButtonHoldBinding(for index: Int) -> Binding<KeyAction?> {
        Binding(
            get: {
                customButtons.indices.contains(index) ? customButtons[index].hold : nil
            },
            set: { newValue in
                guard customButtons.indices.contains(index) else { return }
                customButtons[index].hold = newValue
            }
        )
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

    private struct ColumnTuningRow: View {
        let title: String
        let formatter: NumberFormatter
        let range: ClosedRange<Double>
        let sliderStep: Double
        let buttonStep: Double
        let showSlider: Bool
        @Binding var value: Double

            init(
                title: String,
                value: Binding<Double>,
                formatter: NumberFormatter,
                range: ClosedRange<Double>,
                sliderStep: Double,
                buttonStep: Double? = nil,
                showSlider: Bool? = nil
            ) {
                self.title = title
                self._value = value
                self.formatter = formatter
                self.range = range
                self.sliderStep = sliderStep
                self.buttonStep = buttonStep ?? sliderStep
                self.showSlider = showSlider ?? true
            }

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer()
                HStack(spacing: 12) {
                    if showSlider {
                        Slider(value: $value, in: range, step: sliderStep)
                            .frame(minWidth: 140, maxWidth: 220)
                    }
                    controlButtons
                }
            }
        }

        @ViewBuilder
        private var controlButtons: some View {
            HStack(spacing: 4) {
                Button {
                    adjust(-buttonStep)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                TextField(
                    "",
                    value: $value,
                    formatter: formatter
                )
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)

                Button {
                    adjust(buttonStep)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }

        private func adjust(_ delta: Double) {
            value = min(
                max(range.lowerBound, value + delta),
                range.upperBound
            )
        }
    }

    private enum CustomButtonAxis {
        case x
        case y
    }

    private enum CustomButtonDimension {
        case width
        case height
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

    private func sizePercentBinding(
        for index: Int,
        dimension: CustomButtonDimension
    ) -> Binding<Double> {
        Binding(
            get: {
                let rect = customButtons[index].rect
                let value = dimension == .width ? rect.width : rect.height
                return Double(value * 100.0)
            },
            set: { newValue in
                let rect = customButtons[index].rect
                let maxNormalized = dimension == .width
                    ? (1.0 - rect.x)
                    : (1.0 - rect.y)
                let minNormalized = dimension == .width
                    ? Self.minCustomButtonSize.width
                    : Self.minCustomButtonSize.height
                let upper = max(minNormalized, maxNormalized)
                let normalized = min(max(newValue / 100.0, minNormalized), upper)
                var updated = rect
                if dimension == .width {
                    updated.width = CGFloat(normalized)
                } else {
                    updated.height = CGFloat(normalized)
                }
                customButtons[index].rect = updated.clamped(
                    minWidth: Self.minCustomButtonSize.width,
                    minHeight: Self.minCustomButtonSize.height
                )
            }
        )
    }

    private func sizePercentRange(
        for index: Int,
        dimension: CustomButtonDimension
    ) -> ClosedRange<Double> {
        let rect = customButtons[index].rect
        let maxNormalized = dimension == .width
            ? (1.0 - rect.x)
            : (1.0 - rect.y)
        let minNormalized = dimension == .width
            ? Self.minCustomButtonSize.width
            : Self.minCustomButtonSize.height
        let upper = max(minNormalized, maxNormalized) * 100.0
        let lower = minNormalized * 100.0
        return lower...upper
    }

    private func deviceForID(_ deviceID: String) -> OMSDeviceInfo? {
        guard !deviceID.isEmpty else { return nil }
        return viewModel.availableDevices.first { $0.deviceID == deviceID }
    }

    private static func drawSensorGrid(
        context: inout GraphicsContext,
        size: CGSize,
        columns: Int,
        rows: Int
    ) {
        guard columns > 0, rows > 0 else { return }
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

    private static func drawKeyGrid(
        context: inout GraphicsContext,
        keyRects: [[CGRect]]
    ) {
        for row in keyRects {
            for rect in row {
                let keyPath = Path(roundedRect: rect, cornerRadius: Self.keyCornerRadius)
                context.stroke(keyPath, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            }
        }
    }

    private static func drawKeySelection(
        context: inout GraphicsContext,
        keyRects: [[CGRect]],
        selectedColumn: Int?,
        selectedKey: SelectedGridKey?
    ) {
        if let selectedColumn,
           keyRects.first?.indices.contains(selectedColumn) == true {
            for row in keyRects {
                let rect = row[selectedColumn]
                let keyPath = Path(roundedRect: rect, cornerRadius: Self.keyCornerRadius)
                context.fill(keyPath, with: .color(Color.accentColor.opacity(0.12)))
                context.stroke(keyPath, with: .color(Color.accentColor.opacity(0.8)), lineWidth: 1.5)
            }
        }

        if let key = selectedKey,
           keyRects.indices.contains(key.row),
           keyRects[key.row].indices.contains(key.column) {
            let rect = keyRects[key.row][key.column]
            let keyPath = Path(roundedRect: rect, cornerRadius: Self.keyCornerRadius)
            context.fill(keyPath, with: .color(Color.accentColor.opacity(0.18)))
            context.stroke(keyPath, with: .color(Color.accentColor.opacity(0.9)), lineWidth: 1.5)
        }
    }

    private static func drawCustomButtons(
        context: inout GraphicsContext,
        buttons: [CustomButton],
        trackpadSize: CGSize
    ) {
        let primaryStyle = Font.system(size: 10, weight: .semibold, design: .monospaced)
        let holdStyle = Font.system(size: 8, weight: .semibold, design: .monospaced)
        for button in buttons {
            let rect = button.rect.rect(in: trackpadSize)
            let buttonPath = Path(roundedRect: rect, cornerRadius: Self.keyCornerRadius)
            context.fill(buttonPath, with: .color(Color.blue.opacity(0.12)))
            context.stroke(buttonPath, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let primaryText = Text(button.action.displayText)
                .font(primaryStyle)
                .foregroundColor(.secondary)
            let primaryY = center.y - (button.hold != nil ? 4 : 0)
            context.draw(primaryText, at: CGPoint(x: center.x, y: primaryY))
            if let holdLabel = button.hold?.label {
                let holdText = Text(holdLabel)
                    .font(holdStyle)
                    .foregroundColor(.secondary.opacity(0.7))
                context.draw(holdText, at: CGPoint(x: center.x, y: center.y + 6))
            }
        }
    }

    private func labelInfo(for key: SelectedGridKey) -> (primary: String, hold: String?) {
        let mapping = effectiveKeyMapping(for: key)
        return (primary: mapping.primary.displayText, hold: mapping.hold?.label)
    }

    private func updateGridLabelInfo() {
        leftGridLabelInfo = gridLabelInfo(for: leftGridLabels, side: .left)
        rightGridLabelInfo = gridLabelInfo(for: rightGridLabels, side: .right)
    }

    private func gridLabelInfo(
        for labels: [[String]],
        side: TrackpadSide
    ) -> [[GridLabel]] {
        var output = labels.map { Array(repeating: GridLabel(primary: "", hold: nil), count: $0.count) }
        for row in 0..<labels.count {
            for col in 0..<labels[row].count {
                let key = SelectedGridKey(
                    row: row,
                    column: col,
                    label: labels[row][col],
                    side: side
                )
                let info = labelInfo(for: key)
                output[row][col] = GridLabel(primary: info.primary, hold: info.hold)
            }
        }
        return output
    }

    private func pickerLabel(for action: KeyAction) -> some View {
        let label = action.kind == .typingToggle
            ? KeyActionCatalog.typingToggleDisplayLabel
            : action.label
        return Text(label)
            .multilineTextAlignment(.center)
    }

    private func effectiveKeyMapping(for key: SelectedGridKey) -> KeyMapping {
        let layerMappings = keyMappingsForActiveLayer()
        if let mapping = layerMappings[key.storageKey] {
            return mapping
        }
        if let mapping = layerMappings[key.label] {
            return mapping
        }
        return defaultKeyMapping(for: key.label) ?? KeyMapping(primary: KeyAction(label: key.label, keyCode: 0, flags: 0), hold: nil)
    }

    private func updateKeyMapping(
        for key: SelectedGridKey,
        _ update: (inout KeyMapping) -> Void
    ) {
        let layer = viewModel.activeLayer
        var layerMappings = keyMappingsByLayer[layer] ?? [:]
        var mapping = layerMappings[key.storageKey]
            ?? layerMappings[key.label]
            ?? defaultKeyMapping(for: key.label)
            ?? KeyMapping(primary: KeyAction(label: key.label, keyCode: 0, flags: 0), hold: nil)
        update(&mapping)
        if let defaultMapping = defaultKeyMapping(for: key.label),
           defaultMapping == mapping {
            layerMappings.removeValue(forKey: key.storageKey)
            layerMappings.removeValue(forKey: key.label)
            keyMappingsByLayer[layer] = layerMappings
            return
        }
        layerMappings[key.storageKey] = mapping
        layerMappings.removeValue(forKey: key.label)
        keyMappingsByLayer[layer] = layerMappings
    }

    private func defaultKeyMapping(for label: String) -> KeyMapping? {
        guard let primary = KeyActionCatalog.action(for: label) else { return nil }
        return KeyMapping(primary: primary, hold: KeyActionCatalog.holdAction(for: label))
    }

    private func keyActionBinding(for key: SelectedGridKey) -> Binding<KeyAction> {
        Binding(
            get: {
                effectiveKeyMapping(for: key).primary
            },
            set: { newValue in
                updateKeyMapping(for: key) { $0.primary = newValue }
            }
        )
    }

    private func holdActionBinding(for key: SelectedGridKey) -> Binding<KeyAction?> {
        Binding(
            get: {
                effectiveKeyMapping(for: key).hold
            },
            set: { newValue in
                updateKeyMapping(for: key) { $0.hold = newValue }
            }
        )
    }

    private static func drawGridLabels(
        context: inout GraphicsContext,
        keyRects: [[CGRect]],
        labelInfo: [[GridLabel]]
    ) {
        let textStyle = Font.system(size: 10, weight: .semibold, design: .monospaced)

        for row in 0..<keyRects.count {
            for col in 0..<keyRects[row].count {
                guard row < labelInfo.count,
                      col < labelInfo[row].count else { continue }
                let rect = keyRects[row][col]
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let info = labelInfo[row][col]
                let primaryText = Text(info.primary)
                    .font(textStyle)
                    .foregroundColor(.secondary)
                context.draw(primaryText, at: CGPoint(x: center.x, y: center.y - 4))
                if let holdLabel = info.hold {
                    let holdText = Text(holdLabel)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                    context.draw(holdText, at: CGPoint(x: center.x, y: center.y + 6))
                }
            }
        }
    }

    private var layerToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.activeLayer == 1 },
            set: { isOn in
                viewModel.setPersistentLayer(isOn ? 1 : 0)
            }
        )
    }

    private func normalizedLayerMappings(_ mappings: LayeredKeyMappings) -> LayeredKeyMappings {
        let layer0 = mappings[0] ?? [:]
        let layer1 = mappings[1] ?? layer0
        return [0: layer0, 1: layer1]
    }

    private func keyMappingsForActiveLayer() -> [String: KeyMapping] {
        keyMappingsByLayer[viewModel.activeLayer] ?? [:]
    }
}

#Preview {
    ContentView()
}
