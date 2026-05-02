# CCAS

macOS 菜单栏版 Claude Code 账号切换器。

- 账号索引：`~/.ccas/sequence.json`
- 配置备份：`~/.ccas/configs/`
- 账号凭据：macOS Keychain，service 为 `dev.local.ccas.accounts`
- Claude Code 当前凭据：macOS Keychain，service 为 `Claude Code-credentials`

## 使用

先构建 app：

```bash
./scripts/build_app.sh
```

构建完成后运行：

```bash
open dist/CCAS.app
```

右上角菜单栏会出现 CCAS 图标。

## 添加账号

1. 在 Claude Code 中登录一个账号。
2. 打开 CCAS 菜单栏面板，点击“添加账号”。
3. 切到另一个 Claude Code 账号后，再点击一次“添加账号”。

## 切换账号

在账号列表中点击目标账号即可切换。切换完成后需要重启 Claude Code，新的认证才会生效。

## License

MIT
