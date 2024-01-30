
import UIKit

class IconSearchView: UIView {
    
    var action: ((String) -> Void)?
    
    @objc private func cameraImageViewTapped() {
        // Handle cameraImageView tap event here
        action?("qrcode")
    }

    @objc private func borderViewTapped() {
        // Handle borderView tap event here
        action?("search")
    }

    @objc private func logoViewTapped() {
        // Handle cameraImageView tap event here
        action?("logo")
    }

    
    // Properties
    private let logoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "home_top", in: .module, compatibleWith: nil)
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    // 屏幕模式改变时的处理
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
      super.traitCollectionDidChange(previousTraitCollection)
        borderView.layer.borderColor = UIColor(named: "Color_txt", in: .module, compatibleWith: nil)?.cgColor
    }
    
    private let cameraImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "camera")
        imageView.tintColor = UIColor(named: "Color_txt", in: .module, compatibleWith: nil)
        imageView.contentMode = .center

        return imageView
    }()

    private let borderView: UIView = {
        let view = UIView()
        view.layer.borderWidth = 2.0
        view.layer.borderColor = UIColor(named: "Color_txt", in: .module, compatibleWith: nil)?.cgColor

        view.layer.cornerRadius = 16.0
        return view
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [logoImageView, borderView])
        stackView.axis = .vertical
        stackView.spacing = 28
        // stackView.backgroundColor = UIColor.red
        stackView.alignment = .center
        return stackView
    }()

    // Initializer
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // UI Setup
    private func setupUI() {
        addSubview(stackView)
        setupConstraints()
        isHidden = UIDevice.current.userInterfaceIdiom == .pad
    }

    private func setupConstraints() {
        // StackView Constraints
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
            //   stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            //  stackView.heightAnchor.constraint(equalToConstant: 330)
        ])

        // LogoImageView Constraints
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        
        
        let logoTapGesture = UITapGestureRecognizer(target: self, action: #selector(logoViewTapped))
        logoImageView.isUserInteractionEnabled = true
        logoImageView.addGestureRecognizer(logoTapGesture)
        
        let h =  UIScreen.main.bounds.width <= 375 ? 150 : 200
        NSLayoutConstraint.activate([
            logoImageView.topAnchor.constraint(equalTo: topAnchor, constant: CGFloat(h)),

            logoImageView.widthAnchor.constraint(equalToConstant: 125),
            logoImageView.heightAnchor.constraint(equalToConstant: 40)
        ])

        // BorderView Constraints
        borderView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // borderView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
           // borderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            borderView.widthAnchor.constraint(equalToConstant: UIScreen.main.bounds.width - 80),
            borderView.heightAnchor.constraint(equalToConstant: 62)
        ])

        // CameraImageView Constraints
        borderView.addSubview(cameraImageView)
        cameraImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraImageView.trailingAnchor.constraint(equalTo: borderView.trailingAnchor, constant: -16),
            cameraImageView.centerYAnchor.constraint(equalTo: borderView.centerYAnchor),
            cameraImageView.widthAnchor.constraint(equalToConstant: 24),
            cameraImageView.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Add tap gesture to cameraImageView
        let cameraTapGesture = UITapGestureRecognizer(target: self, action: #selector(cameraImageViewTapped))
        cameraImageView.isUserInteractionEnabled = true
        cameraImageView.addGestureRecognizer(cameraTapGesture)

        // Add tap gesture to borderView
        let borderTapGesture = UITapGestureRecognizer(target: self, action: #selector(borderViewTapped))
        borderView.isUserInteractionEnabled = true
        borderView.addGestureRecognizer(borderTapGesture)
    }
}
