// swift-tools-version: 6.0
//
//  Package.swift
//  SJFullscreenPopGesture
//
//  Created by 畅三江 on 2019/7/17.
//  Copyright © 2019 SanJiang. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "SJFullscreenPopGesture",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SJFullscreenPopGesture",
            targets: ["SJFullscreenPopGesture"]
        )
    ],
    targets: [
        .target(
            name: "SJFullscreenPopGesture",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

