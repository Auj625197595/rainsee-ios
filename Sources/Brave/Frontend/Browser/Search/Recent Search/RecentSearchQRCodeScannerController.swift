// 注意：以下是对你提供的 Swift 代码的中文注释。

// 版权声明：2021年 Brave 作者保留所有权利。
// 此源代码表单受 Mozilla 公共许可证 v. 2.0 条款的约束。
// 如果未随此文件分发 MPL 的副本，则您可以在 http://mozilla.org/MPL/2.0/ 获取一份副本。

import AVFoundation
import BraveShared
import Foundation
import Shared
import UIKit

class RecentSearchQRCodeScannerController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let scannerView = ScannerView()
    private var didScan: Bool = false
    private var onDidScan: (_ string: String) -> Void

    // 检查是否支持相机
    public static var hasCameraSupport: Bool {
        !AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.isEmpty
    }

    // 检查是否有相机权限
    public static var hasCameraPermissions: Bool {
        // 状态 Restricted - 硬件限制，如家长控制
        let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        return status != .denied && status != .restricted
    }

    // 初始化方法
    init(onDidScan: @escaping (_ string: String) -> Void) {
        self.onDidScan = onDidScan
        super.init(nibName: nil, bundle: nil)
    }

    // 未实现的初始化方法
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 视图加载完成时调用
    override func viewDidLoad() {
        super.viewDidLoad()

        title = Strings.recentSearchScannerTitle
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(tappedDone))

        view.addSubview(scannerView)
        scannerView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        scannerView.cameraView.scanCallback = { [weak self] string in
            guard let self = self, !string.isEmpty, !self.didScan else { return }
            // 播放震动提示，表示代码扫描已完成
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
            UIImpactFeedbackGenerator(style: .medium).bzzt()

            self.didScan = true
            self.onDidScan(string)
            self.dismiss(animated: true, completion: nil)
        }

        scannerView.chooseImageButton.addTarget(self, action: #selector(chooseImage), for: .touchUpInside)

        // 设置图片选择器代理
        imagePicker.delegate = self
    }

    let imagePicker = UIImagePickerController()
    // 视图即将消失时调用
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        scannerView.cameraView.stopRunning()
    }

    @objc func chooseImage() {
        // 打开图片选择器
        imagePicker.sourceType = .photoLibrary
        present(imagePicker, animated: true, completion: nil)
    }

    // 处理用户选择的图片
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let selectedImage = info[.originalImage] as? UIImage {
            // 在这里处理选择的图片
            // 例如，你可以在这里将选择的图片显示在一个ImageView中
            // imageView.image = selectedImage

            // 关闭图片选择器
            picker.dismiss(animated: true, completion: nil)
            uploadImage(selectedImage)
        }
    }

    // 上传图片的方法
    func uploadImage(_ image: UIImage) {
        // 上传图片的URL
        let uploadURL = URL.brave.qrcodeScan

        // 创建URLRequest
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"

        // 设置上传图片的数据
        let imageData = image.jpegData(compressionQuality: 0.8) // 适应你的需求
        let boundary = UUID().uuidString

        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // 设置HTTPBody
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpeg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // 创建上传任务
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            // 处理上传结果
            if let error = error {
                print("上传失败: \(error.localizedDescription)")
            } else if let data = data {
                //   let result = String(data: data, encoding: .utf8)
                do {
                    if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let msg = jsonObject["msg"] as? [String: Any],
                       let resultArray = msg["result"] as? [[String: Any]],
                       let data = resultArray.first?["data"] as? String
                    {
                        print("Data: \(data)")

                        DispatchQueue.main.async {
                            self.didScan = true
                            self.onDidScan(data)
                            self.dismiss(animated: true, completion: nil)
                        }

                    } else {
                        print("解析JSON失败")
                        self.alertNoQrcode()
                    }
                } catch {
                    print("解析JSON失败：\(error)")
                    self.alertNoQrcode()
                }
                // print("上传成功: \(result ?? "")")
            }
        }

        // 启动上传任务
        task.resume()
    }

    func alertNoQrcode() {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: Strings.Other.alertTitle, message: Strings.Other.noQrcode, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

            // 获取当前显示的视图控制器
            self.present(alertController, animated: true, completion: nil)
        }
     
    }

    // 处理用户取消选择图片
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }

    // 视图即将显示时调用
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        scannerView.cameraView.stopRunning()
    }

    // 视图已经出现时调用
    override func viewDidAppear(_ animated: Bool) {
        if let orientation = view.window?.windowScene?.interfaceOrientation {
            scannerView.cameraView.videoPreviewLayer?.connection?.videoOrientation = AVCaptureVideoOrientation(ui: orientation)
        }
        scannerView.cameraView.startRunning()
    }

    // 视图将要转换大小时调用
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        scannerView.cameraView.stopRunning()

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }

            if let orientation = self.view.window?.windowScene?.interfaceOrientation {
                self.scannerView.cameraView.videoPreviewLayer?.connection?.videoOrientation = AVCaptureVideoOrientation(ui: orientation)
            }
            self.scannerView.cameraView.startRunning()
        }
    }

    // MARK: - Actions

    // 点击完成按钮时调用
    @objc private func tappedDone() {
        dismiss(animated: true)
    }
}

extension RecentSearchQRCodeScannerController {
    class ScannerView: UIView {
        let cameraView = SyncCameraView().then {
            $0.backgroundColor = .black
            $0.layer.cornerRadius = 4
            $0.layer.cornerCurve = .continuous
        }

        private let scrollView = UIScrollView()
        private let stackView = UIStackView().then {
            $0.axis = .vertical
            $0.spacing = 6
            $0.alignment = .leading
        }

        private let titleLabel = UILabel().then {
            $0.text = Strings.recentSearchScannerDescriptionTitle
            $0.font = .systemFont(ofSize: 17, weight: .semibold)
            $0.numberOfLines = 0
            $0.textColor = .braveLabel
        }

        private let bodyLabel = UILabel().then {
            $0.text = Strings.recentSearchScannerDescriptionBody
            $0.font = .systemFont(ofSize: 17)
            $0.numberOfLines = 0
            $0.textColor = .braveLabel
        }
        
        public let chooseImageButton = UIButton().then {
            $0.setTitle(Strings.Other.selectPhoto, for: .normal)
            $0.setTitleColor(UIColor.braveBlurple, for: .normal)
          //  $0.frame = CGRect(x: 50, y: 100, width: 200, height: 40)
        }
        // 创建选择图片的按钮

        // 初始化方法
        override init(frame: CGRect) {
            super.init(frame: frame)

            backgroundColor = .secondaryBraveBackground

            addSubview(cameraView)
            addSubview(scrollView)
            scrollView.addSubview(stackView)
            stackView.addStackViewItems(
                .view(titleLabel),
                .view(bodyLabel),
                .view(chooseImageButton)
            )

            cameraView.snp.makeConstraints {
                $0.top.equalTo(self.safeAreaLayoutGuide).inset(10)
                $0.leading.greaterThanOrEqualTo(self.safeAreaLayoutGuide).inset(10)
                $0.trailing.lessThanOrEqualTo(self.safeAreaLayoutGuide).inset(10)
                $0.centerX.equalToSuperview()
                $0.height.equalTo(cameraView.snp.width)
                $0.width.lessThanOrEqualTo(375)
            }

            scrollView.snp.makeConstraints {
                $0.top.equalTo(cameraView.snp.bottom).offset(10)
                $0.leading.trailing.bottom.equalToSuperview()
            }
            scrollView.contentLayoutGuide.snp.makeConstraints {
                $0.top.bottom.equalTo(stackView)
                $0.width.equalToSuperview()
            }
            stackView.snp.makeConstraints {
                $0.edges.equalToSuperview().inset(10)
            }
        }

        // 未实现的初始化方法
        @available(*, unavailable)
        required init(coder: NSCoder) {
            fatalError()
        }
    }
}
