//
//  UINavigationController+SJFullscreenPopGesture.swift
//  SJFullscreenPopGesture
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import UIKit
import ObjectiveC.runtime

// MARK: - 公开扩展(SJExtendedFullscreenPopGesture)

extension UINavigationController {

    /// 当前全屏手势的状态(只读)。
    /// 等价 ObjC 版 `sj_fullscreenGestureState`, 选择器一致。
    ///
    /// 该 getter 会按需创建并访问手势对象, 属"确需主线程"的成员, 故标 `@MainActor`
    /// (评审认可)。ObjC 消费方应在主线程读取。
    @MainActor
    @objc public var sj_fullscreenGestureState: UIGestureRecognizer.State {
        sj_fullscreenGesture.state
    }
}

// MARK: - 私有: swizzling 安装(幂等, 可任意线程)

extension UINavigationController {

    /// 安装 method swizzling(幂等)。
    ///
    /// 等价 ObjC 版 `+load` 内的 `method_exchangeImplementations`。Swift 禁止 `+load`,
    /// 纯 SPM 亦无可靠启动期自动执行点, 故由 `SJFullscreenPopGesture.install()` 显式触发。
    /// 交换操作仅访问类/元类的 method 列表(线程安全的 C 函数), 故 nonisolated, 可任意线程调用。
    nonisolated static func sj_installFullscreenPopGestureSwizzlingIfNeeded() {
        SJSwizzleOnce.run()
    }

    /// swizzled 的 push 实现(hook 点)。
    ///
    /// 交换 IMP 后:
    /// - 调用方调用 `pushViewController(_:animated:)` 实际执行本方法体;
    /// - 本方法体内调用 `sj_pushViewController(_:animated:)` 实际派发到原始系统实现, 完成真实 push。
    ///
    /// 该方法标 `nonisolated`(无 `@MainActor`), 故经 `method_exchangeImplementations` 交换后,
    /// `pushViewController` 选择器指向的 thunk **不会**额外插入主线程断言, 与 ObjC 原版
    /// `pushViewController` 的断言行为一致(评审 medium 修正)。setup 与快照建立涉及 @MainActor
    /// 状态, 用 `MainActor.assumeIsolated` 包裹: 主线程调用与 ObjC 完全一致; 后台线程调用本属
    /// UIKit 未定义行为, 此处以断言形式更早暴露(罕见违规路径)。
    @objc dynamic func sj_pushViewController(_ viewController: UIViewController, animated: Bool) {
        MainActor.assumeIsolated {
            sj_setupIfNeeded()
            SJTransitionHandler.shared.push(nav: self, viewController: viewController)
        }
        // 交换后此调用执行原始 pushViewController 实现(递归派发, 不会无限递归)。
        sj_pushViewController(viewController, animated: animated)
    }
}

// MARK: - 私有: 手势管理(主线程)

extension UINavigationController {

    /// 一次性初始化导航控制器的手势系统。等价 ObjC `sj_setupIfNeeded`。
    @MainActor
    func sj_setupIfNeeded() {
        if interactivePopGestureRecognizer == nil {
            return
        }

        if (objc_getAssociatedObject(self, SJAssociatedKeys.didSetup) as? NSNumber)?.boolValue == true {
            return
        }

        objc_setAssociatedObject(self, SJAssociatedKeys.didSetup, NSNumber(value: true), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        interactivePopGestureRecognizer?.isEnabled = false
        view.clipsToBounds = false

        view.addGestureRecognizer(sj_fullscreenGesture)
    }

    /// 全屏手势(延迟创建并缓存)。等价 ObjC `sj_fullscreenGesture`。
    @MainActor
    var sj_fullscreenGesture: UIPanGestureRecognizer {
        if let gesture = objc_getAssociatedObject(self, SJAssociatedKeys.fullscreenGesture) as? UIPanGestureRecognizer {
            return gesture
        }

        let gesture: UIPanGestureRecognizer
        if SJFullscreenPopGesture.gestureType == .edgeLeft {
            let edge = UIScreenEdgePanGestureRecognizer()
            edge.edges = .left
            gesture = edge
        } else {
            gesture = UIPanGestureRecognizer()
        }

        gesture.delaysTouchesBegan = true
        gesture.delegate = SJFullscreenPopGestureDelegate.shared
        gesture.addTarget(self, action: #selector(sj_handleFullscreenGesture(_:)))
        objc_setAssociatedObject(self, SJAssociatedKeys.fullscreenGesture, gesture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return gesture
    }

    /// 手势回调。等价 ObjC `sj_handleFullscreenGesture:`。
    @MainActor
    @objc func sj_handleFullscreenGesture(_ gesture: UIPanGestureRecognizer) {
        let offset = gesture.translation(in: gesture.view).x
        // ObjC 版以 self.topViewController(可能为 nil)调用各阶段方法, 内部 snapshot 为 nil 时直接返回。
        // 此处栈非空(已通过 shouldReceiveTouch 的 count<=1 过滤), top 一般非 nil。
        let top = topViewController
        guard let top else { return }

        switch gesture.state {
        case .began:
            SJTransitionHandler.shared.began(nav: self, viewController: top, offset: offset)
        case .changed:
            SJTransitionHandler.shared.changed(nav: self, viewController: top, offset: offset)
        case .ended, .cancelled, .failed:
            SJTransitionHandler.shared.completed(nav: self, viewController: top, offset: offset)
        case .possible:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - swizzle once 容器(nonisolated, 等价 dispatch_once)

/// 以 NSLock 保护的一次性 swizzle 触发器, 等价 ObjC `dispatch_once`。
/// nonisolated: 仅访问类/元类 method 列表, 不涉及实例隔离。
private enum SJSwizzleOnce {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var done = false

    static func run() {
        lock.lock()
        defer { lock.unlock() }
        if done { return }
        done = true

        let cls: AnyClass = UINavigationController.self
        let originalSelector = #selector(UINavigationController.pushViewController(_:animated:))
        let swizzledSelector = #selector(UINavigationController.sj_pushViewController(_:animated:))

        guard let originalMethod = class_getInstanceMethod(cls, originalSelector),
              let swizzledMethod = class_getInstanceMethod(cls, swizzledSelector) else {
            return
        }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

