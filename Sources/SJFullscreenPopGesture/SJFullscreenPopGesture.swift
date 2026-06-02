//
//  SJFullscreenPopGesture.swift
//  SJBackGRProject
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import UIKit

// MARK: - 公开枚举(@objc 暴露, 与原 ObjC 选择器/原始值一致)

/// 手势类型。
/// - 对应 ObjC `SJFullscreenPopGestureType`(`SJFullscreenPopGestureTypeEdgeLeft=0` / `...Full=1`)。
/// - 底层类型用 `UInt`, 生成 ObjC `NSUInteger`, 与原版 `typedef enum : NSUInteger` 逐字节一致。
@objc public enum SJFullscreenPopGestureType: UInt, Sendable {
    /// 仅左边缘(UIScreenEdgePanGestureRecognizer)。
    case edgeLeft = 0
    /// 全屏(UIPanGestureRecognizer)。
    case full = 1
}

/// 过渡动画模式。
/// - 对应 ObjC `SJFullscreenPopGestureTransitionMode`(`...Shifting=0` / `...MaskAndShifting=1`)。
/// - 底层类型用 `UInt`, 生成 ObjC `NSUInteger`, 与原版一致。
@objc public enum SJFullscreenPopGestureTransitionMode: UInt, Sendable {
    /// 仅前一个 VC 平移。
    case shifting = 0
    /// 前一个 VC 平移 + 遮罩淡出。
    case maskAndShifting = 1
}

/// 拖动背景的显示模式。
/// - 对应 ObjC `SJPreViewDisplayMode`(`SJPreViewDisplayModeSnapshot=0` / `...Origin=1`)。
/// - 底层类型用 `UInt`, 生成 ObjC `NSUInteger`, 与原版一致。
@objc public enum SJPreViewDisplayMode: UInt, Sendable {
    /// 快照显示(有 tabBarController 时抓整个 tabBarController.view)。
    case snapshot = 0
    /// 原始显示(单独显示导航栏 + 前一个 VC + tabBar 片段)。
    case origin = 1
}

// MARK: - 全局配置

/// 全屏返回手势的全局配置类。
///
/// 行为与 ObjC 版严格等价: 以进程级全局变量存储 `gestureType` / `transitionMode` /
/// `maxOffsetToTriggerPop`, 修改后对"新创建的手势 / 新交互"生效。
///
/// 线程契约(对 ObjC 消费方影响): ObjC 版这三个类属性为普通 static 变量, 可在任意线程读写。
/// 本实现以 `NSLock` 保护其读写, 同样允许任意线程访问且消除 Swift6 数据竞争。故未将该类标
/// `@MainActor`, ObjC 消费方从后台线程读写 `[SJFullscreenPopGesture gestureType]` 等不会陷阱。
///
/// 安装时机(相对 ObjC 版唯一的接入差异): ObjC 版通过 `+load` 在类加载期自动完成 swizzling。
/// Swift 明确禁止 `+load`(`method 'load()' ... is not permitted by Swift`), 纯 Swift/SPM
/// target 也无可靠的启动期自动执行点, 因此必须在 App 启动尽早显式调用一次
/// `SJFullscreenPopGesture.install()`(幂等)。该方法 `@objc` 暴露, 选择器为 `install`。
@objc(SJFullscreenPopGesture)
public final class SJFullscreenPopGesture: NSObject {

    // 全局配置存储。以 NSLock 保护, 保留 ObjC 版"任意线程可读写"的契约,
    // 同时满足 Swift6 严格并发(无数据竞争)。
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _gestureType: SJFullscreenPopGestureType = .edgeLeft
    nonisolated(unsafe) private static var _transitionMode: SJFullscreenPopGestureTransitionMode = .shifting
    nonisolated(unsafe) private static var _maxOffsetToTriggerPop: CGFloat = 0.35

    /// 手势类型, 默认 `.edgeLeft`。修改后对新创建的手势生效。可任意线程读写。
    @objc public class var gestureType: SJFullscreenPopGestureType {
        get { lock.lock(); defer { lock.unlock() }; return _gestureType }
        set { lock.lock(); _gestureType = newValue; lock.unlock() }
    }

    /// 动画模式, 默认 `.shifting`。修改后对新的交互生效。可任意线程读写。
    @objc public class var transitionMode: SJFullscreenPopGestureTransitionMode {
        get { lock.lock(); defer { lock.unlock() }; return _transitionMode }
        set { lock.lock(); _transitionMode = newValue; lock.unlock() }
    }

    /// 触发 pop 的拖动比例阈值, 默认 0.35(rate > 0.35 时执行 pop)。可任意线程读写。
    @objc public class var maxOffsetToTriggerPop: CGFloat {
        get { lock.lock(); defer { lock.unlock() }; return _maxOffsetToTriggerPop }
        set { lock.lock(); _maxOffsetToTriggerPop = newValue; lock.unlock() }
    }

    /// 安装全屏返回手势(对 `UINavigationController.pushViewController(_:animated:)` 进行 method swizzling)。
    ///
    /// - 幂等: 内部以等价 `dispatch_once` 的机制保证仅交换一次, 除 swizzle 外不引入任何其它隐式依赖。
    /// - 行为等价于 ObjC 版 `+[UINavigationController(_SJFullscreenPopGesturePrivate) load]` 内的交换。
    /// - 必须在 App 启动尽早调用一次(如 `application(_:didFinishLaunchingWithOptions:)`),
    ///   且应在任何 `pushViewController` 之前调用, 否则该次 push 不会建立前一个 VC 的快照, 手势对其失效。
    /// - 可任意线程调用(交换操作仅访问类/元类的 method 列表, 不涉及实例隔离)。
    @objc public class func install() {
        UINavigationController.sj_installFullscreenPopGestureSwizzlingIfNeeded()
    }
}

