//
//  SJTransitionBackgroundView.swift
//  SJFullscreenPopGesture
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import UIKit

/// 提供带阴影效果的纯白背景, 作为 navigationController.view 的底层。
///
/// 内部私有类型; 行为与 ObjC 版 `SJTransitionBackgroundView` 严格等价。
@MainActor
final class SJTransitionBackgroundView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.shadowOffset = CGSize(width: 0.5, height: 0)
        layer.shadowColor = UIColor(white: 0.2, alpha: 1).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }
}

