//
//  SJFullscreenPopGestureDelegate.swift
//  SJFullscreenPopGesture
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import UIKit

/// 全屏返回手势委托(手势识别与冲突处理)。
///
/// 内部单例; 行为与 ObjC 版 `SJFullscreenPopGestureDelegate` 严格等价。
@MainActor
final class SJFullscreenPopGestureDelegate: NSObject, UIGestureRecognizerDelegate {

    /// 共享单例。等价 ObjC 版 `+shared`(dispatch_once)。
    static let shared = SJFullscreenPopGestureDelegate()

    private override init() { super.init() }

    // MARK: shouldReceiveTouch — 初步过滤

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let nav = sj_lookupResponder(from: gestureRecognizer.view, as: UINavigationController.self) else {
            return false
        }

        if nav.children.count <= 1 {
            return false
        }

        if nav.sj_isTransitioning {
            return false
        }

        if nav.topViewController?.sj_disableFullscreenGesture == true {
            return false
        }

        if blindAreaContains(nav: nav, point: touch.location(in: nav.view)) {
            return false
        }

        if nav.children.last is UINavigationController {
            return false
        }

        // ObjC: if (webView) return !webView.canGoBack;
        if let webView = nav.topViewController?.sj_considerWebView {
            return !webView.canGoBack
        }

        return true
    }

    // MARK: shouldBegin — 区分拖动方向

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if SJFullscreenPopGesture.gestureType == .edgeLeft {
            return true
        }

        // 防御性 cast: 本库手势恒为 UIPanGestureRecognizer(或其子类 UIScreenEdgePanGestureRecognizer),
        // 故此守卫运行期不可达; ObjC 原版以 UIPanGestureRecognizer* 形参直接调用 translationInView。
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return false
        }
        let translate = pan.translation(in: pan.view)

        if translate.x > 0 && translate.y == 0 {
            return true
        }

        return false
    }

    // MARK: shouldRecognizeSimultaneously — 手势冲突处理

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {

        if gestureRecognizer.state == .failed || gestureRecognizer.state == .cancelled {
            return false
        }

        if SJFullscreenPopGesture.gestureType == .edgeLeft {
            otherGestureRecognizer.sj_cancel()
            return true
        }

        // ObjC 版此处 nav 可能为 nil(随后 _blindAreaContains: 收到 nil 安全返回 false)。
        let nav = sj_lookupResponder(from: gestureRecognizer.view, as: UINavigationController.self)

        let location = gestureRecognizer.location(in: gestureRecognizer.view)

        if blindAreaContains(nav: nav, point: location) {
            return false
        }

        if otherGestureRecognizer.isMember(of: NSClassFromString("UIScrollViewPanGestureRecognizer") ?? NSNull.self) ||
           otherGestureRecognizer.isMember(of: NSClassFromString("UIScrollViewPagingSwipeGestureRecognizer") ?? NSNull.self) {
            // ObjC: if ([otherGestureRecognizer.view isKindOfClass:UIScrollView.class]) { ... }
            if let scrollView = otherGestureRecognizer.view as? UIScrollView,
               let pan = gestureRecognizer as? UIPanGestureRecognizer {
                return shouldRecognizeSimultaneously(scrollView: scrollView,
                                                     gestureRecognizer: pan,
                                                     otherGestureRecognizer: otherGestureRecognizer)
            }
        }

        // ObjC: otherGestureRecognizer.view isKindOfClass _MKMapContentView ||
        //       otherGestureRecognizer isKindOfClass UIWebTouchEventsGestureRecognizer
        let isMapContentView: Bool = {
            guard let cls = NSClassFromString("_MKMapContentView") else { return false }
            return otherGestureRecognizer.view?.isKind(of: cls) ?? false
        }()
        let isWebTouchEvents: Bool = {
            guard let cls = NSClassFromString("UIWebTouchEventsGestureRecognizer") else { return false }
            return otherGestureRecognizer.isKind(of: cls)
        }()

        if isMapContentView || isWebTouchEvents {
            if edgeAreaContains(nav: nav, point: location) {
                otherGestureRecognizer.sj_cancel()
                return true
            } else {
                return false
            }
        }

        // ObjC: if ([otherGestureRecognizer isKindOfClass:UIPanGestureRecognizer.class]) return false;
        if otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }

        return false
    }

    // MARK: ScrollView 手势冲突细致判断(等价 ObjC `_shouldRecognizeSimultaneously:...`)

    private func shouldRecognizeSimultaneously(scrollView: UIScrollView,
                                               gestureRecognizer: UIPanGestureRecognizer,
                                               otherGestureRecognizer: UIGestureRecognizer) -> Bool {

        if let queuingCls = NSClassFromString("_UIQueuingScrollView"), scrollView.isKind(of: queuingCls) {
            if scrollView.isDecelerating {
                return false
            }

            // ObjC: pageVC 为 nil 时 pageVC.viewControllers.count == 0 成立, 返回 false。
            guard let pageVC = sj_lookupResponder(from: scrollView, as: UIPageViewController.self) else {
                return false
            }

            if (pageVC.viewControllers?.count ?? 0) == 0 {
                return false
            }

            // ObjC: [pageVC.dataSource pageViewController:pageVC viewControllerBeforeViewController:firstObject] != nil
            if let first = pageVC.viewControllers?.first,
               let dataSource = pageVC.dataSource,
               dataSource.pageViewController(pageVC, viewControllerBefore: first) != nil {
                return false
            }

            otherGestureRecognizer.sj_cancel()
            return true
        }

        let translate = gestureRecognizer.translation(in: gestureRecognizer.view)

        if scrollView.contentOffset.x + scrollView.contentInset.left == 0
            && !scrollView.isDecelerating
            && translate.x > 0 && translate.y == 0 {
            otherGestureRecognizer.sj_cancel()
            return true
        }

        return false
    }

    // MARK: 私有辅助

    /// 等价 ObjC `_edgeAreaContains:point:`。
    private func edgeAreaContains(nav: UINavigationController?, point: CGPoint) -> Bool {
        guard let nav else { return false }
        let offset: CGFloat = 50
        let rect = CGRect(x: 0, y: 0, width: offset, height: nav.view.bounds.size.height)
        return rectContains(nav: nav, rect: rect, point: point, shouldConvert: false)
    }

    /// 等价 ObjC `_blindAreaContains:point:`(nav 为 nil 时安全返回 false)。
    private func blindAreaContains(nav: UINavigationController?, point: CGPoint) -> Bool {
        guard let nav, let top = nav.topViewController else { return false }

        for value in top.sj_blindArea ?? [] {
            if rectContains(nav: nav, rect: value.cgRectValue, point: point, shouldConvert: true) {
                return true
            }
        }

        for view in top.sj_blindAreaViews ?? [] {
            if rectContains(nav: nav, rect: view.frame, point: point, shouldConvert: true) {
                return true
            }
        }

        return false
    }

    /// 等价 ObjC `_rectContains:rect:point:shouldConvertRect:`。
    private func rectContains(nav: UINavigationController, rect: CGRect, point: CGPoint, shouldConvert: Bool) -> Bool {
        var r = rect
        if shouldConvert, let topView = nav.topViewController?.view {
            r = topView.convert(rect, to: nav.view)
        }
        return r.contains(point)
    }
}

