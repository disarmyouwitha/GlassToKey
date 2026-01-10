//
//  ContentView.swift
//  OMSDemo
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import OpenMultitouchSupport
import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = ContentViewModel()
    @State private var testText = ""
    private let trackpadWidthMM: CGFloat = 160.0
    private let trackpadHeightMM: CGFloat = 114.9
    private let displayScale: CGFloat = 2.7
    // Per-column anchor positions in trackpad mm (top key origin).
    private let ColumnAnchorsMM: [CGPoint] = [
        CGPoint(x: 35.0, y: 20.9),
        CGPoint(x: 53.0, y: 19.2),
        CGPoint(x: 71.0, y: 17.5),
        CGPoint(x: 89.0, y: 19.2),
        CGPoint(x: 107.0, y: 22.6),
        CGPoint(x: 125.0, y: 22.6)
    ]

    private let ThumbAnchorsMM: [CGRect] = [
        CGRect(x: 17.0, y: 71.9, width: 18.0, height: 25.5)
    ]

    private var trackpadSize: CGSize {
        CGSize(width: trackpadWidthMM * displayScale, height: trackpadHeightMM * displayScale)
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
                    touches: viewModel.leftTouches,
                    mirrored: true,
                    labels: mirroredLabels(ContentViewModel.leftGridLabels),
                    typingToggleRect: typingToggleRect(isLeft: true),
                    typingEnabled: viewModel.isTypingEnabled
                )
                trackpadCanvas(
                    title: "Right Trackpad",
                    touches: viewModel.rightTouches,
                    mirrored: false,
                    labels: ContentViewModel.rightGridLabels,
                    typingToggleRect: typingToggleRect(isLeft: false),
                    typingEnabled: viewModel.isTypingEnabled
                )
            }
        }
        .padding()
        .frame(minWidth: trackpadSize.width * 2 + 120, minHeight: trackpadSize.height + 180)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onReceive(viewModel.$touchData) { _ in
            let leftLayout = makeKeyLayout(
                size: trackpadSize,
                keyWidth: 18,
                keyHeight: 17,
                columns: 6,
                rows: 3,
                trackpadWidth: trackpadWidthMM,
                trackpadHeight: trackpadHeightMM,
                columnAnchorsMM: ColumnAnchorsMM,
                thumbAnchorsMM: ThumbAnchorsMM,
                mirrored: true
            )
            let rightLayout = makeKeyLayout(
                size: trackpadSize,
                keyWidth: 18,
                keyHeight: 17,
                columns: 6,
                rows: 3,
                trackpadWidth: trackpadWidthMM,
                trackpadHeight: trackpadHeightMM,
                columnAnchorsMM: ColumnAnchorsMM,
                thumbAnchorsMM: ThumbAnchorsMM
            )
            viewModel.processTouches(
                viewModel.leftTouches,
                keyRects: leftLayout.keyRects,
                thumbRects: leftLayout.thumbRects,
                canvasSize: trackpadSize,
                labels: mirroredLabels(ContentViewModel.leftGridLabels),
                isLeftSide: true,
                typingToggleRect: typingToggleRect(isLeft: true)
            )
            viewModel.processTouches(
                viewModel.rightTouches,
                keyRects: rightLayout.keyRects,
                thumbRects: rightLayout.thumbRects,
                canvasSize: trackpadSize,
                labels: ContentViewModel.rightGridLabels,
                isLeftSide: false,
                typingToggleRect: typingToggleRect(isLeft: false)
            )
        }
    }

    private func trackpadCanvas(
        title: String,
        touches: [OMSTouchData],
        mirrored: Bool,
        labels: [[String]],
        typingToggleRect: CGRect?,
        typingEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            Canvas { context, _ in
                let layout = makeKeyLayout(
                    size: trackpadSize,
                    keyWidth: 18,
                    keyHeight: 17,
                    columns: 6,
                    rows: 3,
                    trackpadWidth: trackpadWidthMM,
                    trackpadHeight: trackpadHeightMM,
                    columnAnchorsMM: ColumnAnchorsMM,
                    thumbAnchorsMM: ThumbAnchorsMM,
                    mirrored: mirrored
                )
                drawSensorGrid(context: &context, size: trackpadSize, columns: 30, rows: 22)
                drawKeyGrid(context: &context, keyRects: layout.keyRects)
                drawThumbGrid(context: &context, thumbRects: layout.thumbRects)
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

    private func makeKeyLayout(
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
    ) -> (keyRects: [[CGRect]], thumbRects: [CGRect]) {
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
            return (mirroredKeyRects, mirroredThumbRects)
        }

        return (keyRects, thumbRects)
    }

    private var typingToggleSize: CGSize {
        CGSize(width: trackpadSize.width * 0.27, height: trackpadSize.height * 0.27)
    }

    private func typingToggleRect(isLeft: Bool) -> CGRect {
        let size = typingToggleSize
        let originX = isLeft ? 0 : trackpadSize.width - size.width
        let originY = trackpadSize.height - size.height
        return CGRect(x: originX, y: originY, width: size.width, height: size.height)
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

    private func drawThumbGrid(context: inout GraphicsContext, thumbRects: [CGRect]) {
        for rect in thumbRects {
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
}

#Preview {
    ContentView()
}
