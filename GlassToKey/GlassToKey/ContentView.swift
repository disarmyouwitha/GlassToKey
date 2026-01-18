//
//  ContentView.swift
//  GlassToKey
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import Combine
import OpenMultitouchSupport
import QuartzCore
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

    private struct ColumnInspectorSelection: Equatable {
        let index: Int
        var settings: ColumnLayoutSettings
    }

    private struct ButtonInspectorSelection: Equatable {
        var button: CustomButton
    }

    private struct KeyInspectorSelection: Equatable {
        let key: SelectedGridKey
        var mapping: KeyMapping
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
    @State private var columnInspectorSelection: ColumnInspectorSelection?
    @State private var buttonInspectorSelection: ButtonInspectorSelection?
    @State private var keyInspectorSelection: KeyInspectorSelection?
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
    @AppStorage(GlassToKeyDefaultsKeys.autoResyncMissingTrackpads) private var storedAutoResyncMissingTrackpads = false
    @AppStorage(GlassToKeyDefaultsKeys.tapHoldDuration) private var tapHoldDurationMs: Double = GlassToKeySettings.tapHoldDurationMs
    @AppStorage(GlassToKeyDefaultsKeys.twoFingerTapInterval) private var twoFingerTapIntervalMs: Double = GlassToKeySettings.twoFingerTapIntervalMs
    @AppStorage(GlassToKeyDefaultsKeys.twoFingerSuppressionDuration) private var twoFingerSuppressionDurationMs: Double = GlassToKeySettings.twoFingerSuppressionMs
    @AppStorage(GlassToKeyDefaultsKeys.dragCancelDistance) private var dragCancelDistanceSetting: Double = GlassToKeySettings.dragCancelDistanceMm
    @AppStorage(GlassToKeyDefaultsKeys.forceClickCap) private var forceClickCapSetting: Double = GlassToKeySettings.forceClickCap
    static let trackpadWidthMM: CGFloat = 160.0
    static let trackpadHeightMM: CGFloat = 114.9
    static let displayScale: CGFloat = 2.7
    static let baseKeyWidthMM: CGFloat = 18.0
    static let baseKeyHeightMM: CGFloat = 17.0
    static let minCustomButtonSize = CGSize(width: 0.05, height: 0.05)
    fileprivate static let columnScaleRange: ClosedRange<Double> = ColumnLayoutDefaults.scaleRange
    fileprivate static let columnOffsetPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.offsetPercentRange
    fileprivate static let rowSpacingPercentRange: ClosedRange<Double> = ColumnLayoutDefaults.rowSpacingPercentRange
    fileprivate static let dragCancelDistanceRange: ClosedRange<Double> = 1.0...30.0
    fileprivate static let tapHoldDurationRange: ClosedRange<Double> = 50.0...600.0
    fileprivate static let twoFingerTapIntervalRange: ClosedRange<Double> = 0.0...20.0
    fileprivate static let forceClickCapRange: ClosedRange<Double> = 0.0...150.0
    fileprivate static let twoFingerSuppressionRange: ClosedRange<Double> = 0.0...100.0
    private static let keyCornerRadius: CGFloat = 6.0
    fileprivate static let columnScaleFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: ContentView.columnScaleRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.columnScaleRange.upperBound)
        return formatter
    }()
    fileprivate static let columnOffsetFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.columnOffsetPercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.columnOffsetPercentRange.upperBound)
        return formatter
    }()
    fileprivate static let rowSpacingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.rowSpacingPercentRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.rowSpacingPercentRange.upperBound)
        return formatter
    }()
    fileprivate static let tapHoldDurationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.tapHoldDurationRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.tapHoldDurationRange.upperBound)
        return formatter
    }()
    fileprivate static let twoFingerTapIntervalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.twoFingerTapIntervalRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.twoFingerTapIntervalRange.upperBound)
        return formatter
    }()
    fileprivate static let twoFingerSuppressionFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.twoFingerSuppressionRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.twoFingerSuppressionRange.upperBound)
        return formatter
    }()
    fileprivate static let dragCancelDistanceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.minimum = NSNumber(value: ContentView.dragCancelDistanceRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.dragCancelDistanceRange.upperBound)
        return formatter
    }()
    fileprivate static let forceClickCapFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.minimum = NSNumber(value: ContentView.forceClickCapRange.lowerBound)
        formatter.maximum = NSNumber(value: ContentView.forceClickCapRange.upperBound)
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
    private let onEditModeChange: ((Bool) -> Void)?

    private var layoutSelectionBinding: Binding<TrackpadLayoutPreset> {
        Binding(
            get: { layoutOption },
            set: { handleLayoutOptionChange($0) }
        )
    }

    init(
        viewModel: ContentViewModel = ContentViewModel(),
        onEditModeChange: ((Bool) -> Void)? = nil
    ) {
        self.onEditModeChange = onEditModeChange
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
        mainLayout
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
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            applySavedSettings()
        }
        .onDisappear {
            persistConfig()
        }
        .onChange(of: visualsEnabled) { enabled in
            viewModel.setTouchSnapshotRecordingEnabled(enabled)
            if !enabled {
                viewModel.clearVisualCaches()
                editModeEnabled = false
                selectedButtonID = nil
                selectedColumn = nil
                selectedGridKey = nil
            }
        }
        .onChange(of: editModeEnabled) { enabled in
            if enabled {
                visualsEnabled = true
            } else {
                selectedButtonID = nil
                selectedColumn = nil
                selectedGridKey = nil
            }
            onEditModeChange?(enabled)
        }
        .onAppear {
            viewModel.setAutoResyncEnabled(storedAutoResyncMissingTrackpads)
        }
        .onChange(of: columnSettings) { newValue in
            applyColumnSettings(newValue)
            refreshColumnInspectorSelection()
        }
        .onChange(of: customButtons) { newValue in
            viewModel.updateCustomButtons(newValue)
            refreshButtonInspectorSelection()
        }
        .onChange(of: viewModel.activeLayer) { _ in
            selectedButtonID = nil
            selectedColumn = nil
            selectedGridKey = nil
            updateGridLabelInfo()
        }
        .onChange(of: keyMappingsByLayer) { newValue in
            viewModel.updateKeyMappings(newValue)
            updateGridLabelInfo()
            refreshKeyInspectorSelection()
        }
        .onChange(of: selectedButtonID) { _ in
            refreshButtonInspectorSelection()
        }
        .onChange(of: selectedColumn) { _ in
            refreshColumnInspectorSelection()
        }
        .onChange(of: selectedGridKey) { _ in
            refreshKeyInspectorSelection()
        }
        .onChange(of: tapHoldDurationMs) { newValue in
            viewModel.updateHoldThreshold(newValue / 1000.0)
        }
        .onChange(of: twoFingerTapIntervalMs) { newValue in
            viewModel.updateTwoFingerTapInterval(newValue / 1000.0)
        }
        .onChange(of: twoFingerSuppressionDurationMs) { newValue in
            viewModel.updateTwoFingerSuppressionDuration(newValue / 1000.0)
        }
        .onChange(of: dragCancelDistanceSetting) { newValue in
            viewModel.updateDragCancelDistance(CGFloat(newValue))
        }
        .onChange(of: forceClickCapSetting) { newValue in
            viewModel.updateForceClickCap(newValue)
        }
    }

    @ViewBuilder
    private var mainLayout: some View {
        VStack(spacing: 16) {
            headerView
            contentRow
        }
    }

    private var headerView: some View {
        HeaderControlsView(
            editModeEnabled: $editModeEnabled,
            visualsEnabled: $visualsEnabled,
            layerToggleBinding: layerToggleBinding,
            isListening: viewModel.isListening,
            onStart: {
                viewModel.start()
            },
            onStop: {
                viewModel.stop()
                visualsEnabled = false
            }
        )
    }

    private var contentRow: some View {
        HStack(alignment: .top, spacing: 18) {
            trackpadSectionView
            rightSidebarView
        }
    }

    private var trackpadSectionView: some View {
        TrackpadSectionView(
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
            lastHitLeft: viewModel.debugLastHitLeft,
            lastHitRight: viewModel.debugLastHitRight,
            selectedButtonID: $selectedButtonID,
            selectedColumn: $selectedColumn,
            selectedGridKey: $selectedGridKey,
            testText: $testText
        )
    }

    private var rightSidebarView: some View {
        RightSidebarView(
            viewModel: viewModel,
            autoResyncEnabled: $storedAutoResyncMissingTrackpads,
            layoutSelection: layoutSelectionBinding,
            layoutOption: layoutOption,
            columnSelection: columnInspectorSelection,
            buttonSelection: buttonInspectorSelection,
            keySelection: keyInspectorSelection,
            editModeEnabled: editModeEnabled,
            tapHoldDurationMs: $tapHoldDurationMs,
            dragCancelDistanceSetting: $dragCancelDistanceSetting,
            twoFingerTapIntervalMs: $twoFingerTapIntervalMs,
            twoFingerSuppressionDurationMs: $twoFingerSuppressionDurationMs,
            forceClickCapSetting: $forceClickCapSetting,
            onRefreshDevices: {
                viewModel.loadDevices(preserveSelection: true)
            },
            onAutoResyncChange: { newValue in
                storedAutoResyncMissingTrackpads = newValue
                viewModel.setAutoResyncEnabled(newValue)
            },
            onAddCustomButton: { side in
                addCustomButton(side: side)
            },
            onRemoveCustomButton: { id in
                removeCustomButton(id: id)
            },
            onClearTouchState: {
                viewModel.clearTouchState()
            },
            onUpdateColumn: { index, update in
                updateColumnSettingAndSelection(index: index, update: update)
            },
            onUpdateButton: { id, update in
                updateCustomButtonAndSelection(id: id, update: update)
            },
            onUpdateKeyMapping: { key, update in
                updateKeyMappingAndSelection(key: key, update: update)
            }
        )
    }

    private struct HeaderControlsView: View {
        @Binding var editModeEnabled: Bool
        @Binding var visualsEnabled: Bool
        let layerToggleBinding: Binding<Bool>
        let isListening: Bool
        let onStart: () -> Void
        let onStop: () -> Void

        var body: some View {
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
                if isListening {
                    Button("Stop") {
                        onStop()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start") {
                        onStart()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private struct TrackpadSectionView: View {
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
        let lastHitLeft: ContentViewModel.DebugHit?
        let lastHitRight: ContentViewModel.DebugHit?
        @Binding var selectedButtonID: UUID?
        @Binding var selectedColumn: Int?
        @Binding var selectedGridKey: SelectedGridKey?
        @Binding var testText: String

        var body: some View {
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
                    lastHitLeft: lastHitLeft,
                    lastHitRight: lastHitRight,
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
        }
    }

    private struct RightSidebarView: View {
        @ObservedObject var viewModel: ContentViewModel
        @Binding var autoResyncEnabled: Bool
        let layoutSelection: Binding<TrackpadLayoutPreset>
        let layoutOption: TrackpadLayoutPreset
        let columnSelection: ColumnInspectorSelection?
        let buttonSelection: ButtonInspectorSelection?
        let keySelection: KeyInspectorSelection?
        let editModeEnabled: Bool
        @Binding var tapHoldDurationMs: Double
        @Binding var dragCancelDistanceSetting: Double
        @Binding var twoFingerTapIntervalMs: Double
        @Binding var twoFingerSuppressionDurationMs: Double
        @Binding var forceClickCapSetting: Double
        let onRefreshDevices: () -> Void
        let onAutoResyncChange: (Bool) -> Void
        let onAddCustomButton: (TrackpadSide) -> Void
        let onRemoveCustomButton: (UUID) -> Void
        let onClearTouchState: () -> Void
        let onUpdateColumn: (Int, (inout ColumnLayoutSettings) -> Void) -> Void
        let onUpdateButton: (UUID, (inout CustomButton) -> Void) -> Void
        let onUpdateKeyMapping: (SelectedGridKey, (inout KeyMapping) -> Void) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                DevicesSectionView(
                    availableDevices: viewModel.availableDevices,
                    leftDevice: viewModel.leftDevice,
                    rightDevice: viewModel.rightDevice,
                    autoResyncEnabled: $autoResyncEnabled,
                    onSelectLeft: { device in
                        viewModel.selectLeftDevice(device)
                    },
                    onSelectRight: { device in
                        viewModel.selectRightDevice(device)
                    },
                    onAutoResyncChange: onAutoResyncChange,
                    onRefresh: onRefreshDevices
                )

                HStack(alignment: .top, spacing: 12) {
                    ColumnTuningSectionView(
                        layoutSelection: layoutSelection,
                        layoutOption: layoutOption,
                        selection: columnSelection,
                        onUpdateColumn: onUpdateColumn
                    )
                    ButtonTuningSectionView(
                        buttonSelection: buttonSelection,
                        keySelection: keySelection,
                        onAddCustomButton: onAddCustomButton,
                        onRemoveCustomButton: onRemoveCustomButton,
                        onClearTouchState: onClearTouchState,
                        onUpdateButton: onUpdateButton,
                        onUpdateKeyMapping: onUpdateKeyMapping
                    )
                }

                if !editModeEnabled {
                    TypingTuningSectionView(
                        tapHoldDurationMs: $tapHoldDurationMs,
                        dragCancelDistanceSetting: $dragCancelDistanceSetting,
                        twoFingerTapIntervalMs: $twoFingerTapIntervalMs,
                        twoFingerSuppressionDurationMs: $twoFingerSuppressionDurationMs,
                        forceClickCapSetting: $forceClickCapSetting
                    )
                }
            }
            .frame(width: 420)
        }
    }

    private struct DevicesSectionView: View {
        let availableDevices: [OMSDeviceInfo]
        let leftDevice: OMSDeviceInfo?
        let rightDevice: OMSDeviceInfo?
        @Binding var autoResyncEnabled: Bool
        let onSelectLeft: (OMSDeviceInfo?) -> Void
        let onSelectRight: (OMSDeviceInfo?) -> Void
        let onAutoResyncChange: (Bool) -> Void
        let onRefresh: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Devices")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if availableDevices.isEmpty {
                    Text("No trackpads detected.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Left Trackpad", selection: Binding(
                        get: { leftDevice },
                        set: { device in
                            onSelectLeft(device)
                        }
                    )) {
                        Text("None")
                            .tag(nil as OMSDeviceInfo?)
                        ForEach(availableDevices, id: \.self) { device in
                            Text("\(device.deviceName) (ID: \(device.deviceID))")
                                .tag(device as OMSDeviceInfo?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())

                    Picker("Right Trackpad", selection: Binding(
                        get: { rightDevice },
                        set: { device in
                            onSelectRight(device)
                        }
                    )) {
                        Text("None")
                            .tag(nil as OMSDeviceInfo?)
                        ForEach(availableDevices, id: \.self) { device in
                            Text("\(device.deviceName) (ID: \(device.deviceID))")
                                .tag(device as OMSDeviceInfo?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                HStack {
                    Toggle("Auto-resync disconnected trackpads", isOn: Binding(
                        get: { autoResyncEnabled },
                        set: { newValue in
                            autoResyncEnabled = newValue
                            onAutoResyncChange(newValue)
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle())
                    .help("Polls every 8 seconds to detect disconnected trackpads.")

                    Spacer()

                    Button(action: {
                        onRefresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh trackpad list")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private struct ColumnTuningSectionView: View {
        let layoutSelection: Binding<TrackpadLayoutPreset>
        let layoutOption: TrackpadLayoutPreset
        let selection: ColumnInspectorSelection?
        let onUpdateColumn: (Int, (inout ColumnLayoutSettings) -> Void) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Column Tuning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Layout")
                    Spacer()
                    Picker("", selection: layoutSelection) {
                        ForEach(TrackpadLayoutPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                if layoutOption.hasGrid {
                    if let selection {
                        Text("Selected column \(selection.index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 14) {
                            ColumnTuningRow(
                                title: "Scale",
                                value: Binding(
                                    get: { selection.settings.scale },
                                    set: { newValue in
                                        onUpdateColumn(selection.index) { setting in
                                            setting.scale = ContentView.normalizedColumnScale(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.columnScaleFormatter,
                                range: ContentView.columnScaleRange,
                                sliderStep: 0.05,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "X (%)",
                                value: Binding(
                                    get: { selection.settings.offsetXPercent },
                                    set: { newValue in
                                        onUpdateColumn(selection.index) { setting in
                                            setting.offsetXPercent = ContentView.normalizedColumnOffsetPercent(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.columnOffsetFormatter,
                                range: ContentView.columnOffsetPercentRange,
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Y (%)",
                                value: Binding(
                                    get: { selection.settings.offsetYPercent },
                                    set: { newValue in
                                        onUpdateColumn(selection.index) { setting in
                                            setting.offsetYPercent = ContentView.normalizedColumnOffsetPercent(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.columnOffsetFormatter,
                                range: ContentView.columnOffsetPercentRange,
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Pad",
                                value: Binding(
                                    get: { selection.settings.rowSpacingPercent },
                                    set: { newValue in
                                        onUpdateColumn(selection.index) { setting in
                                            setting.rowSpacingPercent = ContentView.normalizedRowSpacingPercent(newValue)
                                        }
                                    }
                                ),
                                formatter: ContentView.rowSpacingFormatter,
                                range: ContentView.rowSpacingPercentRange,
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
        }
    }

    private struct ButtonTuningSectionView: View {
        let buttonSelection: ButtonInspectorSelection?
        let keySelection: KeyInspectorSelection?
        let onAddCustomButton: (TrackpadSide) -> Void
        let onRemoveCustomButton: (UUID) -> Void
        let onClearTouchState: () -> Void
        let onUpdateButton: (UUID, (inout CustomButton) -> Void) -> Void
        let onUpdateKeyMapping: (SelectedGridKey, (inout KeyMapping) -> Void) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Button Tuning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Add Left") {
                        onAddCustomButton(.left)
                    }
                    Spacer()
                    Button("Add Right") {
                        onAddCustomButton(.right)
                    }
                }
                if let selection = buttonSelection {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Action", selection: Binding(
                            get: { selection.button.action },
                            set: { newValue in
                                onUpdateButton(selection.button.id) { button in
                                    button.action = newValue
                                }
                            }
                        )) {
                            Text(KeyActionCatalog.noneLabel)
                                .tag(KeyActionCatalog.noneAction)
                            ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                ContentView.pickerLabel(for: action).tag(action)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        Picker("Hold Action", selection: Binding(
                            get: { selection.button.hold },
                            set: { newValue in
                                onUpdateButton(selection.button.id) { button in
                                    button.hold = newValue
                                }
                            }
                        )) {
                            Text("None").tag(nil as KeyAction?)
                            ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                ContentView.pickerLabel(for: action).tag(action as KeyAction?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        VStack(alignment: .leading, spacing: 14) {
                            ColumnTuningRow(
                                title: "X (%)",
                                value: positionBinding(for: selection.button, axis: .x),
                                formatter: ContentView.columnOffsetFormatter,
                                range: positionRange(for: selection.button, axis: .x),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Y (%)",
                                value: positionBinding(for: selection.button, axis: .y),
                                formatter: ContentView.columnOffsetFormatter,
                                range: positionRange(for: selection.button, axis: .y),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Width (%)",
                                value: sizeBinding(for: selection.button, dimension: .width),
                                formatter: ContentView.columnOffsetFormatter,
                                range: sizeRange(for: selection.button, dimension: .width),
                                sliderStep: 1.0,
                                buttonStep: 0.5,
                                showSlider: false
                            )
                            ColumnTuningRow(
                                title: "Height (%)",
                                value: sizeBinding(for: selection.button, dimension: .height),
                                formatter: ContentView.columnOffsetFormatter,
                                range: sizeRange(for: selection.button, dimension: .height),
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
                                onRemoveCustomButton(selection.button.id)
                            }
                        }
                    }
                } else if let selection = keySelection {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected key: \(selection.key.label)")
                            .font(.subheadline)
                            .bold()
                        Picker("Action", selection: Binding(
                            get: { selection.mapping.primary },
                            set: { newValue in
                                onUpdateKeyMapping(selection.key) { mapping in
                                    mapping.primary = newValue
                                }
                            }
                        )) {
                            Text(KeyActionCatalog.noneLabel)
                                .tag(KeyActionCatalog.noneAction)
                            ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                ContentView.pickerLabel(for: action).tag(action)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        Picker("Hold Action", selection: Binding(
                            get: { selection.mapping.hold },
                            set: { newValue in
                                onUpdateKeyMapping(selection.key) { mapping in
                                    mapping.hold = newValue
                                }
                            }
                        )) {
                            Text("None").tag(nil as KeyAction?)
                            ForEach(KeyActionCatalog.holdPresets, id: \.self) { action in
                                ContentView.pickerLabel(for: action).tag(action as KeyAction?)
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
                    onClearTouchState()
                }
            )
        }

        private enum CustomButtonAxis {
            case x
            case y
        }

        private enum CustomButtonDimension {
            case width
            case height
        }

        private func positionBinding(
            for button: CustomButton,
            axis: CustomButtonAxis
        ) -> Binding<Double> {
            Binding(
                get: {
                    let value = axis == .x ? button.rect.x : button.rect.y
                    return Double(value * 100.0)
                },
                set: { newValue in
                    onUpdateButton(button.id) { updated in
                        let rect = updated.rect
                        let maxNormalized = axis == .x
                            ? (1.0 - rect.width)
                            : (1.0 - rect.height)
                        let upper = max(0.0, Double(maxNormalized))
                        let normalized = min(max(newValue / 100.0, 0.0), upper)
                        var next = rect
                        if axis == .x {
                            next.x = CGFloat(normalized)
                        } else {
                            next.y = CGFloat(normalized)
                        }
                        updated.rect = next.clamped(
                            minWidth: ContentView.minCustomButtonSize.width,
                            minHeight: ContentView.minCustomButtonSize.height
                        )
                    }
                }
            )
        }

        private func positionRange(
            for button: CustomButton,
            axis: CustomButtonAxis
        ) -> ClosedRange<Double> {
            let rect = button.rect
            let maxNormalized = axis == .x
                ? (1.0 - rect.width)
                : (1.0 - rect.height)
            let upper = max(0.0, Double(maxNormalized)) * 100.0
            return 0.0...upper
        }

        private func sizeBinding(
            for button: CustomButton,
            dimension: CustomButtonDimension
        ) -> Binding<Double> {
            Binding(
                get: {
                    let value = dimension == .width ? button.rect.width : button.rect.height
                    return Double(value * 100.0)
                },
                set: { newValue in
                    onUpdateButton(button.id) { updated in
                        let rect = updated.rect
                        let maxNormalized = dimension == .width
                            ? (1.0 - rect.x)
                            : (1.0 - rect.y)
                        let minNormalized = dimension == .width
                            ? ContentView.minCustomButtonSize.width
                            : ContentView.minCustomButtonSize.height
                        let upper = max(minNormalized, maxNormalized)
                        let normalized = min(max(newValue / 100.0, minNormalized), upper)
                        var next = rect
                        if dimension == .width {
                            next.width = CGFloat(normalized)
                        } else {
                            next.height = CGFloat(normalized)
                        }
                        updated.rect = next.clamped(
                            minWidth: ContentView.minCustomButtonSize.width,
                            minHeight: ContentView.minCustomButtonSize.height
                        )
                    }
                }
            )
        }

        private func sizeRange(
            for button: CustomButton,
            dimension: CustomButtonDimension
        ) -> ClosedRange<Double> {
            let rect = button.rect
            let maxNormalized = dimension == .width
                ? (1.0 - rect.x)
                : (1.0 - rect.y)
            let minNormalized = dimension == .width
                ? ContentView.minCustomButtonSize.width
                : ContentView.minCustomButtonSize.height
            let upper = max(minNormalized, maxNormalized) * 100.0
            let lower = minNormalized * 100.0
            return lower...upper
        }
    }

    private struct TypingTuningSectionView: View {
        @Binding var tapHoldDurationMs: Double
        @Binding var dragCancelDistanceSetting: Double
        @Binding var twoFingerTapIntervalMs: Double
        @Binding var twoFingerSuppressionDurationMs: Double
        @Binding var forceClickCapSetting: Double

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Typing Tuning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Tap/Hold (ms)")
                        TextField(
                            "200",
                            value: $tapHoldDurationMs,
                            formatter: ContentView.tapHoldDurationFormatter
                        )
                        .frame(width: 60)
                        Slider(
                            value: $tapHoldDurationMs,
                            in: ContentView.tapHoldDurationRange,
                            step: 10
                        )
                        .frame(minWidth: 120)
                    }
                    GridRow {
                        Text("Drag Cancel")
                        TextField(
                            "1",
                            value: $dragCancelDistanceSetting,
                            formatter: ContentView.dragCancelDistanceFormatter
                        )
                        .frame(width: 60)
                        Slider(
                            value: $dragCancelDistanceSetting,
                            in: ContentView.dragCancelDistanceRange,
                            step: 1
                        )
                        .frame(minWidth: 120)
                    }
                    GridRow {
                        Text("2-Finger Tap (ms)")
                        TextField(
                            "10",
                            value: $twoFingerTapIntervalMs,
                            formatter: ContentView.twoFingerTapIntervalFormatter
                        )
                        .frame(width: 60)
                        Slider(
                            value: $twoFingerTapIntervalMs,
                            in: ContentView.twoFingerTapIntervalRange,
                            step: 1
                        )
                        .frame(minWidth: 120)
                    }
                    GridRow {
                        Text("2-Finger Suppress (ms)")
                        TextField(
                            "0",
                            value: $twoFingerSuppressionDurationMs,
                            formatter: ContentView.twoFingerSuppressionFormatter
                        )
                        .frame(width: 60)
                        Slider(
                            value: $twoFingerSuppressionDurationMs,
                            in: ContentView.twoFingerSuppressionRange,
                            step: 5
                        )
                        .frame(minWidth: 120)
                    }
                    GridRow {
                        Text("Force Cap (g)")
                        TextField(
                            "0",
                            value: $forceClickCapSetting,
                            formatter: ContentView.forceClickCapFormatter
                        )
                        .frame(width: 60)
                        Slider(
                            value: $forceClickCapSetting,
                            in: ContentView.forceClickCapRange,
                            step: 5
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
        let lastHitLeft: ContentViewModel.DebugHit?
        let lastHitRight: ContentViewModel.DebugHit?
        @Binding var selectedButtonID: UUID?
        @Binding var selectedColumn: Int?
        @Binding var selectedGridKey: SelectedGridKey?
        @State private var displayLeftTouchesState = [OMSTouchData]()
        @State private var displayRightTouchesState = [OMSTouchData]()
        @State private var lastTouchRevision: UInt64 = 0
        @State private var lastDisplayUpdateTime: TimeInterval = 0
        @State private var lastDisplayedHadTouches = false
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
                    lastHit: lastHitLeft,
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
                    lastHit: lastHitRight,
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
                    displayLeftTouchesState = []
                    displayRightTouchesState = []
                    lastDisplayedHadTouches = false
                }
            }
            .task(id: visualsEnabled) {
                guard visualsEnabled else { return }
                var iterator = viewModel.touchRevisionUpdates.makeAsyncIterator()
                while !Task.isCancelled {
                    guard let _ = await iterator.next() else { break }
                    if Task.isCancelled { break }
                    refreshTouchSnapshot(resetRevision: false)
                }
            }
        }

        private func refreshTouchSnapshot(resetRevision: Bool) {
            let snapshot: ContentViewModel.TouchSnapshot
            if resetRevision {
                snapshot = viewModel.snapshotTouchData()
                lastTouchRevision = snapshot.revision
            } else if let updated = viewModel.snapshotTouchDataIfUpdated(since: lastTouchRevision) {
                snapshot = updated
                lastTouchRevision = updated.revision
            } else {
                return
            }

            let now = CACurrentMediaTime()
            if resetRevision || shouldUpdateDisplay(snapshot: snapshot, now: now) {
                displayLeftTouchesState = snapshot.left
                displayRightTouchesState = snapshot.right
                lastDisplayUpdateTime = now
                lastDisplayedHadTouches = !(snapshot.left.isEmpty && snapshot.right.isEmpty)
            }
        }

        private var displayLeftTouches: [OMSTouchData] {
            displayLeftTouchesState
        }

        private var displayRightTouches: [OMSTouchData] {
            displayRightTouchesState
        }

        private func customButtons(for side: TrackpadSide) -> [CustomButton] {
            customButtons.filter { $0.side == side && $0.layer == viewModel.activeLayer }
        }

        private func shouldUpdateDisplay(
            snapshot: ContentViewModel.TouchSnapshot,
            now: TimeInterval
        ) -> Bool {
            guard editModeEnabled else { return true }

            let hasTouches = !(snapshot.left.isEmpty && snapshot.right.isEmpty)
            if hasTouches != lastDisplayedHadTouches {
                return true
            }

            if snapshot.data.contains(where: { touch in
                switch touch.state {
                case .starting, .breaking, .leaving:
                    return true
                default:
                    return false
                }
            }) {
                return true
            }

            let clampedHz = 5.0
            let minInterval = 1.0 / clampedHz
            return now - lastDisplayUpdateTime >= minInterval
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
            lastHit: ContentViewModel.DebugHit?,
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
                            TrackpadButtonSelectionLayer(
                                button: selectedButton(for: customButtons),
                                trackpadSize: trackpadSize
                            )
                            .equatable()
                        if visualsEnabled {
                            TrackpadTouchLayer(
                                revision: lastTouchRevision,
                                touches: touches,
                                trackpadSize: trackpadSize
                            )
                        }
                        if !editModeEnabled, let lastHit = lastHit {
                            LastHitHighlightLayer(lastHit: lastHit)
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
            }
        }

        private func selectedButton(for buttons: [CustomButton]) -> CustomButton? {
            guard let selectedButtonID else { return nil }
            return buttons.first { $0.id == selectedButtonID }
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

    private struct TrackpadButtonSelectionLayer: View, Equatable {
        let button: CustomButton?
        let trackpadSize: CGSize

        var body: some View {
            Canvas { context, _ in
                guard let button else { return }
                let rect = button.rect.rect(in: trackpadSize)
                let path = Path(roundedRect: rect, cornerRadius: ContentView.keyCornerRadius)
                context.fill(path, with: .color(Color.accentColor.opacity(0.08)))
                context.stroke(path, with: .color(Color.accentColor.opacity(0.9)), lineWidth: 1.5)
            }
        }
    }

    private struct LastHitHighlightLayer: View {
        let lastHit: ContentViewModel.DebugHit

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                let age = CACurrentMediaTime() - lastHit.timestamp
                let fadeDuration: TimeInterval = 0.6
                let normalized = max(0, fadeDuration - age) / fadeDuration
                if normalized <= 0 {
                    EmptyView()
                } else {
                    Canvas { context, _ in
                        let cornerRadius = ContentView.keyCornerRadius
                        let highlightColor = Color.green.opacity(normalized * 0.95)
                        let strokePath = Path(roundedRect: lastHit.rect, cornerRadius: cornerRadius)
                        context.stroke(
                            strokePath,
                            with: .color(highlightColor),
                            lineWidth: 2.5
                        )
                    }
                }
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

    fileprivate static func normalizedColumnScale(_ value: Double) -> Double {
        min(max(value, Self.columnScaleRange.lowerBound), Self.columnScaleRange.upperBound)
    }

    fileprivate static func normalizedColumnOffsetPercent(_ value: Double) -> Double {
        min(
            max(value, Self.columnOffsetPercentRange.lowerBound),
            Self.columnOffsetPercentRange.upperBound
        )
    }

    fileprivate static func normalizedRowSpacingPercent(_ value: Double) -> Double {
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

    private func updateColumnSettingAndSelection(
        index: Int,
        update: (inout ColumnLayoutSettings) -> Void
    ) {
        updateColumnSetting(index: index, update: update)
        refreshColumnInspectorSelection()
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
        viewModel.updateTwoFingerSuppressionDuration(twoFingerSuppressionDurationMs / 1000.0)
        viewModel.updateDragCancelDistance(CGFloat(dragCancelDistanceSetting))
        viewModel.setTouchSnapshotRecordingEnabled(visualsEnabled)
    }

    private func saveSettings() {
        storedLeftDeviceID = viewModel.leftDevice?.deviceID ?? ""
        storedRightDeviceID = viewModel.rightDevice?.deviceID ?? ""
        storedVisualsEnabled = visualsEnabled
        storedLayoutPreset = layoutOption.rawValue
        saveCurrentColumnSettings()
    }

    private func persistConfig() {
        saveSettings()
        saveCustomButtons(customButtons)
        saveKeyMappings(keyMappingsByLayer)
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
        if let decoded = KeyActionMappingStore.decodeNormalized(storedKeyMappingsData) {
            keyMappingsByLayer = decoded
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
        if !editModeEnabled {
            editModeEnabled = true
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

    private func updateCustomButtonAndSelection(
        id: UUID,
        update: (inout CustomButton) -> Void
    ) {
        updateCustomButton(id: id, update: update)
        refreshButtonInspectorSelection()
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

    private func refreshColumnInspectorSelection() {
        guard let selectedColumn,
              columnSettings.indices.contains(selectedColumn) else {
            columnInspectorSelection = nil
            return
        }
        columnInspectorSelection = ColumnInspectorSelection(
            index: selectedColumn,
            settings: columnSettings[selectedColumn]
        )
    }

    private func refreshButtonInspectorSelection() {
        guard let selectedButtonID,
              let button = customButtons.first(where: { $0.id == selectedButtonID }) else {
            buttonInspectorSelection = nil
            return
        }
        buttonInspectorSelection = ButtonInspectorSelection(button: button)
    }

    private func refreshKeyInspectorSelection() {
        guard let selectedGridKey else {
            keyInspectorSelection = nil
            return
        }
        let mapping = effectiveKeyMapping(for: selectedGridKey)
        keyInspectorSelection = KeyInspectorSelection(
            key: selectedGridKey,
            mapping: mapping
        )
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

    fileprivate static func pickerLabel(for action: KeyAction) -> some View {
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

    private func updateKeyMappingAndSelection(
        key: SelectedGridKey,
        update: (inout KeyMapping) -> Void
    ) {
        updateKeyMapping(for: key, update)
        refreshKeyInspectorSelection()
    }

    private func defaultKeyMapping(for label: String) -> KeyMapping? {
        guard let primary = KeyActionCatalog.action(for: label) else { return nil }
        return KeyMapping(primary: primary, hold: KeyActionCatalog.holdAction(for: label))
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

    private func keyMappingsForActiveLayer() -> [String: KeyMapping] {
        keyMappingsByLayer[viewModel.activeLayer] ?? [:]
    }
}

#Preview {
    ContentView()
}
