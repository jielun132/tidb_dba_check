# 参与维护

欢迎通过 Issue 报告问题、讨论改进，通过 Pull Request 提交代码或文档。提交内容适用本仓库的 [Apache-2.0 许可证](LICENSE)，请确认你有权贡献相应内容，并保留已有作者署名。

## 分支与 Pull Request

- `main` 是日常维护分支。
- 一个 PR 解决一个问题，避免混入无关格式化和重构。
- 分支名使用 `fix/<topic>`、`feat/<topic>` 或 `docs/<topic>`。
- 有写权限的同事在本仓库开分支；其他贡献者先 Fork，再向本仓库 `main` 发起 PR。
- 建议至少由另一位维护者审阅，确认 CI 通过后合并。这是协作约定；是否由 GitHub 强制执行取决于仓库保护规则。

有写权限的维护者可按以下流程操作：

```bash
git clone git@github.com:jielun132/tidb_dba_check.git
cd tidb_dba_check
git switch main
git pull --ff-only
git switch -c fix/example-topic

# 修改并验证。
bash tests/smoke.sh
git diff --check
git diff

# 只暂存本次涉及的文件；不要使用 git add -f 添加配置或报告。
git add tidb_dba_check.sh
git commit -m "fix: describe the actual change"
git push -u origin fix/example-topic
```

Fork 贡献者将克隆地址替换为自己 Fork 的 SSH 地址。PR 说明需要写清问题触发条件、改动后的行为、验证方式以及未验证的范围。

## 验证要求

`bash tests/smoke.sh` 不需要 TiUP、数据库或 SSH 连接，覆盖：

1. 主脚本和检查脚本的 Bash 语法。
2. `-h`、`--help` 成功退出并显示用法。
3. 缺少集群名时失败退出并提示原因。

这些检查不能代替真实巡检验证。修改 SQL、参数比较、指标、拓扑解析或远程命令时，应在获准的测试环境中验证，并在 PR 中记录：

- TiDB、TiUP、操作系统和 Bash 版本。
- 启用模块、触发条件、实际结果与期望结果。
- 与变更相关的脱敏片段；如果无法验证，明确写明原因。

CI 不连接真实集群，也不需要配置生产 Secret。不要为了通过检查降低断言或隐藏报错。

## 配置与数据

- 只维护 `tidb_dba_check.conf.example`；实际连接信息放在本地 `tidb_dba_check.conf` 中。
- 修改配置项或默认行为时，同步更新示例和 README。
- 不提交数据库密码、Token、私钥、客户名称、真实拓扑、SQL 业务数据或原始巡检报告。
- Issue 和 PR 都是公开内容，附件和截图同样需要脱敏。
- `.gitignore` 是防误提交措施，提交前仍需检查暂存区。

## 版本发布

初始公开基线为 `v1.4.20`。之后保持入口文件名不变，用 `vX.Y.Z` 标签标识版本。

发布由维护者在完成审阅、目标版本验证及发布确认后执行：

1. 更新脚本头部版本、日期和 `SCRIPT_VERSION`。
2. 在 `CHANGELOG.md` 记录实际改动与验证范围，同步相关文档。
3. 通过 PR 合并到 `main`，确认 CI 通过。
4. 在确定的提交上创建附注标签，并通过 SSH 推送该标签。
5. 创建对应 GitHub Release，写清兼容性、变更和已知问题。

不要覆盖已经公开的版本标签。发布内容只取自 Git 中审核过的源码；原始配置、报告和包含敏感信息的旧分发包不能作为 Release 附件。
