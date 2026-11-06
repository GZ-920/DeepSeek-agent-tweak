# DSAAgent — 给 DeepSeek iOS 加「智能体」

> 不改 App 二进制，用 Tweak 运行时注入（LiveContainer 里可直接加载）。

## 功能

| 位置 | 行为 |
|---|---|
| 侧栏会话列表**顶部** | 新增一行「🤖 智能体」 |
| 点进去 | 上半区「智能体对话」（每个智能体 × 对话数），下半区「我的智能体」＋末行「新建智能体」 |
| 新建智能体 | 名字 / 图标 / **设定提示词** / 开场白；保存后可选「保存并开始对话」 |
| 用智能体开新会话 | 新会话出现时，自动把设定提示词作为**第一条消息**发送（发不出去就填进输入框并提示按发送） |
| 防重复 | 每个 sessionId 只注入一次；会话↔智能体绑定持久化 |

数据存于 App 沙盒 `Library/Application Support/DSAgent/{agents,sessions}.json`，与 App 自身数据隔离。

## 编译（Mac / GitHub Actions）

```bash
git clone --recursive --depth 1 https://github.com/theos/theos.git ~/theos
export THEOS=~/theos
make package FINALPACKAGE=1
# 产物：packages/com.minis.dsagent_0.1.0_iphoneos-arm64.deb
#       以及 .theos/obj/arm64/DSAAgent.dylib
```

仓库里已带 `.github/workflows/build.yml`：push 到 GitHub 后在 Actions 里下载 artifact 即可（无需本地 Mac）。

## 安装到 LiveContainer

1. 在 LiveContainer 里给 DeepSeek 打开 **JIT / dylib 注入**。
2. 把 `DSAAgent.dylib` 加入该 App 的注入列表（LiveContainer 支持「额外 dylib」）。
3. 启动 DeepSeek → 侧栏会话列表顶部出现「🤖 智能体」。

> 首次给 App 注入 dylib 后如果 App 起不来，先移除 dylib 确认是插件问题，再看 Console 里 `[DSAgent]` 日志。

## 调试 / 适配新版 App

注入点只有两处，都集中在 `src/Tweak.xm`：

1. `sessionListTable` —— 侧栏会话列表的 Swift 属性名（`xcrun strings` 在二进制里能看到）。
2. `sessionId` —— 会话页读取当前会话 id 的属性名候选（`sessionId` / `sessionID` / `chatSessionId` / `currentSessionId`）。

App 升级后若入口不出现：用 `frida-trace -U -m "-[UIViewController viewDidLayoutSubviews]"` 或 Console.app
观察 `[DSAgent]` 日志，把新属性名加到 `Tweak.xm` 的候选列表即可，其余代码不需要改。

## 已知限制

- 设定提示词以**用户消息**形式发出（DeepSeek 官方接口没有独立 system 字段），会出现在会话历史里。
- 「新建对话」按钮的自动点击未硬编码：点「新建对话」后由会话页出现事件接管注入；
  如果 App 版本把新会话创建改成不经过 `MessageViewController`，需要补 hook（见上）。
- 若 App 对输入框做了富文本/富输入校验，注入失败时会退回「填好等你按发送」，不会丢内容。
