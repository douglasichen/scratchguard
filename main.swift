import AppKit
import SwiftUI
import AVFoundation
import Vision
import ServiceManagement

final class Monitor: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var running = false
    @Published var busy = false
    @Published var status = "Ready when you are"
    @Published var detail = "Start a session to turn on your camera."
    @Published var reminders = 0
    @Published var sessionSeconds = 0
    @Published var sensitivity = UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 0.5 {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity"); let value = sensitivity; queue.async { self.detector.sensitivity = value } }
    }
    @Published var voice = UserDefaults.standard.object(forKey: "voice") as? Bool ?? true { didSet { UserDefaults.standard.set(voice, forKey: "voice") } }
    @Published var login = SMAppService.mainApp.status == .enabled
    @Published var showPreview = true
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "ScratchGuard.camera", qos: .utility)
    var detector = ScratchDetector()
    var lastFrame = 0.0
    var lastReceived = 0.0
    var lastUI = 0.0
    var configured = false
    var timer: Timer?
    var observers: [NSObjectProtocol] = []
    let speaker = AVSpeechSynthesizer()
    var memePlayers: [AVAudioPlayer] = []
    var previousMeme: URL?
    lazy var memeURLs = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: "Sounds") ?? []
    var onAlert: (() -> Void)?
    let faceRequest = VNDetectFaceRectanglesRequest()
    let bodyRequest = VNDetectHumanBodyPoseRequest()
    let handRequest = VNDetectHumanHandPoseRequest()

    override init() {
        super.init()
        handRequest.maximumHandCount = 2
        detector.sensitivity = sensitivity
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            self.sessionSeconds += 1
            self.queue.async {
                if self.lastReceived > 0 && ProcessInfo.processInfo.systemUptime - self.lastReceived > 4 {
                    DispatchQueue.main.async { self.status = "Camera interrupted"; self.detail = "Waiting for camera frames. Try stopping and starting the session." }
                }
            }
        }
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                self?.status = "Camera interrupted"
                self?.detail = "Monitoring is unavailable. Try stopping and starting the session."
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.running else { return }
            self.queue.async { self.detector.reset(); self.lastReceived = ProcessInfo.processInfo.systemUptime; if !self.session.isRunning { self.session.startRunning() } }
        })
    }

    func start() {
        guard !running, !busy else { return }
        busy = true
        status = "Connecting to camera…"
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: beginCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { if granted { self.beginCapture() } else { self.permissionDenied() } }
            }
        default: permissionDenied()
        }
    }
    func permissionDenied() {
        busy = false
        status = "Camera access needed"
        detail = "Allow ScratchGuard in System Settings → Privacy & Security → Camera, then start again."
    }
    func beginCapture() {
        queue.async {
            do {
                if !self.configured {
                    guard let device = AVCaptureDevice.default(for: .video) else { throw NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera found. Connect a camera and try again."]) }
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .medium
                    guard self.session.canAddInput(input) else { self.session.commitConfiguration(); throw NSError(domain: "Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot use this camera."]) }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else { self.session.removeInput(input); self.session.commitConfiguration(); throw NSError(domain: "Camera", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot read camera frames."]) }
                    self.session.addOutput(output)
                    self.session.commitConfiguration()
                    self.configured = true
                }
                self.detector.reset()
                self.lastReceived = ProcessInfo.processInfo.systemUptime
                self.session.startRunning()
                let active = self.session.isRunning
                DispatchQueue.main.async {
                    self.busy = false
                    self.running = active
                    self.status = active ? "Looking for your head and hands" : "Camera could not start"
                    self.detail = active ? "Keep your head and hands visible in the camera." : "Another app may be using the camera. Try again."
                    if active { UserDefaults.standard.set(true, forKey: "resumeMonitoring") }
                }
            } catch {
                DispatchQueue.main.async { self.busy = false; self.status = "Camera unavailable"; self.detail = error.localizedDescription }
            }
        }
    }
    func stop() {
        guard !busy else { return }
        busy = true
        running = false
        UserDefaults.standard.set(false, forKey: "resumeMonitoring")
        speaker.stopSpeaking(at: .immediate)
        memePlayers.forEach { $0.stop() }
        memePlayers.removeAll()
        queue.async {
            self.session.stopRunning()
            self.detector.reset()
            DispatchQueue.main.async { self.busy = false; self.status = "Monitoring paused"; self.detail = "Your camera is off. Start whenever you’re ready." }
        }
    }
    func remind(count: Bool = true) {
        if count { reminders += 1; onAlert?() }
        if voice {
            let choices = memeURLs.filter { $0 != previousMeme }
            if let url = (choices.isEmpty ? memeURLs : choices).randomElement(), let player = try? AVAudioPlayer(contentsOf: url) {
                memePlayers.removeAll { !$0.isPlaying }
                memePlayers.append(player)
                player.volume = 0.65
                player.prepareToPlay()
                player.play()
                previousMeme = url
            } else { NSSound(named: "Glass")?.play() }
        } else { NSSound(named: "Glass")?.play() }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            login = SMAppService.mainApp.status == .enabled
            if enabled && !login { detail = "Approve ScratchGuard in System Settings → General → Login Items."; SMAppService.openSystemSettingsLoginItems() }
        } catch { login = SMAppService.mainApp.status == .enabled; detail = "Could not change launch at login: \(error.localizedDescription). Keep the app in Applications and try again." }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        lastReceived = now
        guard now - lastFrame > 0.06, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        autoreleasepool {
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up)
                try handler.perform([faceRequest, handRequest])
                let face = faceRequest.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })?.boundingBox
                if face == nil { try handler.perform([bodyRequest]) }
                let body = face == nil ? bodyRequest.results?.first : nil
                var head = face
                if head == nil, let points = try? body?.recognizedPoints(.all), let nose = points[.nose], nose.confidence > 0.3,
                   let left = points[.leftEar], let right = points[.rightEar], left.confidence > 0.25, right.confidence > 0.25 {
                    let width = max(abs(left.location.x - right.location.x) * 1.4, 0.12)
                    head = CGRect(x: nose.location.x - width / 2, y: nose.location.y - width * 0.35, width: width, height: width * 1.25)
                }
                var candidates: [String: MotionPoint] = [:]
                if let head, head.width > 0.035 {
                    // Include scalp above the face and temples beside it, excluding the chin.
                    let margin = 0.35 + self.detector.sensitivity * 0.6
                    let region = CGRect(x: head.minX - head.width * margin, y: head.minY + head.height * 0.15, width: head.width * (1 + margin * 2), height: head.height * 1.85)
                    for hand in handRequest.results ?? [] {
                        let points = try hand.recognizedPoints(.all)
                        let tips: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .ringTip, .littleTip, .thumbTip, .indexDIP, .middleDIP, .wrist]
                        let visible = tips.compactMap { points[$0] }.filter { $0.confidence > 0.25 }
                        let wrist = points[.wrist]
                        let location: CGPoint?
                        if let near = visible.first(where: { region.contains($0.location) }) { location = near.location }
                        else { location = wrist.flatMap { $0.confidence > 0.3 ? $0.location : nil } }
                        if let p = location, region.contains(p) {
                            let key = hand.chirality == .left ? "left" : hand.chirality == .right ? "right" : (p.x < head.midX ? "left" : "right")
                            candidates[key] = MotionPoint(x: (p.x - head.midX) / head.width, y: (p.y - head.midY) / head.height)
                        }
                    }
                }
                let alert = detector.update(time: now, hands: candidates)
                if now - lastUI > 0.6 || alert {
                    lastUI = now
                    let message = head == nil ? "Head not visible" : candidates.isEmpty ? "Monitoring · hands away" : "Hand near head · reminder active"
                    DispatchQueue.main.async {
                        guard self.running else { return }
                        self.status = message
                        self.detail = head == nil ? "Face the camera in good lighting so your head is visible." : "Monitoring continues when you close this window."
                        if alert { self.remind() }
                    }
                }
            } catch {
                detector.reset()
                DispatchQueue.main.async { if self.running { self.status = "Tracking unavailable"; self.detail = error.localizedDescription } }
            }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ view: PreviewView, context: Context) {}
}
final class PreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
        if let connection = preview.connection, connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = true }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); preview.frame = bounds }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    let accent = Color(red: 0.58, green: 0.87, blue: 0.67)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "hand.raised.fingers.spread.fill").font(.system(size: 24)).foregroundStyle(accent)
                Text("ScratchGuard").font(.system(size: 24, weight: .semibold, design: .rounded))
                Spacer()
                Text(monitor.running ? "CAMERA ON" : "CAMERA OFF").font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(monitor.running ? accent : .secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Hands down.\nStay focused.").font(.system(size: 30, weight: .medium, design: .rounded)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                Text("An instant nudge when your hand reaches your head.").foregroundStyle(.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.045))
                if monitor.running && monitor.showPreview {
                    CameraPreview(session: monitor.session).clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: monitor.running ? "eye.slash" : "video.slash").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                        Text(monitor.running ? "Preview hidden · monitoring continues" : "Your camera stays off until you start").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                VStack { Spacer(); HStack { Label("Processed on this Mac", systemImage: "lock.shield").font(.system(size: 10)); Spacer() }.padding(12).background(.black.opacity(0.4)) }.clipShape(RoundedRectangle(cornerRadius: 18))
            }.frame(height: 180)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) { Circle().fill(monitor.running ? accent : .gray).frame(width: 7, height: 7); Text(monitor.status).font(.system(size: 14, weight: .semibold)) }
                Text(monitor.detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(minHeight: 42, alignment: .topLeading)
            HStack(spacing: 12) {
                Button { monitor.running ? monitor.stop() : monitor.start() } label: {
                    Label(monitor.busy ? "Please wait…" : monitor.running ? "Pause monitoring" : "Start monitoring", systemImage: monitor.running ? "pause.fill" : "play.fill").frame(maxWidth: .infinity).padding(.vertical, 9)
                }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black).disabled(monitor.busy)
                Button("Test reminder") { monitor.remind(count: false) }.buttonStyle(.bordered).controlSize(.large)
            }
            Divider().overlay(.white.opacity(0.07))
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("\(monitor.reminders)").font(.system(size: 24, weight: .medium, design: .rounded)); Text("reminders this session").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) { Text(String(format: "%d:%02d", monitor.sessionSeconds / 60, monitor.sessionSeconds % 60)).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit(); Text("minutes monitored").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Sensitivity"); Spacer(); Text(monitor.sensitivity < 0.34 ? "Gentle" : monitor.sensitivity > 0.66 ? "Sensitive" : "Balanced").foregroundStyle(accent) }.font(.system(size: 12))
                Slider(value: $monitor.sensitivity, in: 0...1).tint(accent)
                Toggle("Random meme sounds · includes FAHHHH", isOn: $monitor.voice)
                Toggle("Show camera preview", isOn: $monitor.showPreview)
                Toggle("Launch at login", isOn: Binding(get: { monitor.login }, set: { monitor.setLogin($0) }))
            }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
            Text("No recordings. No uploads. Alerts on the first detected hand near your head, including ordinary head touching. New head touches alert immediately; held touches repeat every 4 seconds. Sounds can overlap. Keep your face and hands in view. Runs while your Mac is awake; closing this window keeps monitoring in the menu bar.").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 490).background(Color(red: 0.055, green: 0.085, blue: 0.075)).preferredColorScheme(.dark)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let monitor = Monitor()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var banner: NSPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.raised.fingers.spread", accessibilityDescription: "ScratchGuard")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open ScratchGuard", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Start / pause monitoring", action: #selector(toggleMonitoring), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ScratchGuard", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 850), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ScratchGuard"
        window.contentView = NSHostingView(rootView: Dashboard(monitor: monitor))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        monitor.onAlert = { [weak self] in self?.showReminder() }
        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized { showWindow() }
        if UserDefaults.standard.bool(forKey: "resumeMonitoring"), AVCaptureDevice.authorizationStatus(for: .video) == .authorized { monitor.start() }
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleMonitoring() { monitor.running ? monitor.stop() : monitor.start() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { monitor.session.stopRunning() }
    func showReminder() {
        banner?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HStack(spacing: 15) { Image(systemName: "hand.raised.fill").font(.system(size: 28)); VStack(alignment: .leading, spacing: 5) { Text("Stop scratching your head.").font(.system(size: 17, weight: .semibold)); Text("Relax your hands. Take a breath.").font(.system(size: 12)).foregroundStyle(.secondary) } }.padding(20).frame(width: 350, height: 100).background(.ultraThickMaterial).clipShape(RoundedRectangle(cornerRadius: 18)).preferredColorScheme(.dark))
        if let screen = NSScreen.main { let f = screen.visibleFrame; panel.setFrameOrigin(NSPoint(x: f.maxX - 374, y: f.maxY - 124)) }
        panel.orderFrontRegardless()
        banner = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak panel] in panel?.orderOut(nil) }
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
