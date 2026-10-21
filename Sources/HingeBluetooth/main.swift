import AppKit
import Darwin
import Foundation
import IOBluetooth
import IOKit
import IOKit.hid
import ServiceManagement

private enum L10n {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
    }
}

private enum HingePolicy {
    static let pollingInterval: DispatchTimeInterval = .milliseconds(120)
}

@MainActor
private final class ThresholdSliderView: NSView {
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let slider: NSSlider
    private let valuePrefix: String
    private var onChange: ((Double) -> Void)?

    init(title: String, valuePrefix: String, range: ClosedRange<Double>, value: Double, onChange: @escaping (Double) -> Void) {
        titleLabel = NSTextField(labelWithString: title)
        valueLabel = NSTextField(labelWithString: "")
        slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.valuePrefix = valuePrefix
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 62))

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 14, y: 38, width: 225, height: 17)
        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 244, y: 38, width: 82, height: 17)

        slider.frame = NSRect(x: 10, y: 5, width: 320, height: 25)
        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.setAccessibilityLabel(title)

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(slider)
        updateValueLabel(value)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded()
        sender.doubleValue = value
        updateValueLabel(value)
        onChange?(value)
    }

    private func updateValueLabel(_ value: Double) {
        valueLabel.stringValue = "\(valuePrefix) \(Int(value.rounded()))°"
    }
}

private final class LidAngleReader {
    var onAngle: ((Double) -> Void)?
    var onStatus: ((String) -> Void)?

    private let queue = DispatchQueue(label: "com.codex.hingebluetooth.sensor", qos: .userInitiated)
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var consecutiveReadFailures = 0
    private var reportedFailure: String?

    func start() {
        queue.async { [weak self] in
            self?.openSensor()
        }
    }

    private func openSensor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            kIOHIDPrimaryUsagePageKey as String: 0x0020,
            kIOHIDPrimaryUsageKey as String: 0x008A
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            reportFailure(L10n.text("sensor.openFailed"))
            return
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first,
              IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            reportFailure(L10n.text("sensor.notFound"))
            return
        }

        self.manager = manager
        self.device = device
        reportedFailure = nil
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(L10n.text("sensor.connected"))
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(80), repeating: HingePolicy.pollingInterval, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.readAngle()
        }
        self.timer = timer
        timer.resume()
    }

    private func readAngle() {
        guard let device else { return }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)

        guard result == kIOReturnSuccess, length >= 3 else {
            consecutiveReadFailures += 1
            if consecutiveReadFailures >= 5, reportedFailure != L10n.text("sensor.readFailed") {
                reportFailure(L10n.text("sensor.readFailed"))
            }
            return
        }

        consecutiveReadFailures = 0
        let rawAngle = UInt16(report[2]) << 8 | UInt16(report[1])
        guard rawAngle <= 180 else {
            reportFailure(L10n.text("sensor.invalidAngle"))
            return
        }

        if reportedFailure != nil {
            reportedFailure = nil
            DispatchQueue.main.async { [weak self] in
                self?.onStatus?(L10n.text("sensor.recovered"))
            }
        }
        let angle = Double(rawAngle)
        DispatchQueue.main.async { [weak self] in
            self?.onAngle?(angle)
        }
    }

    private func reportFailure(_ message: String) {
        guard reportedFailure != message else { return }
        reportedFailure = message
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(message)
        }
    }

    deinit {
        timer?.cancel()
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
}

private final class BluetoothPowerController {
    typealias Setter = @convention(c) (Int32) -> Void

    private let queue = DispatchQueue(label: "com.codex.hingebluetooth.bluetooth")
    private let frameworkHandle: UnsafeMutableRawPointer?
    private let setter: Setter?

    init() {
        let path = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
        frameworkHandle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        if let frameworkHandle,
           let symbol = dlsym(frameworkHandle, "IOBluetoothPreferenceSetControllerPowerState") {
            setter = unsafeBitCast(symbol, to: Setter.self)
        } else {
            setter = nil
        }
    }

    var isPowerControlAvailable: Bool { setter != nil }

    func currentPowerState() -> Bool? {
        guard let controller = IOBluetoothHostController.default() else { return nil }
        switch controller.powerState.rawValue {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    func setPowerState(enabled: Bool, completion: @escaping (Bool, String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let setter = self.setter else {
                completion(false, L10n.text("bluetooth.interfaceUnavailable"))
                return
            }

            if self.currentPowerState() == enabled {
                completion(true, nil)
                return
            }

            setter(enabled ? 1 : 0)

            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline {
                if self.currentPowerState() == enabled {
                    completion(true, nil)
                    return
                }
                usleep(100_000)
            }
            completion(false, L10n.text("bluetooth.unconfirmed"))
        }
    }

    deinit {
        if let frameworkHandle {
            dlclose(frameworkHandle)
        }
    }
}

private final class BackgroundAgent {
    private let sensor = LidAngleReader()
    private let bluetooth = BluetoothPowerController()
    private let defaults = UserDefaults(suiteName: "com.codex.hingebluetooth") ?? .standard
    private var pendingTarget: Bool?
    private var requestGeneration = 0
    private var lastForegroundCheck = Date.distantPast
    private var cachedForegroundAppIsRunning = false

    func start() {
        sensor.onAngle = { [weak self] angle in
            self?.handleAngle(angle)
        }
        sensor.onStatus = { message in
            NSLog("Auto Turn Off Bluetooth background agent: %@", message)
        }
        sensor.start()
    }

    private func handleAngle(_ angle: Double) {
        guard defaults.object(forKey: "backgroundResidentEnabled") as? Bool ?? false,
              !isMainAppRunning() else {
            return
        }

        let closeThreshold = threshold(key: "closeThreshold", fallback: 10, range: 0...60)
        let openThreshold = threshold(key: "openThreshold", fallback: 130, range: 70...130)

        if angle <= closeThreshold {
            reconcileBluetooth(enabled: false)
        } else if angle > openThreshold {
            reconcileBluetooth(enabled: true)
        }
    }

    private func threshold(key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        guard let stored = defaults.object(forKey: key) as? NSNumber else { return fallback }
        return min(range.upperBound, max(range.lowerBound, stored.doubleValue.rounded()))
    }

    private func isMainAppRunning() -> Bool {
        if Date().timeIntervalSince(lastForegroundCheck) < 1 {
            return cachedForegroundAppIsRunning
        }
        lastForegroundCheck = Date()
        cachedForegroundAppIsRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.codex.hingebluetooth")
            .contains { $0.processIdentifier != getpid() }
        return cachedForegroundAppIsRunning
    }

    private func reconcileBluetooth(enabled: Bool) {
        guard pendingTarget != enabled else { return }
        if bluetooth.currentPowerState() == enabled {
            pendingTarget = nil
            return
        }
        guard bluetooth.isPowerControlAvailable else { return }

        requestGeneration += 1
        let thisRequest = requestGeneration
        pendingTarget = enabled
        bluetooth.setPowerState(enabled: enabled) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self, self.requestGeneration == thisRequest else { return }
                self.pendingTarget = nil
                if !success {
                    NSLog("Auto Turn Off Bluetooth background agent: %@", error ?? "Bluetooth control failed")
                }
            }
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let sensor = LidAngleReader()
    private let bluetooth = BluetoothPowerController()
    private var statusItem: NSStatusItem!
    private var currentAngle: Double?
    private var sensorStatus = L10n.text("sensor.searching")
    private var closeThreshold: Double
    private var openThreshold: Double
    private var backgroundResidentEnabled: Bool
    private var pendingTarget: Bool?
    private var requestGeneration = 0
    private var lastControlError: String?
    private weak var policyMenuItem: NSMenuItem?

    private static let backgroundAgentPlistName = "com.codex.hingebluetooth.agent.plist"

    override init() {
        closeThreshold = Self.savedThreshold(key: "closeThreshold", fallback: 10, range: 0...60)
        openThreshold = Self.savedThreshold(key: "openThreshold", fallback: 130, range: 70...130)
        backgroundResidentEnabled = UserDefaults.standard.object(forKey: "backgroundResidentEnabled") as? Bool ?? true
        super.init()
    }

    private static func savedThreshold(key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        guard let saved = UserDefaults.standard.object(forKey: key) as? NSNumber else { return fallback }
        return min(range.upperBound, max(range.lowerBound, saved.doubleValue.rounded()))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenuBar()
        configureBackgroundAgentOnLaunch()

        sensor.onAngle = { [weak self] angle in
            DispatchQueue.main.async {
                self?.handleAngle(angle)
            }
        }
        sensor.onStatus = { [weak self] message in
            DispatchQueue.main.async {
                self?.sensorStatus = message
                if message.contains(L10n.text("sensor.notFoundMarker")) || message.contains(L10n.text("sensor.readFailedMarker")) || message.contains(L10n.text("sensor.invalidAngleMarker")) {
                    self?.currentAngle = nil
                }
                self?.refreshMenuBar()
            }
        }

        sensor.start()
        refreshMenuBar()
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = nil
            button.title = "—°"
            button.toolTip = "Auto Turn Off Bluetooth"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        synchronizeBackgroundAgentState()
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        policyMenuItem = nil

        let closeItem = NSMenuItem()
        closeItem.view = ThresholdSliderView(
            title: L10n.text("menu.closeAngle"),
            valuePrefix: "≤",
            range: 0.0...60.0,
            value: closeThreshold
        ) { [weak self] value in
            self?.setCloseThreshold(value)
        }
        menu.addItem(closeItem)

        let openItem = NSMenuItem()
        openItem.view = ThresholdSliderView(
            title: L10n.text("menu.openAngle"),
            valuePrefix: ">",
            range: 70.0...130.0,
            value: openThreshold
        ) { [weak self] value in
            self?.setOpenThreshold(value)
        }
        menu.addItem(openItem)

        let policyItem = NSMenuItem(title: policyDescription, action: nil, keyEquivalent: "")
        policyItem.isEnabled = false
        policyMenuItem = policyItem
        menu.addItem(policyItem)

        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: L10n.text("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        if SMAppService.mainApp.status == .requiresApproval {
            addDisabledItem(L10n.text("login.approve"))
        } else if SMAppService.mainApp.status == .notFound {
            addDisabledItem(L10n.text("login.installFirst"))
        }

        let residentItem = NSMenuItem(
            title: backgroundResidentEnabled ? L10n.text("background.on") : L10n.text("background.off"),
            action: #selector(toggleBackgroundResidence),
            keyEquivalent: ""
        )
        residentItem.target = self
        residentItem.state = backgroundResidentEnabled ? .on : .off
        menu.addItem(residentItem)
        let backgroundAgent = SMAppService.agent(plistName: Self.backgroundAgentPlistName)
        if !backgroundAgentBundleFilesArePresent {
            addDisabledItem(L10n.text("background.missingFiles"))
        }
        switch backgroundAgent.status {
        case .requiresApproval:
            addDisabledItem(L10n.text("background.approve"))
        case .notFound:
            if backgroundAgentBundleFilesArePresent {
                addDisabledItem(L10n.text("background.unrecognized"))
            }
        default:
            break
        }
        if let lastControlError {
            addDisabledItem(lastControlError)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L10n.text("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        addDisabledItem("Auto Turn Off Bluetooth \(L10n.version)")

        let copyrightItem = NSMenuItem(title: "© 2026 catquickly", action: nil, keyEquivalent: "")
        copyrightItem.isEnabled = false
        menu.addItem(copyrightItem)

    }

    private var isLaunchAtLoginEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    private var policyDescription: String {
        String(format: L10n.text("policy.description"), Int(closeThreshold), Int(openThreshold))
    }

    private func addDisabledItem(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        statusItem.menu?.addItem(item)
    }

    private func setCloseThreshold(_ value: Double) {
        closeThreshold = min(60, max(0, value.rounded()))
        UserDefaults.standard.set(closeThreshold, forKey: "closeThreshold")
        policyMenuItem?.title = policyDescription
        if let currentAngle { handleAngle(currentAngle) }
    }

    private func setOpenThreshold(_ value: Double) {
        openThreshold = min(130, max(70, value.rounded()))
        UserDefaults.standard.set(openThreshold, forKey: "openThreshold")
        policyMenuItem?.title = policyDescription
        if let currentAngle { handleAngle(currentAngle) }
    }

    private func handleAngle(_ angle: Double) {
        currentAngle = angle
        if angle <= closeThreshold {
            reconcileBluetooth(enabled: false)
        } else if angle > openThreshold {
            reconcileBluetooth(enabled: true)
        }
        refreshMenuBar()
    }

    private func reconcileBluetooth(enabled: Bool) {
        if pendingTarget == enabled { return }
        if bluetooth.currentPowerState() == enabled {
            pendingTarget = nil
            lastControlError = nil
            return
        }
        if !bluetooth.isPowerControlAvailable {
            let message = L10n.text("bluetooth.noInterface")
            if lastControlError != message {
                lastControlError = message
                refreshMenuBar()
            }
            return
        }

        requestGeneration += 1
        let thisRequest = requestGeneration
        pendingTarget = enabled
        lastControlError = enabled ? L10n.text("bluetooth.turningOn") : L10n.text("bluetooth.turningOff")
        refreshMenuBar()

        bluetooth.setPowerState(enabled: enabled) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self, self.requestGeneration == thisRequest else { return }
                self.pendingTarget = nil
                self.lastControlError = success ? nil : (error ?? L10n.text("bluetooth.failed"))
                self.refreshMenuBar()
            }
        }
    }

    private func refreshMenuBar() {
        let angleText = currentAngle.map { "\(Int($0.rounded()))°" } ?? "—°"
        statusItem?.button?.title = angleText
    }

    private func applyBackgroundResidence() {
        let service = SMAppService.agent(plistName: Self.backgroundAgentPlistName)
        let defaults = UserDefaults.standard
        if backgroundResidentEnabled {
            switch service.status {
            case .enabled:
                defaults.set(true, forKey: "backgroundAgentConfigured")
                lastControlError = nil
                return
            case .requiresApproval:
                defaults.set(true, forKey: "backgroundAgentConfigured")
                lastControlError = L10n.text("background.waitingApproval")
                return
            case .notFound:
                guard backgroundAgentBundleFilesArePresent else {
                    lastControlError = L10n.text("background.missingFiles")
                    return
                }
            default:
                break
            }

            do {
                try service.register()
                switch service.status {
                case .enabled:
                    defaults.set(true, forKey: "backgroundAgentConfigured")
                    lastControlError = nil
                case .requiresApproval:
                    defaults.set(true, forKey: "backgroundAgentConfigured")
                    lastControlError = L10n.text("background.waitingApproval")
                case .notFound:
                    lastControlError = L10n.text("background.notFound")
                default:
                    lastControlError = L10n.text("background.notEnabled")
                }
            } catch {
                lastControlError = String(format: L10n.text("background.registerFailed"), error.localizedDescription)
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            do {
                try service.unregister()
                defaults.set(true, forKey: "backgroundAgentConfigured")
                lastControlError = nil
            } catch {
                lastControlError = String(format: L10n.text("background.unregisterFailed"), error.localizedDescription)
            }
        } else {
            defaults.set(true, forKey: "backgroundAgentConfigured")
            lastControlError = nil
        }
    }

    private func configureBackgroundAgentOnLaunch() {
        let defaults = UserDefaults.standard
        let service = SMAppService.agent(plistName: Self.backgroundAgentPlistName)
        if !defaults.bool(forKey: "backgroundAgentConfigured") ||
            (backgroundResidentEnabled && service.status == .notFound) {
            applyBackgroundResidence()
        } else {
            synchronizeBackgroundAgentState()
        }
    }

    private var backgroundAgentBundleFilesArePresent: Bool {
        let contentsURL = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let plistURL = contentsURL
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(Self.backgroundAgentPlistName)
        let helperURL = contentsURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("HingeBluetoothAgent")
        return FileManager.default.isReadableFile(atPath: plistURL.path)
            && FileManager.default.isExecutableFile(atPath: helperURL.path)
    }

    private func synchronizeBackgroundAgentState() {
        let service = SMAppService.agent(plistName: Self.backgroundAgentPlistName)
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "backgroundAgentConfigured") else { return }

        switch service.status {
        case .enabled:
            backgroundResidentEnabled = true
            defaults.set(true, forKey: "backgroundResidentEnabled")
            lastControlError = nil
        case .requiresApproval:
            backgroundResidentEnabled = true
            defaults.set(true, forKey: "backgroundResidentEnabled")
            lastControlError = L10n.text("background.waitingApproval")
        case .notRegistered:
            backgroundResidentEnabled = false
            defaults.set(false, forKey: "backgroundResidentEnabled")
            lastControlError = nil
        case .notFound:
            if backgroundResidentEnabled && backgroundAgentBundleFilesArePresent {
                lastControlError = L10n.text("background.retrying")
            }
        @unknown default:
            break
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            lastControlError = nil
        } catch {
            lastControlError = String(format: L10n.text("login.failed"), error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func toggleBackgroundResidence() {
        backgroundResidentEnabled.toggle()
        UserDefaults.standard.set(backgroundResidentEnabled, forKey: "backgroundResidentEnabled")
        applyBackgroundResidence()
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

#if HINGEBLUETOOTH_BACKGROUND_AGENT
@main
private enum HingeBluetoothMain {
    static func main() {
        let agent = BackgroundAgent()
        agent.start()
        withExtendedLifetime(agent) {
            dispatchMain()
        }
    }
}
#else
@main
private enum HingeBluetoothMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
#endif
