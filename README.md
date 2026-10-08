# 拾光（ShiGuang）

像刷短视频一样随机回顾照片，看到废片顺手上滑删除。功能对标 iOS App「去留 - 照片整理与随机回顾」，**不需要登录，没有订阅，没有每日浏览上限**。

## 功能

| 功能 | 说明 |
|---|---|
| 随机盲盒 | 每次随机抽一组（默认 15 张，可设 5–100），看过的内容 3 年内不重复；全部看完后用最早看过的补齐并提示重置 |
| 手势 | 上滑标记删除、下滑收藏并下一张、左滑下一张、右滑上一张、双击收藏、撤销 |
| 批量确认删除 | 一组看完进入结算页，可点击切换删除标记、长按回看；删除走系统确认，进入「最近删除」可 30 天内恢复 |
| 分类 | 全部（照片视频混合）、照片、视频、截图、动图、实况、自拍 |
| 回到那天 | 双指捏合（或点日期 / 日历按钮）查看当天所有照片、视频、截图，可筛选、全屏翻看、批量删除 |
| 媒体播放 | HDR 照片与视频（低亮度自动关闭）、实况照片自动播放 / 静音、视频循环播放、长按 2 倍速、加载与播放进度条、GIF 动图、长图浏览 |
| iCloud 照片 | 允许从 iCloud 下载原图，并显示下载进度；离线时先显示本地低清图 |
| 收藏 | 同步到系统相册「个人收藏」 |
| 统计 | 已浏览、已删除、释放空间、收藏、完成组数、连续天数，近 7/14/30 天图表（只显示做了多少，不显示还剩多少） |
| 同步与提醒 | iCloud 键值存储同步浏览记录；每日回顾提醒 |
| 演示模式 | 用生成的示范卡片代替真实照片，方便录屏演示 |
| 其他 | 删除动画、震动反馈开关、日期格式（完整 / 数字 / 相对）、重置浏览记录、部分照片权限管理 |

## 目录结构

```
shiguang-ios/
├── project.yml                  # XcodeGen 工程描述
├── App/                         # iOS App（SwiftUI + PhotoKit）
│   ├── ShiGuangApp.swift        # 入口、RootView、权限引导页
│   ├── AppModel.swift           # 全局状态：设置、浏览记录、统计、同步
│   ├── Browser/                 # 首页随机浏览、结算页
│   ├── Day/                     # 回到那天
│   ├── Media/                   # 照片 / HDR / 实况 / 视频 / 动图 / 长图 / 演示卡片
│   ├── Stats/  Settings/
│   ├── Services/                # PhotoKit、媒体加载、持久化、iCloud 同步、触感、通知
│   └── Resources/Assets.xcassets
├── Packages/ShiGuangCore/       # 纯 Swift 核心逻辑 + 单元测试（不依赖 UIKit）
└── scripts/lint_brackets.py     # 无编译器环境下的括号配对检查
```

核心逻辑都在 `ShiGuangCore`：随机抽组（`GroupPicker`）、组内状态与撤销（`GroupSession`）、浏览记录与 iCloud 合并（`ViewHistory`）、手势判定（`SwipeClassifier`）、统计（`UsageStats`）、设置（`AppSettings`）、日期与容量格式化。

## 构建（需要 macOS + Xcode 16 或更新版本）

```bash
brew install xcodegen
cd shiguang-ios
xcodegen generate
open ShiGuang.xcodeproj
```

- 最低系统：iOS / iPadOS 17。
- 在 Xcode 的 Signing & Capabilities 中选择你的开发团队，并把 `PRODUCT_BUNDLE_IDENTIFIER`（`project.yml` 中为 `com.example.shiguang`）改成你自己的。
- iCloud 同步使用 `com.apple.developer.ubiquity-kvstore-identifier` 权限。**免费开发者账号不支持 iCloud**，签名会失败；这时可删除 `project.yml` 中的 `entitlements` 段落后重新生成工程，App 仍可正常使用，只是同步不生效。

## 测试

```bash
cd shiguang-ios/Packages/ShiGuangCore
swift test
```

也可以在 Xcode 中对 `ShiGuang` scheme 执行 Test（⌘U）。单元测试覆盖随机抽组不重复、浏览记录窗口与多设备合并、组内滑动 / 撤销 / 结算、手势判定、统计与连续天数、设置的解码兼容、日期与容量格式化。

## 已知限制

- 「照片」分类用 PhotoKit 谓词排除截图，但 GIF 仍可能出现在「照片」里（PhotoKit 无法按播放样式筛选）。
- 释放空间通过 `PHAssetResource` 的 `fileSize` 估算，结果是近似值。
- iCloud 键值存储单值上限 1 MB，浏览记录过多时只同步最近的部分。
