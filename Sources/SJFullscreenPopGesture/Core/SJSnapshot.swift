//
//  SJSnapshot.swift
//  SJFullscreenPopGesture
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import UIKit

/// 为拖动过程中显示的"前一个 ViewController"创建视觉快照(background view)。
///
/// 内部私有类型, 不对外暴露; 行为与 ObjC 版 `SJSnapshot` 严格等价。
/// 全部操作在主线程, 标 `@MainActor` 满足 Swift6 严格并发。
@MainActor
final class SJSnapshot: NSObject {

    /// 前一个 VC(弱引用)。
    private(set) weak var target: UIViewController?

    /// 快照容器(CGAffineTransform 动画目标)。
    let rootView: UIView

    /// 可选遮罩层(MaskAndShifting 模式下存在)。
    var maskView: UIView?

    init(target: UIViewController) {
        // target
        self.target = target

        // nav
        let nav = target.navigationController
        let root = UIView(frame: nav?.view.bounds ?? .zero)
        root.backgroundColor = .clear
        self.rootView = root

        super.init()

        // snapshot
        switch target.sj_displayMode {
        case .snapshot:
            // ObjC: nav.tabBarController != nil ? nav.tabBarController.view : nav.view
            let superview: UIView? = (nav?.tabBarController != nil) ? nav?.tabBarController?.view : nav?.view
            if let snapshot = superview?.snapshotView(afterScreenUpdates: false) {
                root.addSubview(snapshot)
            }
        case .origin:
            if let nav, nav.isNavigationBarHidden == false {
                var rect = nav.view.convert(nav.navigationBar.frame, to: nav.view.window)
                rect.size.height += rect.origin.y + 1
                rect.origin.y = 0
                if let navbarSnapshot = nav.view.superview?.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) {
                    root.addSubview(navbarSnapshot)
                }
            }

            if let tabBar = nav?.tabBarController?.tabBar, tabBar.isHidden == false, let window = nav?.view.window {
                var rect = tabBar.convert(tabBar.bounds, to: window)
                rect.origin.y -= 1
                rect.size.height += 1
                if let snapshot = window.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) {
                    snapshot.frame = rect
                    root.addSubview(snapshot)
                }
            }
        }

        // mask
        if SJFullscreenPopGesture.transitionMode == .maskAndShifting {
            let mask = UIView(frame: root.bounds)
            mask.backgroundColor = UIColor(white: 0.0, alpha: 0.8)
            root.addSubview(mask)
            self.maskView = mask
        }
    }

    /// 拖动开始: Origin 模式下, 将 target.view 插入 rootView 最底层。
    func began() {
        if target?.sj_displayMode == .origin, let targetView = target?.view {
            rootView.insertSubview(targetView, at: 0)
        }
    }

    /// 拖动结束: Origin 模式下, 若 target.view 仍在 rootView 中, 移除。
    func completed() {
        if target?.sj_displayMode == .origin,
           let targetView = target?.view,
           targetView.superview == rootView {
            targetView.removeFromSuperview()
        }
    }
}

