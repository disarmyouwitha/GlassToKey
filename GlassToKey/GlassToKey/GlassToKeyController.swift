import OpenMultitouchSupport
import SwiftUI

@MainActor
final class GlassToKeyController: ObservableObject {
    let viewModel: ContentViewModel
    private var isRunning = false

    init(viewModel: ContentViewModel = ContentViewModel()) {
        self.viewModel = viewModel
    }

    func start() {
        guard !isRunning else { return }
        configureFromDefaults()
        viewModel.start()
        viewModel.onAppear()
        isRunning = true
    }

    private func configureFromDefaults() {
        viewModel.loadDevices()

        let keyScale = doubleValue(
            forKey: GlassToKeyDefaultsKeys.keyScale,
            defaultValue: 1.0
        )
        let thumbScale = doubleValue(
            forKey: GlassToKeyDefaultsKeys.thumbScale,
            defaultValue: 1.0
        )
        let pinkyScale = doubleValue(
            forKey: GlassToKeyDefaultsKeys.pinkyScale,
            defaultValue: 1.2
        )
        let keyOffsetX = doubleValue(
            forKey: GlassToKeyDefaultsKeys.keyOffsetX,
            defaultValue: 0.0
        )
        let keyOffsetY = doubleValue(
            forKey: GlassToKeyDefaultsKeys.keyOffsetY,
            defaultValue: 0.0
        )

        let trackpadSize = CGSize(
            width: ContentView.trackpadWidthMM * ContentView.displayScale,
            height: ContentView.trackpadHeightMM * ContentView.displayScale
        )

        let leftLabels = ContentView.mirroredLabels(ContentViewModel.leftGridLabels)
        let rightLabels = ContentViewModel.rightGridLabels

        let leftLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: ContentView.baseKeyWidthMM,
            keyHeight: ContentView.baseKeyHeightMM,
            keyScale: keyScale,
            thumbScale: thumbScale,
            labels: leftLabels,
            widthScaleByLabel: ContentView.outerKeyWidthByLabel(pinkyScale: pinkyScale),
            columns: 6,
            rows: 3,
            trackpadWidth: ContentView.trackpadWidthMM,
            trackpadHeight: ContentView.trackpadHeightMM,
            columnAnchorsMM: ContentView.ColumnAnchorsMM,
            thumbAnchorsMM: ContentView.ThumbAnchorsMM,
            keyOffsetMM: CGPoint(x: keyOffsetX, y: keyOffsetY),
            mirrored: true
        )
        let rightLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: ContentView.baseKeyWidthMM,
            keyHeight: ContentView.baseKeyHeightMM,
            keyScale: keyScale,
            thumbScale: thumbScale,
            labels: rightLabels,
            widthScaleByLabel: ContentView.outerKeyWidthByLabel(pinkyScale: pinkyScale),
            columns: 6,
            rows: 3,
            trackpadWidth: ContentView.trackpadWidthMM,
            trackpadHeight: ContentView.trackpadHeightMM,
            columnAnchorsMM: ContentView.ColumnAnchorsMM,
            thumbAnchorsMM: ContentView.ThumbAnchorsMM,
            keyOffsetMM: CGPoint(x: -keyOffsetX, y: keyOffsetY)
        )

        viewModel.configureLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: leftLabels,
            rightLabels: rightLabels,
            leftTypingToggleRect: typingToggleRect(isLeft: true, trackpadSize: trackpadSize),
            rightTypingToggleRect: typingToggleRect(isLeft: false, trackpadSize: trackpadSize),
            trackpadSize: trackpadSize
        )

        let leftDeviceID = stringValue(forKey: GlassToKeyDefaultsKeys.leftDeviceID)
        let rightDeviceID = stringValue(forKey: GlassToKeyDefaultsKeys.rightDeviceID)
        if let leftDevice = deviceForID(leftDeviceID) {
            viewModel.selectLeftDevice(leftDevice)
        }
        if let rightDevice = deviceForID(rightDeviceID) {
            viewModel.selectRightDevice(rightDevice)
        }
    }

    private func typingToggleRect(isLeft: Bool, trackpadSize: CGSize) -> CGRect {
        let scaleX = trackpadSize.width / ContentView.trackpadWidthMM
        let scaleY = trackpadSize.height / ContentView.trackpadHeightMM
        let originXMM = isLeft
            ? ContentView.typingToggleRectMM.origin.x
            : ContentView.trackpadWidthMM - ContentView.typingToggleRectMM.maxX
        return CGRect(
            x: originXMM * scaleX,
            y: ContentView.typingToggleRectMM.origin.y * scaleY,
            width: ContentView.typingToggleRectMM.width * scaleX,
            height: ContentView.typingToggleRectMM.height * scaleY
        )
    }

    private func deviceForID(_ deviceID: String) -> OMSDeviceInfo? {
        guard !deviceID.isEmpty else { return nil }
        return viewModel.availableDevices.first { $0.deviceID == deviceID }
    }

    private func doubleValue(forKey key: String, defaultValue: Double) -> Double {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.double(forKey: key)
    }

    private func stringValue(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }
}
