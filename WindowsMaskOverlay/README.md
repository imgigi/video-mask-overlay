# WindowsMaskOverlay

Windows 版本遮罩工具骨架，使用 .NET 8 WinForms + Win32 API。

## 功能范围

- 托盘图标和右键菜单
- 启用/关闭遮罩
- 目标窗口选择和跟随
- 普通、置顶、强力置顶
- 点击穿透
- 白色/黑色/Hex 颜色
- 透明度滑杆和输入框
- 图片遮罩：图片默认按目标窗口高度等比例缩放、左对齐；与目标窗口重叠区域按透明度显示，超出区域保持不透明

## 本地运行

需要 Windows 和 .NET 8 SDK。

```powershell
cd WindowsMaskOverlay
dotnet run
```

## 给普通用户使用

下载 `WindowsMaskOverlay-win-x64.zip`，解压后双击 `WindowsMaskOverlay.exe` 即可运行。应用会出现在系统托盘里。

第一次运行如果 Windows SmartScreen 提示未知发布者，点击“更多信息”后选择“仍要运行”。正式发布建议做代码签名来消除这个提示。

## 本地打包

单文件自包含发布：

```powershell
.\scripts\publish-windows.ps1
```

输出目录：

```text
dist\WindowsMaskOverlay-win-x64.zip
```

## GitHub 上线流程

仓库已经包含 GitHub Actions：

```text
.github/workflows/release-windows.yml
```

上线方式有两种：

1. 在 GitHub 页面手动运行 `Release Windows` workflow。
   - 产物会出现在 workflow 的 Artifacts 里。
   - 下载 `WindowsMaskOverlay-win-x64.zip` 后发给用户即可。

2. 打 tag 自动创建 Release。

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会自动构建并创建 Release，附件里会有 `WindowsMaskOverlay-win-x64.zip`。

## 正式产品化建议

1. 先做 MVP
   - Windows 10/11 测试目标窗口跟随、点击穿透、置顶、图片遮罩。
   - 先支持单显示器和常见 DPI，再扩展多显示器边界场景。

2. 安装包
   - 早期可以用单文件 `.exe` 分发。
   - 正式给普通用户建议做安装包，例如 MSIX 或 WiX Toolset MSI。

3. 代码签名
   - 正式发布前购买代码签名证书，给 `.exe` 和安装包签名。
   - 不签名会触发 SmartScreen，新用户下载体验会很差。

4. 自动更新
   - 简单方案：应用启动时检查 GitHub Releases 或自有接口版本号。
   - 成熟方案：安装器/更新器接管，例如 Velopack、Squirrel 或 MSIX App Installer。

5. 隐私说明
   - 工具会枚举窗口标题，并在图片遮罩/颜色遮罩上覆盖窗口。
   - 如果后续加入截图、灰度、识别等能力，要明确说明是否采集屏幕内容。

6. 兼容性风险
   - 游戏、播放器、硬件加速窗口、管理员权限窗口可能有不同层级和捕获限制。
   - 如果目标窗口是管理员权限运行，普通权限遮罩可能无法稳定盖住，需提示用户同权限运行。

7. 商业发布节奏
   - Alpha：免费发给少量用户收集问题。
   - Beta：加入日志、崩溃收集、版本更新。
   - 正式版：签名安装包、隐私政策、官网/下载页、反馈入口。
