# TiDB DBA Check

面向 DBA 的 TiDB 集群巡检工具。通过 TiUP、SQL、SSH、Prometheus 和 ng-monitoring 收集信息，生成包含健康评分、问题明细和性能统计的 HTML 报告。

当前维护版本为 **v1.4.21**。本仓库从 **v1.4.20** 开始维护，原始脚本日期为 **2026-08-10**。入口统一为 `tidb_dba_check.sh`，后续版本通过 Git 提交、Pull Request 和版本标签管理。

[PDF 使用手册](docs/tidb_dba_check_guide_v1.4.pdf) · [使用方法](#快速开始) · [配置说明](#配置说明) · [已知限制](#运行行为与已知限制) · [参与贡献](CONTRIBUTING.md) · [更新记录](CHANGELOG.md) · [Apache-2.0](LICENSE)

**首次使用可先阅读 [《tidb_dba_check.sh 使用说明（v1.4）》](docs/tidb_dba_check_guide_v1.4.pdf)**，其中包含操作步骤、配置说明和报告示例。PDF 保留原始内容；其中的密码和内网地址均为演示数据，已由维护者确认可公开。手册对应 v1.4，当前版本的行为变化与注意事项请同时参考本 README 和更新记录。

## 可以检查什么

| 范围 | 主要内容 |
| --- | --- |
| 硬件与软件 | CPU、内存、磁盘、操作系统、集群拓扑与负载信息 |
| 集群健康 | 实例状态、启动时间、组件版本、标签、容量、Region、PD 调度器和 GC |
| 数据库实践 | 表结构、索引、数据库参数、统计信息 |
| 主机检查 | 系统配置、定时任务、内核日志、组件错误日志和用户空间 |
| 性能统计 | PD、TiDB、TiKV 的相关性能指标 |
| SQL 统计 | 按 TiDB CPU、TiKV CPU、总耗时、执行次数和执行计划数量观察 SQL |

报告汇总低危、中危、高危、Critical 问题，并提供健康评分、问题等级筛选和章节导航。`notice` 为提示项，不参与评分。评分反映已采集到的检查结果；数据缺失或权限不足需要单独排查。

## 运行条件

- **执行位置**：管理目标集群的 Linux TiUP 中控机，使用能够访问该集群 TiUP 元数据和 SSH 密钥的用户运行。
- **Shell**：Bash 4 或更高版本；脚本使用关联数组和大小写转换，不能使用 `sh` 执行。完整巡检依赖 GNU 工具，不适用于 macOS 默认环境。
- **本机命令**：`tiup`、`mysql` 客户端、`ssh`、`curl`、`jq`、`bc`，以及 GNU `awk`、`grep`、`date` 等常用命令。`grep -P`、`date -d` 需要可用。
- **集群版本**：脚本设置的最低版本门槛为 **TiDB v6.5.0**。这不代表所有后续版本都已通过兼容性验证；系统表、指标和参数随版本变化，使用前需要在自己的目标版本验证。
- **网络**：中控机能够访问数据库 SQL 端口、节点 SSH、Prometheus；Top SQL 还需要可用的 ng-monitoring 和相应采集数据。
- **权限**：数据库账号需要读取所选模块用到的系统表和集群信息，例如 `INFORMATION_SCHEMA`、`METRICS_SCHEMA`、`mysql.tidb`、`mysql.stats_*`、`mysql.analyze_options` 以及 `SHOW CONFIG`。主机账号需要读取系统信息和组件日志。具体授权应由 DBA 根据目标版本与模块核实，本仓库不自动创建用户或授予权限。

`tidb_inspector` 只是示例账号名称，需要自行创建或替换为已授权账号。请先安装好依赖并核实权限，再运行巡检。

## 快速开始

配合 [PDF 图文手册](docs/tidb_dba_check_guide_v1.4.pdf) 按以下步骤操作；在 GitHub 文件页面可预览或下载 PDF。

### 1. 获取代码

```bash
git clone https://github.com/jielun132/tidb_dba_check.git
cd tidb_dba_check

# 复现初始版本时使用此标签；日常维护使用 main 分支。
git switch --detach v1.4.20
```

查看帮助不会连接数据库或集群：

```bash
bash tidb_dba_check.sh --help
```

### 2. 准备本地配置

```bash
cp tidb_dba_check.conf.example tidb_dba_check.conf
chmod 600 tidb_dba_check.conf
tiup cluster list
```

编辑 `tidb_dba_check.conf`，把 `[cluster:my-cluster]` 中的 `my-cluster` 改为 TiUP 中真实的集群名称，填写数据库账号与密码，并确认主机用户。

```ini
[global]
inspection_window_minutes = 720

[cluster:my-cluster]
db_ip =
db_user = tidb_inspector
db_password =
db_port =
host_ips =
os_user = tidb
```

这里展示的是连接部分；完整配置请从示例文件复制，保留参数基线和 `[modules]`。

`db_password` 留空表示使用无密码连接，并不会弹出输入提示。需要密码时，在本地配置中填写实际值，不加引号，也不要在同一行追加注释。不要把实际密码写入 Git、Issue 或 PR。

### 3. 检查并运行

```bash
# 确认当前用户能读取目标集群。
tiup cluster display my-cluster

# 检查必需命令；缺失项应先安装。
for cmd in bash tiup mysql ssh curl jq bc awk grep date; do
  command -v "$cmd" || break
done

# 每次处理一个集群，默认读取脚本同目录配置。
bash tidb_dba_check.sh my-cluster
```

脚本默认从**脚本所在目录**读取 `tidb_dba_check.conf`，并把结果写入当前工作目录。可通过 `CONFIG_FILE=/path/to/local.conf bash tidb_dba_check.sh my-cluster` 指定配置文件；启动时会显示配置路径和实际 SSH 登录用户。请在同一中控机上串行运行，避免固定临时文件相互覆盖；同一集群同一分钟内重复执行也会覆盖同名报告。

### 4. 查看报告

生成文件的名称包含集群名、脚本版本和分钟级时间戳：

```text
my-cluster_check_info_v1.4.21_YYYYMMDD_HHMM.html
my-cluster_3.4_dev_best_practices_detail_v1.4.21_YYYYMMDD_HHMM.csv
```

HTML 可用浏览器打开；CSV 对应开发最佳实践检查明细，是否生成取决于模块及查询结果。报告可能包含 IP、拓扑、SQL 文本、表名和日志，只应在获准的范围内保存和分享。

## 配置说明

### 连接信息与时间窗口

| 配置项 | 说明 |
| --- | --- |
| `[cluster:<name>]` | `<name>` 必须与命令参数及 TiUP 集群名完全一致；节名独占一行，支持首尾空白及尾随注释 |
| `db_user` | 必填，数据库巡检账号 |
| `db_password` | 数据库密码，可为空；完整值取自等号后，首尾空白会被移除 |
| `db_ip` / `db_port` | 留空时，尝试从 TiUP 输出中寻找第一个 `Up` 状态的 TiDB 节点；自动识别失败时显式填写 |
| `host_ips` | 留空时从 TiUP 拓扑获取；手动填写时使用英文逗号分隔 |
| `os_user` | 必填的远程主机登录用户，示例为 `tidb`；可按实际部署填写 `tidb1`，兼容键名 `osuser`；应与可用的 SSH 密钥匹配 |
| `inspection_window_minutes` | 性能与 SQL 数据查询窗口，填正整数分钟；示例为 `720`，缺省时脚本回退到 `2880` |

配置文件可包含多个 `[cluster:<name>]` 节；每次命令只检查指定集群。即使手动填写数据库和主机地址，脚本仍需要 TiUP 和 Prometheus。

### 检查模块

在 `[modules]` 中用 `true` 启用、`false` 禁用。示例文件包含全部 19 个开关；未配置的模块不会执行。

| 模块组 | 配置键 |
| --- | --- |
| 基础信息 | `check_hardware_info`、`check_software_info`、`check_tidb_overview` |
| 数据库实践 | `check_dev_best_practices`、`check_db_params`、`check_stats_best_practices` |
| 主机与日志 | `check_sys_config`、`check_crontab`、`check_dmesg_logs`、`check_db_error_logs`、`check_user_space` |
| 性能 | `check_pd_performance`、`check_tidb_performance`、`check_tikv_performance` |
| SQL | `check_sql_order_by_tidb_cpu_time`、`check_sql_order_by_tikv_cpu_time`、`check_sql_order_by_elapsed_time`、`check_sql_order_by_executions`、`check_sql_order_by_plans` |

例如，暂不采集 Top SQL CPU 信息时：

```ini
check_sql_order_by_tidb_cpu_time = false
check_sql_order_by_tikv_cpu_time = false
```

模块开关不会跳过所有初始化步骤，不能用来免除 TiUP、Prometheus 或 SSH 密钥发现等启动条件。

### 参数基线

`[variables_params]` 和 `[tidb_config_params]` 用于比较数据库当前配置与参考值，**不会自动修改数据库参数**。示例继承了 v1.4.20 的参考值，包含环境相关数值和表达式；应按硬件、业务与 TiDB 版本审查后使用，不能直接当成统一调参标准。

原配置中的 `[pd_config_params]` 和 `[tikv_config_params]` 作为历史参考保留，v1.4.20 的参数比较函数并未读取这两个节。它们不代表已经执行的检查项。

## 运行行为与已知限制

- 巡检通过查询和远程读取收集信息，并会生成本地报告与临时文件。缺少 `curl`、`jq` 或 `bc` 时，原脚本会尝试通过 `sudo apt-get`、`sudo yum` 或 `sudo apk` 安装依赖；安装失败后仍可能继续执行。建议运行前自行备齐依赖。
- 当前数据库密码通过 `mysql -p` 参数传递，部分 SSH 调用使用 `StrictHostKeyChecking=no` 和 `UserKnownHostsFile=/dev/null`。这些是继承版本的实现限制；运行前请评估所在环境的访问与凭据保护要求。
- 部分 SQL 错误被重定向到 `/dev/null`。权限不足、指标缺失或不兼容的系统表可能表现为空结果，报告正常或高分不能证明采集完整。
- 临时文件中存在固定的 `/tmp/*.txt` 路径，因此不支持在同一主机安全地并发运行多个实例。
- 本次开源整理完成了语法与命令入口检查，**没有连接真实 TiDB 集群做端到端验证**。后续兼容性记录以对应版本的测试证据为准。

常见问题：

| 现象 | 排查方向 |
| --- | --- |
| `Failed to detect Prometheus address via tiup` | 当前用户的 TiUP 环境、集群名、Prometheus 组件及 `tiup cluster display` 输出 |
| `Cluster ... not found or missing configuration` | 启动时显示的配置路径、配置节名称以及 `db_user` 是否填写 |
| 无法找到 SSH 密钥 | 当前用户能否查看 `tiup cluster list`，集群元数据中是否存在对应 SSH 密钥 |
| SQL 或性能表为空 | 数据库权限、监控可达性、数据保留窗口、系统表和指标的版本差异 |
| Top SQL CPU 无数据 | ng-monitoring 地址与端口、采集状态和查询窗口内的数据 |
| `declare`、大小写转换或 `date -d` 报错 | 是否使用 Linux 上的 Bash 4+ 和 GNU 工具，是否误用了 `sh` |

## 仓库与协作

```text
tidb_dba_check.sh           主程序，版本号保留在 SCRIPT_VERSION
tidb_dba_check.conf.example 无凭据的完整配置示例
README.md                  安装、配置、运行与限制
CONTRIBUTING.md             分支、PR、验证和版本发布约定
CHANGELOG.md                版本记录与导入来源
LICENSE                    Apache License 2.0
tests/smoke.sh              不连接集群的基础检查
docs/                      原始 v1.4 PDF 图文使用手册
.github/                   CI、Issue 与 PR 模板
```

日常改动通过分支和 Pull Request 合并到 `main`；没有仓库写权限的贡献者可以 Fork 后提交 PR。已有同事可由仓库管理员在 GitHub 的 Collaborators 设置中添加。具体步骤见 [贡献指南](CONTRIBUTING.md)。

本地运行与 CI 相同的基础检查：

```bash
bash tests/smoke.sh
```

CI 仅检查 Bash 语法、帮助入口和缺少集群参数时的行为，不连接数据库、不使用生产凭据。修改 SQL、指标或主机检查时，还需要在获准的测试集群上验证。

## 来源与许可证

初始代码来自 `tidb_dba_check_v1.4.20.zip` 中的 `tidb_dba_check_v1.4.20.sh`。作者为 **PingCAP PSE 团队**，包含多个区域参与维护的同事；按维护者确认统一团队署名，保留历史版本记录。

公开版本采用 [Apache License 2.0](LICENSE)。开源整理统一了入口文件名和团队署名，将代码注释中的内网地址替换为文档示例地址，并新增文档、无凭据配置与协作检查；初始公开版本的巡检逻辑保持基线版本不变；后续修复见更新记录。原始 PDF 手册随仓库发布；原始配置和原始压缩包不包含在公开仓库中。
