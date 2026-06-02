# SJFullscreenPopGesture

`UINavigationController` 全屏 / 边缘返回手势库，支持 UIKit 与 WebKit，基于 method swizzling 实现。

让你在任意 `UINavigationController` 中通过「屏幕左边缘」或「全屏拖动」触发返回（pop），并提供逐 VC 的精细化控制（禁用手势、盲区、拖动回调、WebView 优先返回等）。

> 本仓库是 [changsanjiang/SJFullscreenPopGesture](https://github.com/changsanjiang/SJFullscreenPopGesture) 的 fork。

---

## 已迁移到 Swift 6 + SPM

原版是 **Objective-C + CocoaPods**，本 fork 已**全面用 Swift 原生重写**，并改为通过 **Swift Package Manager** 分发：

- 源码全部为 Swift（`Sources/SJFullscreenPopGesture/`），以 Swift 6 语言模式（严格并发）编译。
- 不再提供 CocoaPods 的 `SJFullscreenPopGesture/ObjC` 与 `SJFullscreenPopGesture/Swift` 两个 subspec，统一为单一 SPM 产物。
- swizzling 经 Objective-C runtime 保留（交换 `UINavigationController.pushViewController(_:animated:)` 的实现），核心交互行为与原版严格等价。
- 公开类型与属性均带 `@objc`，选择器、枚举原始值与原 ObjC 版逐字节对齐，便于尚未迁移的 ObjC 消费方继续调用。

> **重要破坏性变更：不再自动安装。** 原 ObjC 版通过 `+load` 在类加载期自动完成 swizzling；Swift 禁止 `+load`，纯 SPM target 也没有可靠的启动期自动执行点，因此**必须在 App 启动时显式调用一次 `SJFullscreenPopGesture.install()`**。详见下文「迁移注意」。

---

## 环境要求

- iOS 15.0+
- Swift 6（`swift-tools-version: 6.0`，以 Swift 6 语言模式编译）
- 使用 Swift 6.3 / Xcode 26 工具链验证，iOS 模拟器编译通过

---

## 安装（Swift Package Manager）

### 方式一：Xcode

`File > Add Package Dependencies...`，输入仓库地址：

```
https://github.com/moxcomic/SJFullscreenPopGesture.git
```

分支选择 `main`。

### 方式二：Package.swift

在 `dependencies` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/moxcomic/SJFullscreenPopGesture.git", branch: "main")
]
```

并在对应 target 的 `dependencies` 中声明依赖：

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "SJFullscreenPopGesture", package: "SJFullscreenPopGesture")
    ]
)
```

---

## 快速开始

### 1. 启动时安装（必需，且仅需一次）

在 App 启动尽早处调用 `install()`。它是**幂等**的，且必须在任何 `pushViewController` 之前调用，否则该次 push 不会为前一个 VC 建立快照，手势对其失效。

UIKit `AppDelegate`：

```swift
import UIKit
import SJFullscreenPopGesture

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        SJFullscreenPopGesture.install()
        return true
    }
}
```

SwiftUI `App`：

```swift
import SwiftUI
import SJFullscreenPopGesture

@main
struct MyApp: App {
    init() {
        SJFullscreenPopGesture.install()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

调用 `install()` 之后，被 push 进任意 `UINavigationController` 的页面即自动获得全屏 / 边缘返回手势，无需额外配置。

### 2. 全局配置

通过 `SJFullscreenPopGesture` 的类属性进行全局配置（可在任意线程读写；修改后对**新创建的手势 / 新交互**生效）：

```swift
import SJFullscreenPopGesture

// 手势类型：.edgeLeft（默认，仅左边缘）/ .full（全屏拖动均可触发）
SJFullscreenPopGesture.gestureType = .full

// 过渡动画模式：.shifting（默认，仅前一个 VC 平移）/ .maskAndShifting（平移 + 遮罩淡出）
SJFullscreenPopGesture.transitionMode = .maskAndShifting

// 触发 pop 的拖动比例阈值，默认 0.35（拖动比例 > 该值时执行 pop）
SJFullscreenPopGesture.maxOffsetToTriggerPop = 0.5
```

### 3. 单个页面的精细化控制

库以 `@objc` 关联对象的形式扩展了 `UIViewController`，可在某个页面上单独配置：

```swift
import UIKit
import SJFullscreenPopGesture

final class DetailViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // 在此页面禁用全屏返回手势
        sj_disableFullscreenGesture = true

        // 返回界面的显示模式：.snapshot（默认，快照）/ .origin（原始视图）
        sj_displayMode = .origin

        // 盲区：在这些矩形区域内不触发手势（CGRect 装箱为 NSValue）
        sj_blindArea = [NSValue(cgRect: CGRect(x: 0, y: 0, width: 80, height: 200))]

        // 盲区视图：这些视图所在区域内不触发手势
        sj_blindAreaViews = [someSlider]

        // 拖动生命周期回调
        sj_viewWillBeginDragging = { vc in print("将开始拖动: \(vc)") }
        sj_viewDidDrag = { vc in print("拖动中: \(vc)") }
        sj_viewDidEndDragging = { vc in print("结束拖动: \(vc)") }
    }
}
```

### 4. 兼容 WKWebView 返回

将页面内的 `WKWebView` 设为「优先返回」对象：当其 `canGoBack` 为 `true` 时，全屏手势会让位给 WebView 自身的前进/后退手势（setter 同时会把该 WebView 的 `allowsBackForwardNavigationGestures` 置为 `true`）。

```swift
sj_considerWebView = webView
```

### 5. 读取手势状态

`UINavigationController` 暴露了只读的手势状态（需在主线程读取）：

```swift
@MainActor
func check(nav: UINavigationController) {
    let state: UIGestureRecognizer.State = nav.sj_fullscreenGestureState
    print(state)
}
```

---

## 公共 API 一览

### `SJFullscreenPopGesture`

| 成员 | 说明 |
| --- | --- |
| `static func install()` | 安装 swizzling，启动时调用一次（幂等，必需） |
| `class var gestureType: SJFullscreenPopGestureType` | 手势类型，默认 `.edgeLeft` |
| `class var transitionMode: SJFullscreenPopGestureTransitionMode` | 过渡动画模式，默认 `.shifting` |
| `class var maxOffsetToTriggerPop: CGFloat` | 触发 pop 的拖动比例阈值，默认 `0.35` |

### 枚举

```swift
enum SJFullscreenPopGestureType: UInt { case edgeLeft = 0, full = 1 }
enum SJFullscreenPopGestureTransitionMode: UInt { case shifting = 0, maskAndShifting = 1 }
enum SJPreViewDisplayMode: UInt { case snapshot = 0, origin = 1 }
```

### `UIViewController` 扩展

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `sj_displayMode` | `SJPreViewDisplayMode` | `.snapshot` | 返回界面显示模式（setter 会设置 `edgesForExtendedLayout = []`） |
| `sj_disableFullscreenGesture` | `Bool` | `false` | 在该页面禁用全屏手势 |
| `sj_blindArea` | `[NSValue]?` | `nil` | 手势盲区矩形（CGRect 装箱） |
| `sj_blindAreaViews` | `[UIView]?` | `nil` | 手势盲区视图 |
| `sj_viewWillBeginDragging` | `((UIViewController) -> Void)?` | `nil` | 拖动将开始回调 |
| `sj_viewDidDrag` | `((UIViewController) -> Void)?` | `nil` | 拖动中连续回调 |
| `sj_viewDidEndDragging` | `((UIViewController) -> Void)?` | `nil` | 拖动结束回调 |
| `sj_considerWebView` | `WKWebView?` | `nil` | 优先返回的 WebView（setter 会启用其 `allowsBackForwardNavigationGestures`） |

### `UINavigationController` 扩展

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `sj_fullscreenGestureState` | `UIGestureRecognizer.State`（只读，`@MainActor`） | 当前全屏手势的状态 |

---

## 从 ObjC / CocoaPods 版迁移

1. **接入方式改为 SPM。** 移除 Podfile 中的 `pod 'SJFullscreenPopGesture/ObjC'` 或 `pod 'SJFullscreenPopGesture/Swift'`，改用上文的 SPM 依赖。
2. **必须显式安装。** 原版靠 `+load` 自动 swizzle，本版需在 App 启动时调用一次 `SJFullscreenPopGesture.install()`（这是相对原版唯一的接入差异）。
3. **API 名称基本不变。** 公开类型 `SJFullscreenPopGesture`、各 `sj_` 前缀属性、各枚举原始值均与原 ObjC 版对齐，已迁移到 Swift 的调用代码改动很小；ObjC 消费方因 `@objc` 暴露也可继续按原选择器调用。
4. **线程契约保持。** 全局配置（`gestureType` / `transitionMode` / `maxOffsetToTriggerPop`）与各 `sj_` 配置属性仍可在任意线程读写；`sj_fullscreenGestureState` 与内部手势创建为主线程相关，请在主线程访问。

---

## License

SJFullscreenPopGesture 基于 **MIT License** 发布，沿用原仓库授权（Copyright (c) 2019 changsanjiang）。详见 [LICENSE](./LICENSE)。
