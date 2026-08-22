# Pagugu

Pagugu 是一个面向 Codex 与 Claude Code 的本地 macOS Agent Skill 管理与安全同步应用。

当前仓库只包含可运行的技术基线：SwiftUI 主窗口、状态栏入口、构建脚本和工程治理文档。Skill 扫描、状态检查、每日检查与 Git 更新尚未实现。

计划中的内容真相由 Git 源仓库拥有，Agent 安装目录只作为投影。Pagugu 只会自动更新干净且可 fast-forward 的已识别源仓库。

## 产品与架构

- [产品愿景](docs/product/vision.md)：产品动机、目标用户、目标体验与品牌方向。
- [统一语言](CONTEXT.md)：项目使用的 canonical term。
- [当前系统地图](docs/architecture/current-system-map.md)：当前实现、系统边界与产品不变量。

## 本地运行

要求 macOS 14+、Xcode 26 或兼容的 Swift 6 工具链。

```bash
./script/build_and_run.sh --verify
```

## 验证

```bash
xcodebuild test \
  -project Pagugu.xcodeproj \
  -scheme Pagugu \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

## License

MIT

## 远程状态

公开仓库 `Dimon94/pagugu` 已创建并用于 Issues。本地 Git 已初始化，但尚未配置 remote 或推送代码。
