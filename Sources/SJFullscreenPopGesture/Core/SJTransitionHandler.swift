//
//  SJTransitionHandler.swift
//  SJFullscreenPopGesture
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import UIKit

/// 过渡动画过程管理(began / changed / completed 三阶段)。
///
/// 内部单例; 行为与 ObjC 版 `SJTransitionHandler` 严格等价。
/// 全部 UI 操作在主线程, 标 `@MainActor` 满足 Swift6 严格并发, 无数据竞争。
@MainActor
final class SJTransitionHandler: NSObject {

    /// 共享单例。等价 ObjC 版 `+shared`(dispatch_once)。
    static let shared = SJTransitionHandler()

    /// 负位移值, 初始 `-screenWidth * 0.382`, 用于快照平移动画。
    var shift: CGFloat

    /// 单一共享背景视图。
    let backgroundView: SJTransitionBackgroundView

    private override init() {
        self.shift = -UIScreen.main.bounds.size.width * 0.382
        self.backgroundView = SJTransitionBackgroundView(frame: .zero)
        super.init()
    }

    /// push 时为 viewController 关联"前一个 VC"的快照。
    /// 等价 ObjC `pushWithNav:viewController:`。
    func push(nav: UINavigationController, viewController: UIViewController) {
        if let last = nav.children.last {
            viewController.sj_previousViewControllerSnapshot = SJSnapshot(target: last)
        }
    }

    /// 手势 Began。等价 ObjC `beganWithNav:viewController:offset:`。
    func began(nav: UINavigationController, viewController: UIViewController, offset: CGFloat) {
        guard let snapshot = viewController.sj_previousViewControllerSnapshot else { return }

        // keyboard
        nav.view.endEditing(true)

        nav.view.superview?.insertSubview(snapshot.rootView, belowSubview: nav.view)
        nav.view.insertSubview(backgroundView, at: 0)
        backgroundView.frame = nav.view.bounds

        snapshot.began()

        snapshot.rootView.transform = CGAffineTransform(translationX: shift, y: 0)

        if SJFullscreenPopGesture.transitionMode == .maskAndShifting {
            snapshot.maskView?.alpha = 1
            let width = snapshot.rootView.frame.size.width
            snapshot.maskView?.transform = CGAffineTransform(translationX: -(shift + width), y: 0)
        }

        viewController.sj_viewWillBeginDragging?(viewController)

        changed(nav: nav, viewController: viewController, offset: offset)
    }

    /// 手势 Changed(连续)。等价 ObjC `changedWithNav:viewController:offset:`。
    func changed(nav: UINavigationController, viewController: UIViewController, offset rawOffset: CGFloat) {
        guard let snapshot = viewController.sj_previousViewControllerSnapshot else { return }

        var offset = rawOffset
        if offset < 0 { offset = 0 }

        nav.view.transform = CGAffineTransform(translationX: offset, y: 0)

        let width = snapshot.rootView.frame.size.width
        let rate = offset / width

        snapshot.rootView.transform = CGAffineTransform(translationX: shift * (1 - rate), y: 0)

        if SJFullscreenPopGesture.transitionMode == .maskAndShifting {
            snapshot.maskView?.alpha = 1 - rate
            snapshot.maskView?.transform = CGAffineTransform(translationX: -(shift + width) + (shift * rate) + offset, y: 0)
        }

        viewController.sj_viewDidDrag?(viewController)
    }

    /// 手势 Ended / Cancelled / Failed。等价 ObjC `completedWithNav:viewController:offset:`。
    func completed(nav: UINavigationController, viewController: UIViewController, offset: CGFloat) {
        guard let snapshot = viewController.sj_previousViewControllerSnapshot else { return }

        let screenwidth = nav.view.frame.size.width
        let rate = offset / screenwidth
        let maxOffset = SJFullscreenPopGesture.maxOffsetToTriggerPop
        let shouldPop = rate > maxOffset
        var animDuration: CGFloat = 0.25

        if shouldPop == false {
            animDuration = animDuration * (offset / (maxOffset * screenwidth)) + 0.05
        }

        UIView.animate(withDuration: TimeInterval(animDuration), animations: {
            if shouldPop {
                snapshot.rootView.transform = .identity
                snapshot.maskView?.transform = .identity
                snapshot.maskView?.alpha = 0.001

                nav.view.transform = CGAffineTransform(translationX: screenwidth, y: 0)
            } else {
                snapshot.maskView?.transform = CGAffineTransform(translationX: -(self.shift + screenwidth), y: 0)
                snapshot.maskView?.alpha = 1

                nav.view.transform = .identity
            }
        }, completion: { _ in
            self.backgroundView.removeFromSuperview()
            snapshot.rootView.removeFromSuperview()
            snapshot.completed()

            if shouldPop {
                nav.view.transform = .identity
                nav.popViewController(animated: false)
            }

            viewController.sj_viewDidEndDragging?(viewController)
        })
    }
}

