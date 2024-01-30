/* 该源代码形式受 Mozilla 公共许可证 2.0 版的条款约束。
 * 如果本文件未随此文件分发，您可以在 http://mozilla.org/MPL/2.0/ 获取一份。 */

import Foundation
import UIKit

// 定义滑动动画的参数结构体
struct SwipeAnimationParameters {
    let totalRotationInDegrees: Double  // 总旋转角度（度）
    let deleteThreshold: CGFloat       // 删除阈值
    let totalScale: CGFloat            // 总缩放比例
    let totalAlpha: CGFloat            // 总透明度
    let minExitVelocity: CGFloat       // 最小退出速度
    let recenterAnimationDuration: TimeInterval  // 重新居中动画的持续时间
}

// 默认参数
private let DefaultParameters =
    SwipeAnimationParameters(
        totalRotationInDegrees: 10,
        deleteThreshold: 80,
        totalScale: 0.9,
        totalAlpha: 0,
        minExitVelocity: 800,
        recenterAnimationDuration: 0.15)

// 滑动动画的委托协议
protocol SwipeAnimatorDelegate: AnyObject {
    func swipeAnimator(_ animator: SwipeAnimator, viewWillExitContainerBounds: UIView)
}

// 滑动动画类
class SwipeAnimator: NSObject {
    weak var delegate: SwipeAnimatorDelegate?
    weak var animatingView: UIView?

    fileprivate var prevOffset: CGPoint?
    fileprivate let params: SwipeAnimationParameters

    fileprivate var panGestureRecogniser: UIPanGestureRecognizer!

    // 计算容器中心
    var containerCenter: CGPoint {
        guard let animatingView = self.animatingView else {
            return .zero
        }
        return CGPoint(x: animatingView.frame.width / 2, y: animatingView.frame.height / 2)
    }

    // 初始化方法
    init(animatingView: UIView, params: SwipeAnimationParameters = DefaultParameters) {
        self.animatingView = animatingView
        self.params = params

        super.init()

        self.panGestureRecogniser = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        animatingView.addGestureRecognizer(self.panGestureRecogniser)
        self.panGestureRecogniser.delegate = self
    }

    // 取消已有手势
    func cancelExistingGestures() {
        self.panGestureRecogniser.isEnabled = false
        self.panGestureRecogniser.isEnabled = true
    }
}

// MARK: - 私有助手方法
extension SwipeAnimator {
    // 动画返回到中心位置
    fileprivate func animateBackToCenter() {
        UIView.animate(
            withDuration: params.recenterAnimationDuration,
            animations: {
                self.animatingView?.transform = .identity
                self.animatingView?.alpha = 1
            })
    }

    // 根据速度和速度计算动画消失
    fileprivate func animateAwayWithVelocity(_ velocity: CGPoint, speed: CGFloat) {
        guard let animatingView = self.animatingView else {
            return
        }

        // 计算边缘以计算距离
        let translation = velocity.x >= 0 ? animatingView.frame.width : -animatingView.frame.width
        let timeStep = TimeInterval(abs(translation) / speed)
        self.delegate?.swipeAnimator(self, viewWillExitContainerBounds: animatingView)
        UIView.animate(
            withDuration: timeStep,
            animations: {
                animatingView.transform = self.transformForTranslation(translation)
                animatingView.alpha = self.alphaForDistanceFromCenter(abs(translation))
            },
            completion: { finished in
                if finished {
                    animatingView.alpha = 0
                }
            })
    }

    // 根据平移计算变换
    fileprivate func transformForTranslation(_ translation: CGFloat) -> CGAffineTransform {
        let swipeWidth = animatingView?.frame.size.width ?? 1
        let totalRotationInRadians = CGFloat(params.totalRotationInDegrees / 180.0 * Double.pi)

        // 通过到边缘的距离确定旋转/缩放量
        let rotation = (translation / swipeWidth) * totalRotationInRadians
        let scale = 1 - (abs(translation) / swipeWidth) * (1 - params.totalScale)

        let rotationTransform = CGAffineTransform(rotationAngle: rotation)
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let translateTransform = CGAffineTransform(translationX: translation, y: 0)
        return rotationTransform.concatenating(scaleTransform).concatenating(translateTransform)
    }

    // 根据距离计算透明度
    fileprivate func alphaForDistanceFromCenter(_ distance: CGFloat) -> CGFloat {
        let swipeWidth = animatingView?.frame.size.width ?? 1
        return 1 - (distance / swipeWidth) * (1 - params.totalAlpha)
    }
}

// MARK: - 选择器
extension SwipeAnimator {
    @objc func didPan(_ recognizer: UIPanGestureRecognizer!) {
        let translation = recognizer.translation(in: animatingView)

        switch recognizer.state {
        case .began:
            prevOffset = containerCenter
        case .changed:
            animatingView?.transform = transformForTranslation(translation.x)
            animatingView?.alpha = alphaForDistanceFromCenter(abs(translation.x))
            prevOffset = CGPoint(x: translation.x, y: 0)
        case .cancelled:
            animateBackToCenter()
        case .ended:
            let velocity = recognizer.velocity(in: animatingView)
            // 如果速度太低或者尚未达到阈值，则弹回
            let speed = max(abs(velocity.x), params.minExitVelocity)
            if speed < params.minExitVelocity || abs(prevOffset?.x ?? 0) < params.deleteThreshold {
                animateBackToCenter()
            } else {
                animateAwayWithVelocity(velocity, speed: speed)
            }
        default:
            break
        }
    }

    // 关闭视图，指定方向
    func close(right: Bool) {
        let direction = CGFloat(right ? -1 : 1)
        animateAwayWithVelocity(CGPoint(x: -direction * params.minExitVelocity, y: 0), speed: direction * params.minExitVelocity)
    }

    // 无手势关闭视图
    @discardableResult @objc func closeWithoutGesture() -> Bool {
        close(right: false)
        return true
    }
}

// 扩展 SwipeAnimator 以实现手势识别委托
extension SwipeAnimator: UIGestureRecognizerDelegate {
    @objc func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = recognizer as? UIPanGestureRecognizer else { return false }
        let cellView = recognizer.view
        let translation = panGesture.translation(in: cellView?.superview)
        return abs(translation.x) > abs(translation.y)
    }
}
