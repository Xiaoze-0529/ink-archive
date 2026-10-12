import AVFoundation
import SwiftUI
import UIKit

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraController()
    let onCapture: (Data) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            VStack {
                HStack {
                    Button("取消") { dismiss() }.disabled(camera.capturing)
                    Spacer()
                    Text("整页拍摄").font(.headline)
                }.padding(20).background(.black.opacity(0.4))
                Spacer()
                if let message = camera.message {
                    VStack(spacing: 12) {
                        Text(message).multilineTextAlignment(.center)
                        if camera.permissionDenied {
                            Button("打开设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.buttonStyle(.bordered)
                        } else {
                            Button("重试") { camera.start() }.buttonStyle(.bordered)
                        }
                    }.padding(24).background(.black.opacity(0.65))
                }
                Spacer()
                Text("请将整页放入画面，保持平稳").font(.subheadline)
                    .padding(8).background(.black.opacity(0.4))
                Button { camera.takePhoto() } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                        Circle().fill(.white).frame(width: 62, height: 62)
                        if camera.capturing { ProgressView().tint(.black) }
                    }
                }.disabled(!camera.ready || camera.capturing).accessibilityLabel("拍摄手账页").padding(24)
            }.foregroundStyle(.white)
        }
        .task { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() } else { camera.stop() }
        }
        .onReceive(camera.$capturedData) { data in
            if let data { onCapture(data) }
        }
    }
}

/// Session configuration, start/stop, and capture run on one serial queue.
/// Published UI changes are dispatched to the main queue.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published private(set) var ready = false
    @Published private(set) var capturing = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var message: String?
    @Published private(set) var capturedData: Data?

    private let sessionQueue = DispatchQueue(label: "com.inkarchive.camera")
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var wantsRunning = false

    func start() {
        sessionQueue.async {
            self.wantsRunning = true
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.configureAndStart()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    self.sessionQueue.async {
                        guard self.wantsRunning else { return }
                        if granted { self.configureAndStart() }
                        else { self.report("需要相机权限才能拍摄。也可取消后从相册导入。", denied: true) }
                    }
                }
            default: self.report("相机权限未开启。请在设置中允许访问，或从相册导入。", denied: true)
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.wantsRunning = false
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.ready = false }
        }
    }

    func takePhoto() {
        guard ready, !capturing else { return }
        capturing = true
        sessionQueue.async {
            guard self.session.isRunning else { self.report("相机已暂停，请重试。"); return }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureAndStart() {
        guard wantsRunning else { return }
        if !configured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                report("这台设备没有可用的后置相机。模拟器请使用相册导入。")
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    report("无法连接相机输入。")
                    return
                }
                session.addInput(input)
                guard session.canAddOutput(output) else {
                    session.removeInput(input)
                    session.commitConfiguration()
                    report("无法连接照片输出。")
                    return
                }
                session.addOutput(output)
                output.maxPhotoQualityPrioritization = .quality
                session.commitConfiguration()
                configured = true
            } catch { report("相机启动失败：\(error.localizedDescription)"); return }
        }
        if !session.isRunning { session.startRunning() }
        DispatchQueue.main.async {
            self.message = nil
            self.permissionDenied = false
            self.ready = true
        }
    }

    private func report(_ message: String, denied: Bool = false) {
        DispatchQueue.main.async {
            self.message = message
            self.permissionDenied = denied
            self.ready = false
            self.capturing = false
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { report("拍摄失败：\(error.localizedDescription)"); return }
        guard let data = photo.fileDataRepresentation() else { report("未收到图片，请重新拍摄。"); return }
        DispatchQueue.main.async {
            self.capturing = false
            self.capturedData = data
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error { report("拍摄失败：\(error.localizedDescription)") }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}
