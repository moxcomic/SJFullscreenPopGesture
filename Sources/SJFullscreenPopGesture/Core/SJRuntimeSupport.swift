//
//  SJRuntimeSupport.swift
//  SJFullscreenPopGesture
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import UIKit
import ObjectiveC.runtime

// MARK: - 关联对象 key

/// 关联对象使用的稳定地址 key。
///
/// ObjC 版以 `@selector(...)` 作为 key; Swift 改用各自独立的、进程级唯一且不可变的堆地址常量。
/// 每个 key 是一字节堆内存的地址, 仅在初始化后**取其地址作 key、从不解引用/写入**, 因此本质是
/// immutable shared state(进程内常驻, 永不释放, 共 11 字节, 可忽略), 满足 Swift6 严格并发,
/// 无数据竞争。维护者请勿对这些指针解引用或写入, 否则破坏 `nonisolated(unsafe)` 的安全前提。
enum SJAssociatedKeys {
    private static func make() -> UnsafeRawPointer {
        UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    }
    // UIViewController 公开配置
    nonisolated(unsafe) static let displayMode = make()
    nonisolated(unsafe) static let disableFullscreenGesture = make()
    nonisolated(unsafe) static let blindArea = make()
    nonisolated(unsafe) static let blindAreaViews = make()
    nonisolated(unsafe) static let viewWillBeginDragging = make()
    nonisolated(unsafe) static let viewDidDrag = make()
    nonisolated(unsafe) static let viewDidEndDragging = make()
    nonisolated(unsafe) static let considerWebView = make()
    // UIViewController 私有
    nonisolated(unsafe) static let previousViewControllerSnapshot = make()
    // UINavigationController 私有
    nonisolated(unsafe) static let didSetup = make()
    nonisolated(unsafe) static let fullscreenGesture = make()
}

// MARK: - KVC 辅助(忠实保留 ObjC 版非官方 API 行为)

extension UIGestureRecognizer {
    /// 强制将手势 state 置为 `.cancelled`。
    /// 忠实保留 ObjC 版 `[gesture setValue:@(UIGestureRecognizerStateCancelled) forKey:@"state"]` 行为。
    @MainActor
    func sj_cancel() {
        setValue(UIGestureRecognizer.State.cancelled.rawValue, forKey: "state")
    }
}

extension UINavigationController {
    /// 读取系统私有标记 `isTransitioning`(是否正在执行 push/pop 动画)。
    /// 忠实保留 ObjC 版 `[[nav valueForKey:@"isTransitioning"] boolValue]` 行为。
    @MainActor
    var sj_isTransitioning: Bool {
        (value(forKey: "isTransitioning") as? NSNumber)?.boolValue ?? false
    }
}

// MARK: - responder chain 查找

/// 沿 responder 链向上查找首个为指定类型的响应者。
/// 等价 ObjC 版 `_lookupResponder:class:`(从 `view.nextResponder` 起向上找)。
@MainActor
func sj_lookupResponder<T: UIResponder>(from view: UIView?, as type: T.Type) -> T? {
    var next: UIResponder? = view?.next
    while let current = next, (current is T) == false {
        next = current.next
    }
    return next as? T
}

