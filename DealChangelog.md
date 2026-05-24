# Sparkle Changelog 处理总结

整个 release notes 是在 GitHub Actions 里生成一次，同时喂给两个出口：**GitHub Release 页面**（Markdown）和 **Sparkle 的 appcast.xml**（HTML 内联）。

## 三个核心文件

| 文件 | 角色 |
|---|---|
| `.github/release.yml` | PR 分类配置（按 label 映射到 Features / Bug Fixes / Docs / Other） |
| `.github/workflows/release.yml` (step "Generate release notes") | 生成 Markdown + HTML 两份 notes |
| `scripts/package_release.sh` | 把 HTML 内联到 appcast.xml |

## 生成 notes 的逻辑（workflow 里）

1. **PR 优先路径**：调用 `gh api /repos/{repo}/releases/generate-notes`，GitHub 会读 `.github/release.yml`，把上一个 tag 到当前 tag 之间合并的 PR 按 label 分组成 Markdown，落到 `release_notes.md`。

2. **直接 commit 兜底**：如果区间内没有 PR，API 返回的 body 只含一个 "Full Changelog" 链接（不含 `## What...` 标题）。脚本用 `grep -qF '## What'` 检测这种情况，然后：
   - `git fetch --tags --unshallow` 把历史拉全（actions/checkout 默认浅克隆）
   - `git describe --tags --abbrev=0 "$TAG^"` 找上一个 tag
   - `git log --no-merges --pretty=format:"- %s ([\`%h\`](...commit/%H))" PREV..TAG` 生成 commit 列表
   - 在 `release_notes.md` 最前面塞一个 `## Changes` 段落

3. **Markdown → HTML**：再调一次 `gh api -X POST /markdown -F text=@notes.md -f mode=gfm -f context=<repo>`，让 GitHub 用 GFM 渲染（自动把 `#123` 变成 PR 链接、`@user` 变成用户链接），HTML 落到 `release_notes.html`。

4. 用 step output 把两个路径暴露给后续 step：`notes_md` 给 `gh release create --notes-file`，`notes_html` 通过 `SPARKLE_RELEASE_NOTES_FILE` env 喂给打包脚本。

## Sparkle 端的处理（`package_release.sh`）

读 `SPARKLE_RELEASE_NOTES_FILE` 的 HTML，**内联**进 appcast 的 `<description><![CDATA[...]]>`，而不是只放一个 `<sparkle:releaseNotesLink>` URL：

```xml
<item>
  <title>Version 1.2.3</title>
  <sparkle:version>1.2.3</sparkle:version>
  <description><![CDATA[ <h2>What's Changed</h2>...渲染好的 HTML... ]]></description>
  <sparkle:fullReleaseNotesLink>https://github.com/.../releases/tag/v1.2.3</sparkle:fullReleaseNotesLink>
  <pubDate>...</pubDate>
  <enclosure url="...zip" sparkle:edSignature="..." length="..." />
</item>
```

为什么内联：之前用 `<sparkle:releaseNotesLink>` 指向 GitHub Release 页面，Sparkle 在更新弹窗里嵌一个 WebView 去加载，会带上 GitHub 的整套登录/header/JS，又慢又丑还可能空白。直接内联 GFM 渲染后的 HTML 片段，弹窗里立即显示干净的 release notes；`<sparkle:fullReleaseNotesLink>`（注意 `full` 前缀）保留指向 GitHub 的链接，作为 "完整说明" 的兜底入口，不会被 Sparkle 自动加载。

## 复用到新项目时需要带过去的

- 复制 `.github/release.yml`（PR 分类）和 workflow 的 **Generate release notes** 这一个 step（PR/commit fallback + markdown→HTML）。
- 给 PR 打 label 才会被分类，否则全落到 "Other Changes"。
- 在打包脚本里读 `SPARKLE_RELEASE_NOTES_FILE`，把内容塞到 `<description><![CDATA[...]]></description>`，并加一条 `<sparkle:fullReleaseNotesLink>`。
- 用 `<sparkle:fullReleaseNotesLink>` 而不是 `<sparkle:releaseNotesLink>`，否则 Sparkle 仍会去远程加载覆盖掉你的内联内容。
- workflow 里要 `fetch-depth: 0` + `fetch-tags: true`，否则 commit fallback 找不到上一个 tag。
