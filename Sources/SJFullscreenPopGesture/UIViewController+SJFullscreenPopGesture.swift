//
//  UIViewController+SJFullscreenPopGesture.swift
//  SJFullscreenPopGesture
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import UIKit
import WebKit
import ObjectiveC.runtime

// MARK: - 公开配置(SJExtendedFullscreenPopGesture)

/// `UIViewController` 全屏返回手势配置扩展。
///
/// 全部 `@objc` 暴露, 选择器与 ObjC 版一致(`sj_displayMode` / `setSj_displayMode:` 等),
/// 以便尚未迁移的 ObjC 消费方继续调用。存储均使用关联对象, 策略与 ObjC 版一致。
///
/// 线程契约(关键): 本扩展**不**标 `@MainActor`, 各成员为 nonisolated, 与 ObjC 原版一致——
/// 这些属性原本只是关联对象读写, 可在任意线程安全调用。setter 中的两处 UIKit 副作用
/// (`edgesForExtendedLayout` / `allowsBackForwardNavigationGestures`)在 Swift 中均非
/// 全局 actor 隔离成员, 可从 nonisolated 上下文调用, 行为与 ObjC 原版任意线程调用完全一致,
/// 不会引入额外的主线程断言/陷阱。
extension UIViewController {

    /// 拖动背景的显示模式, 默认 `.snapshot`。
    /// 存储策略 OBJC_ASSOCIATION_RETAIN_NONATOMIC。
    /// setter 同时设置 `edgesForExtendedLayout = []`(与 ObjC 版一致)。
    @objc public var sj_displayMode: SJPreViewDisplayMode {
        get {
            // ObjC 原版 getter 为 `[obj integerValue]`(无值默认 0 = snapshot)。
            let raw = (objc_getAssociatedObject(self, SJAssociatedKeys.displayMode) as? NSNumber)?.uintValue ?? 0
            return SJPreViewDisplayMode(rawValue: raw) ?? .snapshot
        }
        set {
            edgesForExtendedLayout = []
            objc_setAssociatedObject(self, SJAssociatedKeys.displayMode, NSNumber(value: newValue.rawValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// 禁用该 VC 的全屏手势, 默认 false。存储策略 OBJC_ASSOCIATION_RETAIN_NONATOMIC。
    @objc public var sj_disableFullscreenGesture: Bool {
        get { (objc_getAssociatedObject(self, SJAssociatedKeys.disableFullscreenGesture) as? NSNumber)?.boolValue ?? false }
        set { objc_setAssociatedObject(self, SJAssociatedKeys.disableFullscreenGesture, NSNumber(value: newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 手势盲区矩形数组(CGRect 装箱为 NSValue), 默认 nil。存储策略 OBJC_ASSOCIATION_COPY_NONATOMIC。
    @objc public var sj_blindArea: [NSValue]? {
        get { objc_getAssociatedObject(self, SJAssociatedKeys.blindArea) as? [NSValue] }
        set { objc_setAssociatedObject(self, SJAssociatedKeys.blindArea, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }

    /// 手势盲区视图数组, 默认 nil。存储策略 OBJC_ASSOCIATION_COPY_NONATOMIC。
    @objc public var sj_blindAreaViews: [UIView]? {
        get { objc_getAssociatedObject(self, SJAssociatedKeys.blindAreaViews) as? [UIView] }
        set { objc_setAssociatedObject(self, SJAssociatedKeys.blindAreaViews, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }

    /// 拖动将开始时回调。存储策略 OBJC_ASSOCIATION_COPY_NONATOMIC。
    @objc public var sj_viewWillBeginDragging: ((UIViewController) -> Void)? {
        get { sj_block(for: SJAssociatedKeys.viewWillBeginDragging) }
        set { sj_setBlock(newValue, for: SJAssociatedKeys.viewWillBeginDragging) }
    }

    /// 拖动中连续回调。存储策略 OBJC_ASSOCIATION_COPY_NONATOMIC。
    @objc public var sj_viewDidDrag: ((UIViewController) -> Void)? {
        get { sj_block(for: SJAssociatedKeys.viewDidDrag) }
        set { sj_setBlock(newValue, for: SJAssociatedKeys.viewDidDrag) }
    }

    /// 拖动结束时回调。存储策略 OBJC_ASSOCIATION_COPY_NONATOMIC。
    @objc public var sj_viewDidEndDragging: ((UIViewController) -> Void)? {
        get { sj_block(for: SJAssociatedKeys.viewDidEndDragging) }
        set { sj_setBlock(newValue, for: SJAssociatedKeys.viewDidEndDragging) }
    }

    /// 优先级 WebView: 当其 `canGoBack` 为 true 时禁用全屏手势(优先 WebView 自身返回)。
    /// 存储策略 OBJC_ASSOCIATION_RETAIN_NONATOMIC。
    /// setter 同时启用 `allowsBackForwardNavigationGestures = true`(与 ObjC 版一致)。
    @objc public var sj_considerWebView: WKWebView? {
        get { objc_getAssociatedObject(self, SJAssociatedKeys.considerWebView) as? WKWebView }
        set {
            newValue?.allowsBackForwardNavigationGestures = true
            objc_setAssociatedObject(self, SJAssociatedKeys.considerWebView, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // MARK: block 存取(以 OBJC_ASSOCIATION_COPY_NONATOMIC 桥接为 ObjC block)

    private func sj_block(for key: UnsafeRawPointer) -> ((UIViewController) -> Void)? {
        guard let obj = objc_getAssociatedObject(self, key) else { return nil }
        // 以 @convention(block) 存储, 取回时强转回 Swift 闭包。
        return obj as? ((UIViewController) -> Void)
    }

    private func sj_setBlock(_ block: ((UIViewController) -> Void)?, for key: UnsafeRawPointer) {
        if let block {
            // 显式 @convention(block) 以 ObjC block 形式存储, 兼容 ObjC 消费方按 void(^)(id) 读写。
            let objcBlock: @convention(block) (UIViewController) -> Void = { vc in block(vc) }
            objc_setAssociatedObject(self, key, objcBlock, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        } else {
            objc_setAssociatedObject(self, key, nil, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
}

// MARK: - 私有: 前一个 VC 的快照

extension UIViewController {
    /// push 时创建, 拖动时使用。存储策略 OBJC_ASSOCIATION_RETAIN_NONATOMIC。
    /// 私有, 仅内部主线程使用, 故标 `@MainActor`(SJSnapshot 为 @MainActor 隔离类型)。
    @MainActor
    var sj_previousViewControllerSnapshot: SJSnapshot? {
        get { objc_getAssociatedObject(self, SJAssociatedKeys.previousViewControllerSnapshot) as? SJSnapshot }
        set { objc_setAssociatedObject(self, SJAssociatedKeys.previousViewControllerSnapshot, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

