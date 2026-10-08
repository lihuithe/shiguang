# 拾光（ShiGuang）

像刷短视频一样随机回顾照片，看到废片顺手上滑删除。功能对标 iOS App「去留 - 照片整理与随机回顾」，**不需要登录，没有订阅，没有每日浏览上限**。

## 功能与交互（对照「去留」录屏重构）

**底部浮动 Tab：照片 / 视频 / 统计**

| 页面 | 交互 |
|---|---|
| 照片首页 | 三张扇形叠放的卡片，背景取照片主色；轻触「开始回顾」；左上角下拉切换分类（照片、截图、实况、动图、自拍），角标是本组剩余数量 |
| 照片浏览 | 顶部：返回、组内进度条、分享。中间圆角照片卡片：左右滑切换（下一张从后方浮现，上一张从左侧滑入）、上滑删除（照片缩小飞进动态岛并闪红光，立即从序列移除）、双击收藏、双指捏合「回到那天」、长图轻点全屏查看。底部：收藏、「时间 · 地点 ⓘ」、撤销；删除后提示「点击 ↶ 可以撤销」 |
| 首次引导 | 「上滑删除」「左右滑动切换照片」提示；看到第 3 张时弹出「回到那天」捏合教学 |
| 一组结束 | 滑过最后一张（或中途返回且有待删除项）弹出「有待删除的照片」：默认全选，可点选保留；「放弃，回到首页」或「确认删除」→ 系统确认 → 回首页换一组 |
| 视频 | 短视频式上下滑；右侧收藏、分享、删除、撤销；左下角时间与地点（点击看详情）；首次播放询问「视频会自动播放声音，要继续吗？」；长按 2 倍速；待删除数量显示在右上角，看完一组统一确认 |
| 统计 | 照片 / 截屏 / 视频各自的查看、删除、清理；腾出空间与各类占比；重置浏览记录；右上角齿轮进入设置 |
| 详细信息 | 拍摄时间、距今、地点（反查中文地名）、类型、尺寸、大小、文件名、回到那天 |
| 回到那天 | 当天所有照片 / 视频 / 截图，可筛选、全屏翻看、批量删除 |

其他：每组 5–100 张、看过 3 年内不重复、HDR（低亮度自动关闭）、实况自动播放与静音（卡片左上角「实况 ⌄」可切换）、iCloud 同步浏览记录、每日提醒、演示模式。**不需要登录，没有订阅和浏览上限。**

## 目录结构

```
shiguang-ios/
├── project.yml                  # XcodeGen 工程描述
├── App/                         # iOS App（SwiftUI + PhotoKit）
│   ├── ShiGuangApp.swift        # 入口、RootView、权限引导页
│   ├── AppModel.swift           # 全局状态：设置、浏览记录、统计、同步
│   ├── Components/              # 浮动 Tab、按钮、动态岛红光、进度条等
│   ├── Photos/                  # 照片首页（扇形卡片）、照片浏览页
│   ├── Videos/                  # 视频信息流
│   ├── Review/                  # 照片 / 视频共用的浏览状态机、待删除清单、详情、教学弹窗
│   ├── Day/                     # 回到那天
│   ├── Media/                   # 照片 / HDR / 实况 / 视频 / 动图 / 长图 / 演示卡片
│   ├── Stats/  Settings/
│   ├── Services/                # PhotoKit、媒体加载、持久化、iCloud 同步、触感、通知
│   └── Resources/Assets.xcassets
├── Packages/ShiGuangCore/       # 纯 Swift 核心逻辑 + 单元测试（不依赖 UIKit）
└── scripts/lint_brackets.py     # 无编译器环境下的括号配对检查
```

核心逻辑都在 `ShiGuangCore`：随机抽组（`GroupPicker`）、组内状态、删除即移出序列与撤销（`GroupSession`）、浏览记录与 iCloud 合并（`ViewHistory`）、手势判定（`SwipeClassifier`）、统计（`UsageStats`）、设置（`AppSettings`）、日期与容量格式化。

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

也可以在 Xcode 中对 `ShiGuang` scheme 执行 Test（⌘U）。单元测试覆盖随机抽组不重复、浏览记录窗口与多设备合并、删除即移出序列 / 撤销放回原位 / 外部删除后保持进度、轴向锁定与翻页 / 上滑删除判定、按类别统计与腾出空间占比、设置的解码兼容、日期与容量格式化。

## 已知限制

- 「照片」分类用 PhotoKit 谓词排除截图，但 GIF 仍可能出现在「照片」里（PhotoKit 无法按播放样式筛选）。
- 释放空间通过 `PHAssetResource` 的 `fileSize` 估算，结果是近似值。
- iCloud 键值存储单值上限 1 MB，浏览记录过多时只同步最近的部分。
