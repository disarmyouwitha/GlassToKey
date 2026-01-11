//
//  ContentView.swift
//  OMSDemo
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import Combine
import OpenMultitouchSupport
import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = ContentViewModel()
    @State private var testText = ""
    @State private var displayTouchData = [OMSTouchData]()
    @State private var visualsEnabled = true
    private static let trackpadWidthMM: CGFloat = 160.0
    private static let trackpadHeightMM: CGFloat = 114.9
    private static let displayScale: CGFloat = 2.7
    private let displayRefreshInterval: TimeInterval = 1.0 / 60.0
    // Per-column anchor positions in trackpad mm (top key origin).
    private static let ColumnAnchorsMM: [CGPoint] = [
        CGPoint(x: 35.0, y: 20.9),
        CGPoint(x: 53.0, y: 19.2),
        CGPoint(x: 71.0, y: 17.5),
        CGPoint(x: 89.0, y: 19.2),
        CGPoint(x: 107.0, y: 22.6),
        CGPoint(x: 125.0, y: 22.6)
    ]

    private static let ThumbAnchorsMM: [CGRect] = [
        CGRect(x: 0, y: 75, width: 40, height: 40),
        CGRect(x: 40, y: 85, width: 40, height: 30),
        CGRect(x: 80, y: 85, width: 40, height: 30),
        CGRect(x: 120, y: 85, width: 40, height: 30)
    ]
    private static let typingToggleRectMM = CGRect(x: 130, y: 0, width: 30, height: 75)

    private let trackpadSize: CGSize
    private let leftLayout: ContentViewModel.Layout
    private let rightLayout: ContentViewModel.Layout

    init() {
        let size = CGSize(
            width: Self.trackpadWidthMM * Self.displayScale,
            height: Self.trackpadHeightMM * Self.displayScale
        )
        trackpadSize = size
        leftLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: 18,
            keyHeight: 17,
            columns: 6,
            rows: 3,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            thumbAnchorsMM: Self.ThumbAnchorsMM,
            mirrored: true
        )
        rightLayout = ContentView.makeKeyLayout(
            size: size,
            keyWidth: 18,
            keyHeight: 17,
            columns: 6,
            rows: 3,
            trackpadWidth: Self.trackpadWidthMM,
            trackpadHeight: Self.trackpadHeightMM,
            columnAnchorsMM: Self.ColumnAnchorsMM,
            thumbAnchorsMM: Self.ThumbAnchorsMM
        )
    }

    var body: some View {
        VStack {
            // Device Selectors
            if !viewModel.availableDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trackpad Devices")
                        .font(.headline)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading) {
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
                        }

                        VStack(alignment: .leading) {
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
                }
                .padding(.bottom)
            }
            
            HStack(spacing: 20) {
                if viewModel.isListening {
                    Button {
                        viewModel.stop()
                    } label: {
                        Text("Stop")
                    }
                } else {
                    Button {
                        viewModel.start()
                    } label: {
                        Text("Start")
                    }
                }
                Toggle("Visuals", isOn: $visualsEnabled)
                    .toggleStyle(SwitchToggleStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Typing Test")
                    .font(.subheadline)
                TextEditor(text: $testText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.6), lineWidth: 1)
                    )
            }
            .padding(.vertical, 8)
            
            HStack(alignment: .top, spacing: 16) {
                trackpadCanvas(
                    title: "Left Trackpad",
                    touches: visualsEnabled ? displayLeftTouches : [],
                    mirrored: true,
                    labels: mirroredLabels(ContentViewModel.leftGridLabels),
                    activeThumbCount: viewModel.leftThumbKeyCount,
                    visualsEnabled: visualsEnabled,
                    typingToggleRect: typingToggleRect(isLeft: true),
                    typingEnabled: viewModel.isTypingEnabled
                )
                trackpadCanvas(
                    title: "Right Trackpad",
                    touches: visualsEnabled ? displayRightTouches : [],
                    mirrored: false,
                    labels: ContentViewModel.rightGridLabels,
                    activeThumbCount: viewModel.rightThumbKeyCount,
                    visualsEnabled: visualsEnabled,
                    typingToggleRect: typingToggleRect(isLeft: false),
                    typingEnabled: viewModel.isTypingEnabled
                )
            }
        }
        .padding()
        .frame(minWidth: trackpadSize.width * 2 + 120, minHeight: trackpadSize.height + 180)
        .onAppear {
            viewModel.configureLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: mirroredLabels(ContentViewModel.leftGridLabels),
                rightLabels: ContentViewModel.rightGridLabels,
                leftTypingToggleRect: typingToggleRect(isLeft: true),
                rightTypingToggleRect: typingToggleRect(isLeft: false),
                trackpadSize: trackpadSize
            )
            viewModel.onAppear()
            displayTouchData = viewModel.snapshotTouchData()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: visualsEnabled) { enabled in
            displayTouchData = enabled ? viewModel.snapshotTouchData() : []
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
        activeThumbCount: Int,
        visualsEnabled: Bool,
        typingToggleRect: CGRect?,
        typingEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            Group {
                if visualsEnabled {
                    Canvas { context, _ in
                        let layout = mirrored ? leftLayout : rightLayout
                        drawSensorGrid(context: &context, size: trackpadSize, columns: 30, rows: 22)
                        drawKeyGrid(context: &context, keyRects: layout.keyRects)
                        drawThumbGrid(
                            context: &context,
                            thumbRects: layout.thumbRects,
                            activeThumbCount: activeThumbCount
                        )
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

    private static func makeKeyLayout(
        size: CGSize,
        keyWidth: CGFloat,
        keyHeight: CGFloat,
        columns: Int,
        rows: Int,
        trackpadWidth: CGFloat,
        trackpadHeight: CGFloat,
        columnAnchorsMM: [CGPoint],
        thumbAnchorsMM: [CGRect],
        mirrored: Bool = false
    ) -> ContentViewModel.Layout {
        let scaleX = size.width / trackpadWidth
        let scaleY = size.height / trackpadHeight
        let keySize = CGSize(width: keyWidth * scaleX, height: keyHeight * scaleY)

        var keyRects: [[CGRect]] = Array(
            repeating: Array(repeating: .zero, count: columns),
            count: rows
        )
        for row in 0..<rows {
            for col in 0..<columns {
                let anchorMM = columnAnchorsMM[col]
                keyRects[row][col] = CGRect(
                    x: anchorMM.x * scaleX,
                    y: anchorMM.y * scaleY + CGFloat(row) * keySize.height,
                    width: keySize.width,
                    height: keySize.height
                )
            }
        }

        let thumbRects = thumbAnchorsMM.map { rectMM in
            CGRect(
                x: rectMM.origin.x * scaleX,
                y: rectMM.origin.y * scaleY,
                width: rectMM.width * scaleX,
                height: rectMM.height * scaleY
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
            let mirroredThumbRects = thumbRects.map { rect in
                CGRect(
                    x: size.width - rect.maxX,
                    y: rect.minY,
                    width: rect.width,
                    height: rect.height
                )
            }
            return ContentViewModel.Layout(
                keyRects: mirroredKeyRects,
                thumbRects: mirroredThumbRects
            )
        }

        return ContentViewModel.Layout(keyRects: keyRects, thumbRects: thumbRects)
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

    private func drawThumbGrid(
        context: inout GraphicsContext,
        thumbRects: [CGRect],
        activeThumbCount: Int
    ) {
        for (index, rect) in thumbRects.enumerated() {
            if index < activeThumbCount {
                context.fill(Path(rect), with: .color(Color.blue.opacity(0.15)))
            }
            context.stroke(Path(rect), with: .color(.secondary.opacity(0.6)), lineWidth: 1)
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

    private func mirroredLabels(_ labels: [[String]]) -> [[String]] {
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
