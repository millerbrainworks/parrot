import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private static let systemDefaultIdentifier = "__parrot_system_default__"

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let stateLabel: NSMenuItem
    private let modelLabel: NSMenuItem
    private let microphoneItem: NSMenuItem
    private let microphoneMenu = NSMenu()
    private let historyItem: NSMenuItem
    private let launchAtLoginItem: NSMenuItem
    private let permissionsItem: NSMenuItem
    private let modelID: String
    private let deviceCatalog: AudioDeviceCatalog
    private let preferencesStore: PreferencesStore
    private let historyWriter: HistoryWriter
    private let logger: DiagnosticLogger
    private var model: MenuBarModel

    init(
        modelID: String,
        deviceCatalog: AudioDeviceCatalog = AudioDeviceCatalog(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        historyWriter: HistoryWriter = HistoryWriter(),
        logger: DiagnosticLogger = DiagnosticLogger()
    ) {
        self.modelID = modelID
        self.deviceCatalog = deviceCatalog
        self.preferencesStore = preferencesStore
        self.historyWriter = historyWriter
        self.logger = logger
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let initialDevice = Self.resolveDevice(
            catalog: deviceCatalog,
            preferencesStore: preferencesStore
        )
        self.model = MenuBarModel(
            state: .idle,
            microphoneName: initialDevice.displayName,
            microphoneFallback: initialDevice.isFallback
        )
        self.stateLabel = NSMenuItem(title: model.stateTitle, action: nil, keyEquivalent: "")
        self.modelLabel = NSMenuItem(title: "Model: \(modelID)", action: nil, keyEquivalent: "")
        self.microphoneItem = NSMenuItem(
            title: "Microphone: \(model.microphoneTitle)",
            action: nil,
            keyEquivalent: ""
        )
        self.historyItem = NSMenuItem(
            title: "Open Today’s History",
            action: #selector(openHistoryClicked),
            keyEquivalent: ""
        )
        self.launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: nil,
            keyEquivalent: ""
        )
        self.permissionsItem = NSMenuItem(
            title: "Review Permissions…",
            action: #selector(permissionsClicked),
            keyEquivalent: ""
        )

        super.init()

        menu.autoenablesItems = false
        menu.delegate = self

        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        modelLabel.isEnabled = false
        menu.addItem(modelLabel)

        microphoneItem.submenu = microphoneMenu
        menu.addItem(microphoneItem)
        menu.addItem(.separator())

        historyItem.target = self
        menu.addItem(historyItem)

        launchAtLoginItem.isEnabled = false
        menu.addItem(launchAtLoginItem)

        permissionsItem.target = self
        menu.addItem(permissionsItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Parrot",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        configureButton()
        refresh()
    }

    func setRecording(_ recording: Bool) {
        setState(recording ? .recording : .idle)
    }

    func setTranscribing() {
        setState(.transcribing)
    }

    func setState(_ state: DictationState) {
        model.state = state
        stateLabel.title = model.stateTitle
        microphoneItem.isEnabled = model.canChangeMicrophone
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        let resolved = Self.resolveDevice(
            catalog: deviceCatalog,
            preferencesStore: preferencesStore
        )
        model.microphoneName = resolved.displayName
        model.microphoneFallback = resolved.isFallback
        microphoneItem.title = "Microphone: \(model.microphoneTitle)"
        microphoneItem.isEnabled = model.canChangeMicrophone
        rebuildMicrophoneMenu()

        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.digimata.parrot.plist")
        let launchEnabled = FileManager.default.fileExists(atPath: plist.path)
        launchAtLoginItem.title = "Launch at Login: \(launchEnabled ? "On" : "Off")"

        permissionsItem.isHidden = DoctorReport.allClean(DoctorReport.run())
    }

    private func rebuildMicrophoneMenu() {
        microphoneMenu.removeAllItems()
        let preferences = (try? preferencesStore.load()) ?? ParrotPreferences()

        let systemDefault = NSMenuItem(
            title: "System Default",
            action: #selector(microphoneClicked),
            keyEquivalent: ""
        )
        systemDefault.target = self
        systemDefault.representedObject = Self.systemDefaultIdentifier
        systemDefault.state = preferences.microphoneUID == nil ? .on : .off
        systemDefault.isEnabled = model.canChangeMicrophone
        microphoneMenu.addItem(systemDefault)

        let devices = deviceCatalog.inputDevices()
        if !devices.isEmpty {
            microphoneMenu.addItem(.separator())
        }
        for device in devices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(microphoneClicked),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.uid
            item.state = preferences.microphoneUID == device.uid ? .on : .off
            item.isEnabled = model.canChangeMicrophone
            microphoneMenu.addItem(item)
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = Self.birdImage()
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Parrot Dictation"
    }

    @objc private func microphoneClicked(_ sender: NSMenuItem) {
        guard model.canChangeMicrophone, let identifier = sender.representedObject as? String else {
            return
        }
        let uid = identifier == Self.systemDefaultIdentifier ? nil : identifier
        do {
            try preferencesStore.save(ParrotPreferences(microphoneUID: uid))
        } catch {
            logger.message("preferences save failed: \(error)")
        }
        refresh()
    }

    @objc private func openHistoryClicked() {
        let today = historyWriter.fileURL()
        if FileManager.default.fileExists(atPath: today.path) {
            NSWorkspace.shared.open(today)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: historyWriter.rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: historyWriter.rootDirectory.path
            )
            NSWorkspace.shared.open(historyWriter.rootDirectory)
        } catch {
            logger.message("history open failed: \(error)")
        }
    }

    @objc private func permissionsClicked() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    private static func resolveDevice(
        catalog: AudioDeviceCatalog,
        preferencesStore: PreferencesStore
    ) -> ResolvedAudioDevice {
        let preferences = (try? preferencesStore.load()) ?? ParrotPreferences()
        return catalog.resolve(savedUID: preferences.microphoneUID)
    }

    private static let birdSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" \
    viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" \
    stroke-linecap="round" stroke-linejoin="round">\
    <path d="M16 7h.01"/>\
    <path d="M3.4 18H12a8 8 0 0 0 8-8V7a4 4 0 0 0-7.28-2.3L2 20"/>\
    <path d="m20 7 2 .5-2 .5"/>\
    <path d="M10 18v3"/>\
    <path d="M14 17.75V21"/>\
    <path d="M7 18a6 6 0 0 0 3.84-10.61"/>\
    </svg>
    """

    private static func birdImage() -> NSImage? {
        guard
            let data = birdSVG.data(using: .utf8),
            let image = NSImage(data: data)
        else {
            return nil
        }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
