# Asspp SAP 登录修复

本仓库保存 Asspp 的 SAP 认证修复源码，包括本地 ApplePackage、iOS WebKit/WASM 签名运行时、macOS 签名桥接和构建校验脚本。

## 当前验证状态

截至 2026-10-17：

- 已在 Xcode 27.1 上完成 iOS Release 构建，版本 4.2.0、arm64、最低 iOS 17.0。
- 已校验 IPA 完整性，以及内置五个 SAP 运行时文件与源码/固定哈希的一致性。
- 已在 iPhone 18 Pro Max / iOS 27.0.1 上签名、安装和启动测试版，启动后进程正常运行。
- **用户已于 2026-10-17 反馈：已在上述真机上验证本次修复版，可以正常使用。**

此前导出包还记录了 GitHub macOS CI 中的无账号 SAP 握手、连续签名和 iOS 构建通过情况。这些历史记录见 [LOCAL-CHANGES.txt](Packages/ApplePackage/LOCAL-CHANGES.txt)，应与本次本机构建区分。

## 修复内容

- 工作区改用本地 `Packages/ApplePackage`，确保构建包含修复实现。
- iOS 使用内置 WebKit/WASM SAP 引擎；认证请求在设备本机签名。
- macOS 使用 CommerceKit 签名桥接。
- 对实际发送的最终 XML 字节签名，覆盖重试、重定向与账号 token 刷新。
- 限制登录重定向目标，规范认证地址和验证码输入，并对日志中的签名、Cookie 与 token 脱敏。
- 构建脚本保留本地修复，校验并打包固定版本的签名运行时。

SAP WASM 是固定来源的上游预编译资源，准备脚本检查 SHA-256；本仓库未提供从原始 Go 源码复现该 WASM 的流程。详见 [修复说明](Packages/ApplePackage/LOCAL-CHANGES.txt) 和 [准备脚本](Resources/Scripts/prepare.sap.runtime.py)。

`sap.wasm`、`unicorn_x86.js` 和 `wasm_exec.js` 沿用本地包的忽略规则，不纳入 Git；构建前由上述准备脚本按固定提交和哈希获取，并随 IPA 内置。

## 本机构建未签名 IPA

需要完整 Xcode、Python 3 和 `xcbeautify`。使用 `Asspp.xcworkspace`。

```sh
brew install xcbeautify
python3 Resources/Scripts/prepare.sap.runtime.py --public-certificates
zsh Resources/Scripts/compile.release.mobile.ci.sh "$PWD" "$PWD/Asspp-SAP.ipa"
python3 Resources/Scripts/verify.sap.ipa.py "$PWD/Asspp-SAP.ipa"
```

`--public-certificates` 仅恢复上游公开分发的 localhost OTA 测试证书，按固定哈希校验。这些资源不属于用户的 Apple 开发者签名材料，并已被 Git 忽略。

输出 IPA 未签名，需用自己的开发者证书与适用的 provisioning profile 签名后安装。仓库中应用的原始 bundle ID 为 `wiki.qaq.Asspp`；本次设备验收使用单独签名的 `wiki.qaq.Asspp.SAPTest`，显示名称为 `Asspp SAP`。该显示名称和 bundle ID 的调整仅应用于本地测试产物。

## GitHub Actions

只启用手动触发的 [SAP iOS IPA](.github/workflows/sap-ipa.yml) 工作流。它执行无账号 WebKit SAP 测试、iOS 构建和 IPA 校验，并上传未签名构建产物。

上游通用构建、发布和定时签名工作流保留在 [参考目录](Resources/Document/UpstreamWorkflows)，不会作为本仓库的活动工作流执行。此次源码发布不触发云端构建或安装包发布。

## 源码来源与内容边界

- Asspp 上游：<https://github.com/Lakr233/Asspp>
- 导出包记录的 Asspp 基准提交：`caed708182c61897bd539557a10618f9b0eba066`。
- 本地 ApplePackage 基于 1.2.7：`28710fec47fa89dfdedf2bf47cc284a2334ddfdc`。
- 本仓库是 `Lakr233/Asspp` 的公开 fork，保留完整上游 Git 历史；SAP 修复以基于上述基准提交的后续提交提供。
- 不包含用户证书、私钥、证书密码、Apple 账号凭据、设备描述文件、会话导出、构建缓存或已签名 IPA。

保留原项目及所包含依赖的许可证与版权信息；参见 [LICENSE](LICENSE)、[ApplePackage LICENSE](Packages/ApplePackage/LICENSE) 和 [ipatool LICENSE](Packages/ApplePackage/LICENSE.ipatool)。
