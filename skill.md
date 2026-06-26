# emexDE TrollStore 改造接手说明

## 项目路径与方向

- 当前仓库路径：`/var/mobile/Containers/Shared/AppGroup/.jbroot-8AC8F433F9E3920D/var/mobile/SuSu/emexDE`
- 本地 TrollStore 源码路径：`/var/mobile/Containers/Shared/AppGroup/.jbroot-8AC8F433F9E3920D/var/mobile/SuSu/TrollStore`
- 后续优先参考本地 TrollStore 源码，不优先看远端 raw。
- 改造方向：以 jailed/IPA 版本为基础，把 emexDE 从开发者证书签名/内部安装模型迁移到 TrollStore 权限模型。
- 允许删除或禁用与当前方向冲突的旧 jailbreak/rootless/rootful/roothide/tshelper/开发者证书残留逻辑，但要分批小改、验证、提交。

## 用户约束

- 不要重复解释同一个目标；工具操作前后只给简短说明。
- 每次改动尽量小，分批完成。
- 修改后尽量验证。
- 项目改动验证通过后自动提交并推送到 GitHub。
- 不要 force push，不要清理 `.backups/`，除非用户明确要求。

## 总体目标

emexDE 自身：

1. 最终打包出的 `Payload/emexDE.app` 必须在 zip/ipa 前用 ldid 重新签名。
2. 签名 entitlements 使用项目内 `supports/emexDE.entitlements.plist`。
3. 该文件来源于：
   - `/var/mobile/Containers/Shared/AppGroup/.jbroot-8AC8F433F9E3920D/var/mobile/sign/entitlements.plist`
4. 只把 `application-identifier` 从源文件的 `com.susu.pictapro` 改为 `com.cr4zy.nyxian`，其余 key 不增删。
5. 这样 TrollStore 导入 emexDE 时应能识别最终 app 签名里的敏感权限并出现黄/红提示。

emexDE 内运行用户项目：

1. Run 项目时不再请求开发者证书。
2. 项目编译成 `.app` 后，使用项目自己的 `Config/Entitlements.plist` 或 `Config/entitlements.plist`。
3. 通过 `ldid -S<项目目录>/Config/Entitlements.plist <主可执行文件>` 签名。
4. 后续要安装到系统桌面并打开，不再只安装到 `LDEApplicationWorkspace` 内部环境。

## 已完成提交

### 1. `a17527e7 Add TrollStore ldid signing support`

完成第一批 TrollStore ldid 签名基础：

- `Makefile`
  - `compile` 不再依赖旧 `Nyxian/LindChain/JBSupport/tshelper`。
- `Info.plist`
  - 删除 `TSRootBinaries` / `tshelper` 声明。
- `Nyxian/LindChain/Project/NXProject.m`
  - 新项目默认 `Config/Entitlements.plist` 改为只包含：
    - `platform-application = true`
- 新增：
  - `Nyxian/LindChain/TrollStoreSupport/NXTrollStoreSupport.h`
  - `Nyxian/LindChain/TrollStoreSupport/NXTrollStoreSupport.m`
- `NXTrollStoreSupport` 当前能力：
  - 查找项目 entitlements：
    - `Config/Entitlements.plist`
    - `Config/entitlements.plist`
  - 下载 ldid：
    - `https://github.com/opa334/ldid/releases/latest/download/ldid`
  - 下载后 `chmod 0755`
  - 使用 `posix_spawn` 执行：
    - `ldid -S<entitlements.plist> <executable>`
- `Nyxian/bridge.h`
  - 导入 `NXTrollStoreSupport.h`。
- `Nyxian/LindChain/Core/Builder.swift`
  - jailed app Run 分支不再检查/请求开发者证书。
  - 不再调用 `LCUtils.signAppBundle(withZSign:)`。
  - 改为读取项目 Config entitlements 并用 ldid 签项目主可执行文件。

### 2. `097acec1 Fix TrollStore support Swift bridge calls`

修复 Swift 调 ObjC `NSError **` 方法的桥接错误：

- `NXTrollStoreSupport` 的 ObjC 方法在 Swift 中桥接为 `throws`。
- `Builder.swift` 已改为 `do/try/catch`，不再传 `error: &nsError`。

关键代码方向：

```swift
do {
    let entitlementsPath = try NXTrollStoreSupport.projectEntitlementsPath(forProjectPath: self.project.url.path)
    try NXTrollStoreSupport.signExecutable(atPath: self.project.machoURL.path, entitlementsPath: entitlementsPath)
} catch {
    throw NSError(domain: "com.cr4zy.nyxian.builder.install", code: 1, userInfo: [NSLocalizedDescriptionKey:error.localizedDescription])
}
```

### 3. `66b5614b Use TrollStore entitlements for app signing`

曾把 emexDE 自身 Xcode/codesign entitlements 改成 TrollStore 模板：

- `Nyxian/Nyxian.entitlements`
- `ent/nyxianforjb.xml`

这两份当前不是最终关键点。后面发现 TrollStore 导入 emexDE 无权限提示，说明只改这些不够；关键要对最终 `Payload/emexDE.app` 执行 ldid 重签。

注意：后续不要再把 `/var/mobile/sign/entitlements.plist` 直接覆盖到这两份文件，除非用户明确要求。

### 4. `7df5056e Sign packaged app with ldid entitlements`

完成 TrollSpeed 风格的最终 app 重签：

- 新增：
  - `supports/emexDE.entitlements.plist`
- 文件来源：
  - `/var/mobile/Containers/Shared/AppGroup/.jbroot-8AC8F433F9E3920D/var/mobile/sign/entitlements.plist`
- 只修改：
  - `application-identifier: com.susu.pictapro -> com.cr4zy.nyxian`
- 保持源文件 key 顺序和 key 集合不变。
- `Makefile check` 增加 `ldid` 依赖。
- `Makefile package-app` 在 zip 前执行：

```make
@if [ -d Payload/emexDE.app ]; then \
	ldid -Ssupports/emexDE.entitlements.plist Payload/emexDE.app; \
elif [ -d Payload/emexDEForJB.app ]; then \
	ldid -Ssupports/emexDE.entitlements.plist Payload/emexDEForJB.app; \
else \
	echo "No emexDE app bundle found in Payload"; exit 1; \
fi
```

验证过：

- `plistlib` 对比 `supports/emexDE.entitlements.plist` 和 `/var/mobile/sign/entitlements.plist`：
  - key 顺序一致。
  - 仅 `application-identifier` 不同。
- `git diff --check` 通过。
- 已推送到 `origin/main`。

## 当前重要文件

### `Makefile`

关键 target：

- `jailed`
  - `SCHEME := Nyxian`
  - `FILE := emexDE.ipa`
  - 执行：`clean check compile package-app clean`
- `trollstore`
  - `SCHEME := NyxianForJB`
  - `FILE := emexDE.tipa`
  - 执行：`clean check compile pseudo-sign package-app clean`
- `package-app`
  - 复制 archive 产物到 `Payload`
  - 使用 `ldid -Ssupports/emexDE.entitlements.plist` 重签 `Payload/emexDE.app` 或 `Payload/emexDEForJB.app`
  - zip 成最终 ipa/tipa

### `supports/emexDE.entitlements.plist`

只用于 emexDE 自身最终包重签。不要用于 emexDE 内用户项目模板。

### `Nyxian/LindChain/TrollStoreSupport/`

当前放 ldid 下载、查找项目 entitlements、执行 ldid 签名相关逻辑。

后续桌面安装逻辑建议也放这里，继续避免复用旧 `JBSupport/Shell.m`。

### `Nyxian/LindChain/Core/Builder.swift`

当前 jailed app Run 已接入项目 entitlements + ldid 签项目主可执行文件。后续还需要把安装和打开逻辑改成 TrollStore/system desktop 方向。

### `Nyxian/LindChain/Project/NXProject.m`

新项目默认 `Config/Entitlements.plist` 已改为 `platform-application = true`。

这里仍有旧 `NXEntitlementsConfig`、`NXSignMachOWithNyxianEntitlements`、`com.nyxian.pe.*` 相关残留，后续要清理。

## TrollSpeed 参考结论

本地路径：

- `/var/mobile/Containers/Shared/AppGroup/.jbroot-8AC8F433F9E3920D/var/mobile/SuSu/TrollSpeed`

关键文件：

- `supports/entitlements.plist`
- `build.sh`

TrollSpeed 打包流程关键点：

```sh
cp supports/entitlements.plist TrollSpeed.xcarchive/Products
cd TrollSpeed.xcarchive/Products/Applications || exit
codesign --remove-signature TrollSpeed.app
cd - || exit
cd TrollSpeed.xcarchive/Products || exit
mv Applications Payload
ldid -Sentitlements.plist Payload/TrollSpeed.app
zip -qr TrollSpeed.tipa Payload
```

对 emexDE 的对应实现：

- 不需要照搬全部脚本。
- 已在 `Makefile package-app` 中直接对最终 `Payload/emexDE.app` 执行 ldid 重签。

## 已知当前状态

- `origin/main` 已包含上述 4 个提交。
- 当前工作区正常情况下只剩未跟踪 `.backups/`。
- `.backups/` 不要提交，也不要删除，除非用户明确要求。
- 本地设备环境可能没有完整 macOS/Xcode 构建能力，完整构建主要依赖 GitHub Actions。
- `.github/workflows/build.yml` 已安装 `ldid`：
  - `brew install ldid dpkg libarchive`

## 后续未完成内容

### 第六步：统一 emexDE 内用户项目的 entitlements 使用规则

当前部分完成：

- 新项目默认 `Config/Entitlements.plist` 已是 `platform-application = true`。
- `Builder.swift` Run app 分支已从项目 Config 读取 entitlements 并 ldid 签主可执行文件。

待完成：

1. 清理或禁用旧 `NXEntitlementsConfig` 对 app 签名链路的影响。
2. 检查并处理旧配置：
   - `NXSignMachOWithNyxianEntitlements`
   - `com.nyxian.pe.*`
   - `PEEntitlement`
3. 检查项目设置 UI：
   - 不要再让用户以为需要旧 PE 权限或开发者证书。
   - 可改成编辑/展示项目 `Config/Entitlements.plist`。
4. 非 RunningApp / package 分支若还使用：
   - `macho_after_sign(self.project.machoURL.path, self.project.entitlementsConfig.entitlement)`
   - 应改为统一用项目 Config entitlements + ldid，或确认该分支保留理由。

建议先搜索：

```sh
grep -R "NXEntitlementsConfig\|NXSignMachOWithNyxianEntitlements\|com.nyxian.pe\|macho_after_sign\|certificateData\|signAppBundle" -n Nyxian
```

### 第七步：把 Run 产物安装到系统桌面

目标：

- 用户在 emexDE 内 Run 一个 app 项目后，编译出的 `.app` 应安装到系统桌面并自动打开。
- 不再使用内部 `LDEApplicationWorkspace` 虚拟安装作为最终目标。
- 不再依赖 `PEProcessManager` 启动桌面 app。

当前未完成：

- `Builder.swift` 里 app 安装/启动仍需要继续替换。
- 需要参考本地 TrollStore 的 custom install 逻辑。

建议参考 TrollStore 源码中这些关键词：

```sh
grep -R "custom install\|installIpa\|registerApplication\|LSApplicationWorkspace\|MobileContainerManager\|uicache\|MCM" -n /var/mobile/Containers/Shared/AppGroup/.jbroot-8AC8F433F9E3920D/var/mobile/SuSu/TrollStore
```

推荐实现位置：

- `Nyxian/LindChain/TrollStoreSupport/NXTrollStoreSupport.h`
- `Nyxian/LindChain/TrollStoreSupport/NXTrollStoreSupport.m`

建议新增能力：

```objc
+ (BOOL)installAppBundleAtPath:(NSString *)bundlePath error:(NSError **)error;
+ (BOOL)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier error:(NSError **)error;
```

Swift 调用仍按 `throws` bridge 使用 `try`。

安装流程建议：

1. 确认 `.app` 存在。
2. 读取 `.app/Info.plist`。
3. 获取：
   - `CFBundleIdentifier`
   - `CFBundleExecutable`
4. 确认主可执行文件已经 ldid 签名。
5. 复制到系统应用目录或按 TrollStore custom install 的目录策略处理。
6. 注册应用，让图标出现在桌面。
7. 自动打开 bundle id。
8. 重复安装同 bundle id 时应覆盖/更新，不产生重复图标。

### 第八步：清理开发者证书和旧 JB 残留

待处理范围：

1. Settings 里的证书管理入口。
2. IPA 导入流程里旧的开发者证书检查和 zsign 逻辑。
3. `LCUtils.certificateData` 相关 UI/提示。
4. 旧 `JBSupport`、`tshelper`、`rootless/rootful/roothide` 默认构建链路残留。

注意：

- 先隐藏或禁用 UI，再考虑删除源码。
- 不要一次性大删。

### 第九步：最终验证

需要通过 GitHub Actions 或 macOS/Xcode 环境验证：

1. `make jailed` 能产出 `emexDE.ipa`。
2. `package-app` 中 ldid 确实执行在最终 `Payload/emexDE.app` 上。
3. TrollStore 导入 emexDE 时出现预期权限提示。
4. emexDE 安装后能启动。
5. 新建 app 项目生成 `Config/Entitlements.plist`。
6. Run 项目时：
   - 编译成功。
   - 主可执行文件用项目 Config entitlements ldid 签名成功。
   - 后续实现后能安装到桌面并打开。
7. 重复安装同 bundle id 不产生重复图标。
8. 错误提示清楚：
   - 缺少 entitlements。
   - ldid 下载失败。
   - ldid 执行失败。
   - 桌面安装失败。
   - 注册/打开失败。

## 推荐下一步执行顺序

1. 检查 GitHub Actions 最新构建，确认 `ldid -Ssupports/emexDE.entitlements.plist Payload/emexDE.app` 生效。
2. 如果 TrollStore 导入仍无权限提示，先解包产物检查最终 app 签名 entitlements，而不是继续改模板文件。
3. 做第六步：清理用户项目签名链路中的旧 PE entitlement / 证书残留。
4. 做第七步：移植 TrollStore custom install，Run 产物安装到桌面并打开。
5. 做第八步：隐藏或删除旧证书 UI 和无用 JB 残留。
6. 完整验证后再做最终清理。

