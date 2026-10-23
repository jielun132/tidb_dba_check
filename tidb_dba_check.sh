#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Public distribution: example IPs in comments replaced; inspection logic unchanged.

# ============================================================================
# 脚本名称: tidb_dba_check.sh
# 作者: PingCAP 南区 PSE 团队
# 创建日期: 2024-12-25
# 版本: 1.4.20
# 更新日期: 2026-08-10
# 描述:
#   本脚本根据 `tidb_dba_check.conf` 文件中指定的配置，对 TiDB 集群执行一系列检查。
#   检查内容包括硬件信息、软件信息、TiDB 概览、最佳实践、系统参数、错误日志、数据库性能问题等等。
#   检查结果以 HTML 格式输出。
#
# 版本更新日志:
#   1.0 (2024-12-25):
#       - 完成脚本功能
#   1.1 (2025-02-10):
#       - 修复或优化15处已知问题
#   1.2 (2025-02-24):
#       - 修复或优化8处已知问题
#   1.3 (2026-03-19):
#       - 修复或优化9处已知问题
#   1.4 (2026-04-11):
#       - 优化 HTML 报告的视觉样式与可读性
#   1.4.2 (2026-04-30):
#       - 修复 4.2 中非数字指标导致 bc syntax error 的问题
#   1.4.3 (2026-04-30):
#       - 调整 PD 调度器检查逻辑，按当前全量 scheduler 与启用 scheduler 差异告警
#   1.4.4 (2026-07-27):
#       - 新增健康评分体系（满分100分扣分制，四级问题：低危/中危/高危/Critical）
#       - 报告首页显示健康评分、等级、问题分布及详细问题列表
#   1.4.5(kimi-k2.7) (2026-08-04):
#       - 修复问题详情中的空行问题
#       - 报告页脚/标题显示脚本版本号
#   1.4.6(kimi-k2.7) (2026-08-04):
#       - 修复 tiup cluster display 输出列变化导致主机 IP 被识别为 (patched) 的问题
#   1.4.7(kimi-k2.7) (2026-08-04):
#       - 修复 3.2 拓扑信息同样因 tiup 列变化把 patch 状态误识别为主机的问题
#   1.4.8(kimi-k2.7) (2026-08-04):
#       - 第四章 Performance Statistics 无论是否有异常都打印明细行
#   1.4.9(glm-5.2) (2026-08-05):
#       - 修复 get_ssh_key_path 使用 grep 模糊匹配导致相似集群名（如 tidb-cc 和 tidb-cc-856）误匹配的问题，改用 awk 精确匹配
#   1.4.10(glm-4.7) (2026-08-05):
#       - 修复 TopSQL API 使用错误的端口（Blackbox Exporter 的 9115 端口）
#       - 新增 get_dashboard_addr() 函数从 PD 获取 Dashboard 地址（端口 2379）
#       - TopSQL 请求地址更新为使用 Dashboard API 而非 Prometheus
#       - 改进 TopSQL 非法 JSON 响应的错误处理，不计入重试次数
#       - 移除脚本头部的 "# 大模型: glm-5.2" 注释行
#   1.4.11(glm-5.2) (2026-08-05):
#       - 修复 get_dashboard_addr 中命令替换内换行符位于管道符 | 之前导致语法错误，
#         使 DASHBOARD_ADDR 解析为空、TopSQL 回退到 Blackbox Exporter 9115 端口的问题
#       - 纠正 TopSQL API 归属：/topsql/v1/* 由 ng-monitoring(默认端口 12020) 提供，而非 PD Dashboard(2379)
#       - 移除错误的 get_dashboard_addr/DASHBOARD_ADDR 逻辑，重写 get_ng_addr：
#         优先查找独立 ng-monitoring 组件行，否则从 prometheus 行端口列表中取 12020
#         (原实现 awk -F'/' '{print $2}' 假设端口格式为 9090/12020，遇到 9090/9115/9100/12020
#         时误取 9115 blackbox 端口)
#       - 修正第五章执行顺序与编号，使其与报告章节一致：5.1=TiDB CPU、5.2=TiKV CPU、5.3=Elapsed、
#         5.4=Executions、5.5=Plans（原执行顺序为 Elapsed/TiDB/TiKV，进度消息编号错位）
#       - 理顺 summary 中 ERROR_COUNT 与 check id 的交叉引用，使 checkN 对应 ERROR_COUNTN
#   1.4.12(glm-5.2) (2026-08-05):
#       - 4.2 Performance statistics by TiDB 显示单位修复：cpu usage 的 Avg/Max Metrics 列统一加 %
#         (原仅告警行带 %，正常行无单位)；memory usage 的 Avg/Max Metrics 列统一加 GB 单位
#   1.4.13(glm-5.2) (2026-08-05):
#       - HTML 报告与 CSV 文件名加入脚本版本号：{cluster}_check_info_{version}_{timestamp}.html
#         （如 tidb-cc_check_info_v1.4.13_20260805_1618.html），便于区分不同版本生成的报告
#   1.4.14(glm-5.2) (2026-08-05):
#       - 修复 3.7 透明大页误报：原同时要求 AnonHugePages=0 且 grubby 持久化标记，过严导致 [never] 已生效仍报高危；
#         改为仅判断运行时 [never] 是否生效（与 tiup cluster check 一致），并移除多余的 AnonHugePages/grubby SSH 采集
#       - 修复 3.7 tcp_tw_recycle 误报：该 sysctl 在 kernel 4.12+ 已移除，CentOS 8 等新内核上不存在属正常，
#         "未设置" 现视为符合，不再报高危
#   1.4.15(glm-5.2) (2026-08-05):
#       - 3.7 limits.conf 检查改为下限告警：tidb nofile(soft/hard) < 1000000 或 tidb soft stack < 10240 时告警
#         (原为精确匹配期望值 nofile=1000000/stack=32768，且检查 tidb hard stack；现移除 hard stack 检查，
#         未设置仍告警，提示文案改为"应不低于")
#   1.4.16(glm-5.2) (2026-08-09):
#       - 健康评分卡片 UI 优化：评分等级(优秀/良好/...)原为小字独立一行，现改为与分数同字号(28px)并置于同一行
#         (新增 .metric-grade 样式，分数行变为"92 🟢 优秀"；建议文案单独留在小字说明行)
#       - 危险等级处理建议文案更新为"存在 Critical 级别问题或大量高危问题，必须紧急干预"
#   1.4.17(glm-5.2) (2026-08-09):
#       - 修复 3.5 Variables 参数检查大小写敏感误报：current_value 与 standard_value 比较改为忽略大小写
#         (如 autocommit 当前=ON、标准=on 不再判为异常)，避免仅大小写差异(ON/on、0/OFF 等)触发低危告警
#       - 同上修复 3.5 Config 检查([tidb_config_params]，取自 CLUSTER_CONFIG)：current_value 与 standard_val
#         比较也改为忽略大小写，覆盖布尔/数值/枚举/字符串所有取值类型
#   1.4.18(glm-5.2) (2026-08-10):
#       - 3.7 系统配置检查对齐检查项清单：
#         * 磁盘挂载改为双阈值：缺少 noatime → low；缺少 nodelalloc 或文件系统非 ext4 → high（未挂载仍 high）
#         * 新增 7 项检查：CPU 调频策略(performance,high)、clocksource(tsc,high)、irqbalance(active,medium)、
#           操作系统版本是否支持(高版本支持列表,high)、时区是否相同(跨主机,medium)、操作系统版本是否相同(跨主机,notice)、
#           操作系统内核是否相同(跨主机,notice)；单机项每台主机合并为一次 SSH 采集，跨主机项循环后比对去重
#         * 静态检查表补 7 行
#       - 修复 4 处级别与清单不一致：3.3 label 检查 high→critical、3.6 健康度<90% low→notice、
#         3.7 TiDB UID/GID medium→low、3.7 TiDB 密码过期 low→notice
#       - 回填 doc/TiDB巡检检查项清单.xlsx 行 75-81 的检查标准/触发条件/检查命令
#   1.4.19(glm-4.7) (2026-08-10):
#       - 新增问题详情按级别筛选功能：点击问题分布卡片（低危/中危/高危/Critical）可筛选对应级别的问题，并自动跳转到问题详情
#       - 问题详情表按级别和章节排序：Critical → 高危 → 中危 → 低危 → notice，同级别内按章节排序
#       - 为问题详情表的每一行添加 data-severity 和 data-chapter 属性，支持前端筛选
#       - 问题分布卡片添加点击事件和悬停效果，增强交互体验
#   1.4.20(glm-4.7) (2026-08-10):
#       - 修复 vm.min_free_kbytes 检查逻辑错误：原为精确匹配（= 1048576），改为下限检查（≥ 1048576）
#       - 优化问题级别卡片交互：点击已选中卡片可取消筛选，显示所有问题详情
#       - 修复 CSS 样式冲突：移除重复的 .metric-label 定义，解决巡检章节/信息章节文字不显示问题
#       - 修复 JavaScript 作用域问题：将 filterIssuesBySeverity 函数移到 DOMContentLoaded 外部
#       - 修复问题详情表 HTML 结构：添加 <thead> 和 <tbody> 标签，确保 JavaScript 正确选择行元素
#       - 实现动态样式逻辑：问题数量>0显示颜色样式并可点击，数量=0显示默认样式
#
# 使用方法: 
#   tidb_dba_check.sh {cluster-name}   # 对指定的集群执行检查。
#   tidb_dba_check.sh -h               # 显示帮助信息。
# ============================================================================

CONFIG_FILE="tidb_dba_check.conf"
CHECK_TIME=$(date "+%Y/%m/%d %H:%M:%S")
SCRIPT_VERSION="v1.4.20"


# 检查是否为帮助选项，如果是则显示帮助
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<HELP
Usage: tidb_dba_check.sh {cluster-name}

Options:
  {cluster-name}   Specify the name of the TiDB cluster to check. Configuration must exist in $CONFIG_FILE.
  -h, --help       Display this help message.

Description:
  This script reads configuration from $CONFIG_FILE and performs various checks on the specified TiDB cluster.
  Results are saved in an HTML file named {cluster-name}_check_info_{version}_{YYYYMMDD_HHMM}.html.
HELP
    exit 0
fi

# 获取集群名，如果没有提供则报错
CLUSTER_NAME=$1
if [[ -z "$CLUSTER_NAME" ]]; then
    echo "Error: Missing cluster name. Use -h for help."
    exit 1
fi

# 确认 Prometheus 服务器地址
PROME_ADDR=$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null | grep -w "prometheus" | awk '{print $1}')
if [[ -z "$PROME_ADDR" ]]; then
    echo "[Error] Failed to detect Prometheus address via tiup."
    exit 1
fi

# 读取 inspection_window_minutes，若未设置则默认 2880
INSPECTION_WINDOW_MINUTES=$(awk -F '=' '
    BEGIN { val="" }
    /^\[global\]/ { in_global=1; next }
    /^\[/ && !/\[global\]/ { in_global=0 }
    in_global==1 && $1 ~ /inspection_window_minutes/ {
        val=$2
    }
    END {
        gsub(/^[ \t]+|[ \t]+$/, "", val)
        if(val == "") {
            val = "2880"  # 默认值
        }
        print val
    }
' "$CONFIG_FILE")

# 转换成小时，用于在 HTML 中展示
INSPECTION_WINDOW_HOURS=$((INSPECTION_WINDOW_MINUTES / 60))

# 提取指定集群的配置
HOST_IPS=$(awk -F '=' -v cluster_name="$CLUSTER_NAME" '
    BEGIN {found=0}
    /^\[cluster:/ {
        if ($0 == "[cluster:" cluster_name "]") {
            found=1
        } else {
            found=0
        }
    }
    found==1 && $1 ~ /host_ips/ {print $2}' "$CONFIG_FILE" | tr -d ' ')

# 如果配置文件里没有填写 host_ips，则通过 `tiup cluster display <cluster_name>` 获取 IP 列表
if [[ -z "$HOST_IPS" ]]; then
    echo "未在配置文件中找到 host_ips，尝试通过 'tiup cluster display $CLUSTER_NAME' 获取 IP ..."

    HOST_IPS=$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null \
        | awk '
            /^ID[[:space:]]+Role/ {
                host_idx = 0
                for (i = 1; i <= NF; i++) {
                    if ($i == "Host") { host_idx = i; break }
                }
                next
            }
            host_idx > 0 && /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
                host = $host_idx
                gsub(/[()]/, "", host)
                if (host ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                    print host
                }
            }
        ' \
        | sort -u \
        | paste -sd "," -)
fi

OS_USER=$(awk -F '=' -v cluster_name="$CLUSTER_NAME" '
    BEGIN {found=0}
    /^\[cluster:/ {
        if ($0 == "[cluster:" cluster_name "]") {
            found=1
        } else {
            found=0
        }
    }
    found==1 && $1 ~ /os_user/ {print $2}' "$CONFIG_FILE" | sed 's/#.*//' | tr -d ' ')


DB_IP=$(awk -F '=' -v cluster_name="$CLUSTER_NAME" '
    BEGIN {found=0}
    /^\[cluster:/ {
        if ($0 == "[cluster:" cluster_name "]") {
            found=1
        } else {
            found=0
        }
    }
    found==1 && $1 ~ /db_ip/ {print $2}' "$CONFIG_FILE" | tr -d ' ')

DB_PORT=$(awk -F '=' -v cluster_name="$CLUSTER_NAME" '
    BEGIN {found=0}
    /^\[cluster:/ {
        if ($0 == "[cluster:" cluster_name "]") {
            found=1
        } else {
            found=0
        }
    }
    found==1 && $1 ~ /db_port/ {print $2}' "$CONFIG_FILE" | tr -d ' ')

DB_USER=$(awk -F '=' -v cluster_name="$CLUSTER_NAME" '
    BEGIN {found=0}
    /^\[cluster:/ {
        if ($0 == "[cluster:" cluster_name "]") {
            found=1
        } else {
            found=0
        }
    }
    found==1 && $1 ~ /db_user/ {print $2}' "$CONFIG_FILE" | tr -d ' ')

DB_PASSWORD=$(
  awk -v cluster_name="$CLUSTER_NAME" '
    BEGIN {
      found = 0
    }

    /^\[cluster:/ {
      if ($0 == "[cluster:" cluster_name "]") {
        found = 1
      } else {
        found = 0
      }
      next
    }

    found && /^\s*db_password\s*=/ {
      sub(/^[^=]*=[ \t]*/, "", $0)

      sub(/^[ \t]+/, "", $0)
      sub(/[ \t]+$/, "", $0)

      print $0
      exit
    }
  ' "$CONFIG_FILE"
)

# 如果配置文件里没有填写 db_ip 或 db_port，则通过 `tiup cluster display <cluster_name>` 获取第一个 Up 状态的 TiDB 节点信息
if [[ -z "$DB_IP" || -z "$DB_PORT" ]]; then
    echo "未在配置文件中找到 db_ip 或 db_port，尝试通过 'tiup cluster display $CLUSTER_NAME' 获取..."

    # 获取第一个状态为 Up 的 TiDB 节点信息
    TIDB_NODE=$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null | awk '($2=="tidb" || $2=="ubisql") && $6~/^Up/ {split($1,a,":"); print a[1] ":" a[2]}' | head -n 1)

    if [[ -n "$TIDB_NODE" ]]; then
        if [[ -z "$DB_IP" ]]; then
            DB_IP=$(echo "$TIDB_NODE" | cut -d':' -f1)
        fi
        if [[ -z "$DB_PORT" ]]; then
            DB_PORT=$(echo "$TIDB_NODE" | cut -d':' -f2)
        fi
    fi
fi

# 检查配置必要信息 (只有 db_user 是必填)
if [[ -z "$DB_USER" ]]; then
    echo "Cluster $CLUSTER_NAME not found or missing configuration."
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M")
OUTPUT_FILE="${CLUSTER_NAME}_check_info_${SCRIPT_VERSION}_${TIMESTAMP}.html"
DEV_BP_CSV_FILE="${CLUSTER_NAME}_3.4_dev_best_practices_detail_${SCRIPT_VERSION}_${TIMESTAMP}.csv"

rm -f "$OUTPUT_FILE"
rm -f "$DEV_BP_CSV_FILE"


###############################################################################
# 服务所有需要 ssh 的模块
###############################################################################

# 获取 TiDB 集群对应的 SSH 密钥路径
function get_ssh_key_path() {
    local cluster_name="$1"
    # 使用 tiup cluster list 获取集群对应的路径（精确匹配集群名，避免匹配到 tidb-cc 和 tidb-cc-856 等相似名称）
    local ssh_key_path
    ssh_key_path=$(tiup cluster list 2>/dev/null | awk -v name="$cluster_name" '$1 == name {print $4"/ssh/id_rsa"}')

    if [[ -z "$ssh_key_path" ]]; then
        echo "ERROR: 无法找到集群 $cluster_name 对应的 SSH 密钥路径。"
        exit 1
    fi

    echo "$ssh_key_path"
}

# 获取 SSH 密钥路径
SSH_KEY_PATH=$(get_ssh_key_path "$CLUSTER_NAME")

###############################################################################
# 服务所有使用 SQL 的模块
###############################################################################
#    - 如果 DB_PASSWORD 不为空，则使用 -p"$DB_PASSWORD"
#    - 如果 DB_PASSWORD 为空，则跳过 -p 参数
run_sql() {
    local sql="$1"

    if [[ -n "$DB_PASSWORD" ]]; then
        # 密码不为空，拼接 -p"$DB_PASSWORD"
        mysql -h"$DB_IP" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" -N -e "$sql" 2>/dev/null
    else
        # 密码为空，直接省略 -p 参数
        mysql -h"$DB_IP" -P"$DB_PORT" -u"$DB_USER" -N -e "$sql" 2>/dev/null
    fi
}

###############################################################################
# 新增一个 CSV 转义函数
###############################################################################
escape_csv() {
    local s="$1"
    s=${s//$'\r'/}
    s=${s//$'\n'/\\n}
    s=${s//\"/\"\"}
    printf '"%s"' "$s"
}

###############################################################################
# 检查依赖 (curl / jq / bc) 并自动安装
###############################################################################
function detect_os_type() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    else
        echo "unknown"
    fi
}

function install_deps() {
    # 可以在此处统一添加需要检测/安装的依赖
    local tools=("curl" "jq" "bc")
    local missing=()

    # 逐个检测依赖是否已安装
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "依赖工具 (curl / jq / bc) 均已安装"
        return
    fi

    echo "检测到缺失依赖: ${missing[*]}，尝试自动安装..."

    local os_type
    os_type=$(detect_os_type)

    # 根据不同的发行版进行安装
    case "$os_type" in
        ubuntu|debian)
            sudo apt-get update -qq
            sudo apt-get install -y -qq "${missing[@]}" || echo "自动安装依赖失败，请手动安装后再试" 
            ;;
        centos|rhel|amzn)
            sudo yum install -y -q "${missing[@]}" || echo "自动安装依赖失败，请手动安装后再试" 
            ;;
        alpine)
            sudo apk add --no-cache -q "${missing[@]}" || echo "自动安装依赖失败，请手动安装后再试" 
            ;;
        *)
            echo "不支持的操作系统: $os_type, 请手动安装: ${missing[*]} (脚本继续执行)" 
            #exit 1
            ;;
    esac

    # 再次检查是否安装成功
    for tool in "${missing[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo "自动安装 $tool 失败，请手动安装后再试 (脚本继续执行)" 
            #exit 1
        fi
    done

    echo "依赖工具检测完毕（无论安装成功或失败，脚本继续执行）" 
}

# 调用函数，开始执行依赖检查及自动安装
install_deps


###############################################################################
# 健康评分体系（v1.4.4 新增）
###############################################################################
# 满分 100 分，扣分制。等级：🟢优秀(90-100) 🟡良好(80-89) 🟠一般(70-79) 🔴警告(60-69) ⚫危险(≤59)
# 按级别从低到高依次扣分：
# 1. 低危：每项扣 1 分，不低于 80（不会因低危导致等级低于良好）
# 2. 中危：每项扣 3 分，不低于 60（不会因低危+中危导致等级低于一般）
# 3. 高危：每项扣 5 分，遇到第一个时，-5分后若仍>79 则降至 79
# 4. Critical：每项扣 10 分，遇到第一个时，-10分后若仍>59 则降至 59
# Critical：每项扣 10 分，遇到第一个时若分数>59 则降至 59

ISSUES_FILE=$(mktemp)
# 格式: severity|chapter|item|description

_sev_rank() {
    case "$1" in
        info) echo 0 ;;
        notice) echo 1 ;;
        low) echo 2 ;;
        medium) echo 3 ;;
        high) echo 4 ;;
        critical) echo 5 ;;
        none) echo 0 ;;
        *) echo 0 ;;
    esac
}

report_issue() {
    local sev="$1" chapter="$2" item="$3" desc="$4"
    local key="${chapter}|${item}"
    local new_rank=$(_sev_rank "$sev")

    # info 级别不写入 ISSUES_FILE，仅提示和中危以上才记录
    if [[ "$sev" == "info" || "$sev" == "none" ]]; then
        return
    fi

    # 统一把描述中的真实换行转成 <br>，避免一条记录被拆成多行写入 ISSUES_FILE
    desc="${desc//$'\r'/}"
    desc="${desc//$'\n'/<br>}"

    if [[ -f "${ISSUES_FILE}.${key//\//_}" ]]; then
        local existing
        existing=$(cat "${ISSUES_FILE}.${key//\//_}")
        local old_sev old_desc old_rank
        old_sev=$(echo "$existing" | cut -d'|' -f1)
        old_desc=$(echo "$existing" | cut -d'|' -f4-)
        old_rank=$(_sev_rank "$old_sev")
        if [[ $new_rank -gt $old_rank ]]; then
            # 新条目等级更高：升级 severity，保留旧描述作为补充
            echo "${sev}|${key}|${desc}；另有：${old_desc}" > "${ISSUES_FILE}.${key//\//_}"
        elif [[ $new_rank -ge 1 ]]; then
            # 同级或更低（但至少为 notice）：追加描述，不升级
            echo "${old_sev}|${key}|${old_desc}；另有：${desc}" > "${ISSUES_FILE}.${key//\//_}"
        fi
    else
        echo "${sev}|${key}|${desc}" > "${ISSUES_FILE}.${key//\//_}"
    fi
}

_finalize_issues() {
    rm -f "$ISSUES_FILE"
    touch "$ISSUES_FILE"
    local f
    for f in "${ISSUES_FILE}."*; do
        [[ -f "$f" ]] || continue
        cat "$f" >> "$ISSUES_FILE"
        rm -f "$f"
    done
}

calculate_health_score() {
    local low=0 medium=0 high=0 critical=0 score=100

    if [[ -f "$ISSUES_FILE" && -s "$ISSUES_FILE" ]]; then
        while IFS='|' read -r sev _ch _it _desc; do
            case "$sev" in
                low) low=$((low + 1)) ;;
                medium) medium=$((medium + 1)) ;;
                high) high=$((high + 1)) ;;
                critical) critical=$((critical + 1)) ;;
            esac
        done < "$ISSUES_FILE"
    fi

    local total=$((low + medium + high + critical))
    if [[ $total -eq 0 ]]; then
        echo "100|优秀"
        return
    fi

    # 1. 低危：每项扣1分，不低于80（不会因低危导致等级低于良好）
    local after_low=$((score - low * 1))
    [[ $after_low -lt 80 ]] && after_low=80
    score=$after_low

    # 2. 中危：每项扣3分，不低于70（不会单纯因低危+中危导致等级低于一般）
    local after_med=$((score - medium * 3))
    [[ $after_med -lt 70 ]] && after_med=70
    score=$after_med

    # 3. 高危：每项扣5分，遇到第一个时，-5分后若仍高于79则降至79
    if [[ $high -gt 0 ]]; then
        score=$((score - 5))
        [[ $score -gt 79 ]] && score=79
        score=$((score - (high - 1) * 5))
    fi

    # 4. Critical：每项扣10分，遇到第一个时，-10分后若仍高于59则降至59
    if [[ $critical -gt 0 ]]; then
        score=$((score - 10))
        [[ $score -gt 59 ]] && score=59
        score=$((score - (critical - 1) * 10))
    fi

    [[ $score -lt 0 ]] && score=0

    local grade
    if [[ $score -ge 90 ]]; then grade="🟢 优秀"
    elif [[ $score -ge 80 ]]; then grade="🟡 良好"
    elif [[ $score -ge 70 ]]; then grade="🟠 一般"
    elif [[ $score -ge 60 ]]; then grade="🔴 警告"
    else grade="⚫ 危险"
    fi

    echo "${score}|${grade}"
}

generate_issues_html() {
    if [[ ! -f "$ISSUES_FILE" || ! -s "$ISSUES_FILE" ]]; then
        echo "<p style='color:var(--success);font-weight:700;'>未检测到异常问题。</p>"
        return
    fi

    # 创建排序后的临时文件：按级别倒序和章节升序排序
    local sorted_file=$(mktemp)

    # 定义级别优先级（数字越大越严重）
    local priority_file=$(mktemp)
    while IFS='|' read -r sev ch item desc; do
        local priority=0
        case "$sev" in
            notice) priority=1 ;;
            low) priority=2 ;;
            medium) priority=3 ;;
            high) priority=4 ;;
            critical) priority=5 ;;
        esac
        # 输出：优先级|级别|章节|条目|描述（用于排序）
        echo "${priority}|${sev}|${ch}|${item}|${desc}"
    done < "$ISSUES_FILE" | sort -t'|' -k1,1nr -k3,3n > "$priority_file"

    # 重新构建排序后的ISSUES_FILE格式
    > "$sorted_file"
    while IFS='|' read -r priority sev ch item desc; do
        echo "${sev}|${ch}|${item}|${desc}" >> "$sorted_file"
    done < "$priority_file"
    rm -f "$priority_file"

    local html=""
    html+="<table class='issues-table'>"
    html+="<colgroup><col style='width:80px;'><col style='width:70px;'><col style='min-width:200px;'><col style='min-width:400px;'></colgroup>"
    html+="<thead><tr><th>问题级别</th><th>章节</th><th>检查条目</th><th>详细描述</th></tr></thead>"
    html+="<tbody>"

    local row_idx=0
    while IFS='|' read -r sev ch item desc; do
        # 防御：跳过空/损坏行（无有效级别、或章节和条目均为空）
        case "$sev" in
            notice|low|medium|high|critical) ;;
            *) continue ;;
        esac
        if [[ -z "$ch" && -z "$item" ]]; then
            continue
        fi

        local badge
        case "$sev" in
            notice) badge="<span class='status-badge' style='color:#6b7280;background:#f3f4f6;border:#d1d5db 1px solid;'>提示</span>" ;;
            low) badge="<span class='status-badge status-info'>低危</span>" ;;
            medium) badge="<span class='status-badge' style='color:#9a3412;background:#ffedd5;border:#fdba74 1px solid;'>中危</span>" ;;
            high) badge="<span class='status-badge status-warn'>高危</span>" ;;
            critical) badge="<span class='status-badge' style='color:#fff;background:#dc2626;border:#b91c1c 1px solid;'>Critical</span>" ;;
        esac

        # ====== 统一清洗描述 ======

        # 1) 去除开头重复的 key| 前缀
        local cleaned_desc="$desc"
        local leading=""
        if [[ "$cleaned_desc" =~ ^(Config:[^|]+)\| ]]; then
            leading="${BASH_REMATCH[1]}"
        elif [[ "$cleaned_desc" =~ ^(Variables:[^|]+)\| ]]; then
            leading="${BASH_REMATCH[1]}"
        elif [[ "$cleaned_desc" =~ ^(sysctl\.conf)\| ]]; then
            leading="${BASH_REMATCH[1]}"
        elif [[ "$cleaned_desc" =~ ^(磁盘挂载)\| ]]; then
            leading="${BASH_REMATCH[1]}"
        elif [[ "$cleaned_desc" =~ ^(透明大页)\| ]]; then
            leading="${BASH_REMATCH[1]}"
        elif [[ "$cleaned_desc" =~ ^(label[[:space:]]*检查)\| ]]; then
            leading="${BASH_REMATCH[1]}"
        fi
        if [[ -n "$leading" ]]; then
            while [[ "$cleaned_desc" == "${leading}|"* ]]; do
                cleaned_desc="${cleaned_desc#${leading}|}"
            done
        fi

        # 通用兜底：若描述意外残留“检查条目|”前缀（如旧合并逻辑导致的重复标题），也一并去除
        if [[ -n "$item" ]]; then
            while [[ "$cleaned_desc" == "${item}|"* ]]; do
                cleaned_desc="${cleaned_desc#${item}|}"
            done
        fi

        # 2) 统一把 "；另有：" 或 "；" + 新实例/主机开头的内容 转为 <br>
        #    关键：每个 "实例=" 或 "主机=" 开头的新条目都要换行
        #    用 sed 一次性处理：先替换 "；另有：实例=" / "；另有：主机="，再替换残留的 "；实例=" / "；主机="
        cleaned_desc=$(echo "$cleaned_desc" | sed \
            -e 's/；另有：实例=/<br>实例=/g' \
            -e 's/；另有：主机=/<br>主机=/g' \
            -e 's/；实例=/<br>实例=/g' \
            -e 's/；主机=/<br>主机=/g')

        # 3) 去除残留的 "另有："（不在分隔符之后的）
        cleaned_desc="${cleaned_desc//另有：/}"
        cleaned_desc="${cleaned_desc//另有:/}"

        # 4) 去除残留中文分号（不在关键字前的）
        cleaned_desc="${cleaned_desc//；/}"

        # 5) 针对"实例启动时间检查"特殊处理
        if [[ "$item" == *"实例启动时间"* ]]; then
            # 去掉重复的标题前缀
            cleaned_desc=$(echo "$cleaned_desc" | sed \
                -e 's/近期重启[（(][^）)]*[）)][：:]//g' \
                -e 's/近期重启[：:]<br>//g' \
                -e 's/近期重启[：:]//g')
            cleaned_desc="${cleaned_desc#<br>}"
            # 统计实例数
            local tmp_remaining="$cleaned_desc"
            local inst_count=0
            while [[ "$tmp_remaining" == *"异常实例"* ]]; do
                inst_count=$((inst_count + 1))
                tmp_remaining="${tmp_remaining#*异常实例}"
            done
            cleaned_desc="近期重启（${inst_count} 个实例）:<br>${cleaned_desc}"
        fi

        desc="$cleaned_desc"

        # ====== 渲染 ======

        # 检测是否含 <br> 分隔的多行内容
        if [[ "$desc" == *"<br>"* ]]; then
            # 拆分为行数组
            local lines=()
            local remaining="$desc"
            while [[ "$remaining" == *"<br>"* ]]; do
                lines+=("${remaining%%<br>*}")
                remaining="${remaining#*<br>}"
            done
            [[ -n "$remaining" ]] && lines+=("$remaining")

            # 过滤空行 + 去重
            local seen_lines=()
            local filtered=()
            local li
            for li in "${lines[@]}"; do
                local trimmed="${li// /}"
                trimmed="${trimmed//$'\t'/}"
                [[ -z "$trimmed" ]] && continue
                # 去重
                local dup=0
                local s
                for s in "${seen_lines[@]}"; do
                    if [[ "$s" == "$trimmed" ]]; then
                        dup=1
                        break
                    fi
                done
                if [[ $dup -eq 0 ]]; then
                    seen_lines+=("$trimmed")
                    filtered+=("$li")
                fi
            done
            lines=("${filtered[@]}")

            local total=${#lines[@]}
            local visible=5
            if (( total == 0 )); then
                html+="<tr data-severity='${sev}' data-chapter='${ch}'><td>${badge}</td><td>${ch}</td><td>${item}</td><td>—</td></tr>"
            elif (( total <= visible )); then
                local inner=""
                local i
                for ((i=0; i<total; i++)); do
                    inner+="${lines[$i]}"
                    (( i < total - 1 )) && inner+="<br>"
                done
                html+="<tr data-severity='${sev}' data-chapter='${ch}'><td>${badge}</td><td>${ch}</td><td>${item}</td><td>${inner}</td></tr>"
            else
                local shown=""
                local i
                for ((i=0; i<visible; i++)); do
                    shown+="${lines[$i]}<br>"
                done
                local hidden=""
                for ((i=visible; i<total; i++)); do
                    hidden+="${lines[$i]}<br>"
                done
                local hidden_count=$(( total - visible ))
                html+="<tr data-severity='${sev}' data-chapter='${ch}'><td>${badge}</td><td>${ch}</td><td>${item}</td><td class='collapsible-cell' data-row='${row_idx}' data-total='${total}' data-visible='${visible}'>"
                html+="${shown}"
                html+="<a href='javascript:void(0)' class='expand-toggle' data-row='${row_idx}' data-total='${total}' data-visible='${visible}' onclick='toggleDesc(this, \"${row_idx}\")'>… 还有 ${hidden_count} 行，点击展开</a>"
                html+="<div class='hidden-content' id='hidden-${row_idx}' style='display:none;'>${hidden}</div>"
                html+="</td></tr>"
            fi
        else
            html+="<tr data-severity='${sev}' data-chapter='${ch}'><td>${badge}</td><td>${ch}</td><td>${item}</td><td>${desc}</td></tr>"
        fi
        row_idx=$((row_idx + 1))
    done < "$sorted_file"

    rm -f "$sorted_file"
    html+="</tbody></table>"
    echo "$html"
}



###############################################################################
# 检查 tidb 版本模块
###############################################################################

function check_tidb_version_for_cluster() {
    local cluster_name="$1"

    # 1. 获取该集群的 Cluster version 行
    #    例如："Cluster version:    v6.5.11"
    local version_line
    version_line=$(tiup cluster display "$cluster_name" 2>/dev/null \
        | grep -i "Cluster version" \
        || true)

    # 2. 判断是否获取到版本信息
    if [[ -z "$version_line" ]]; then
        echo "ERROR: 未找到集群 $cluster_name 的版本信息，请确认集群名称或 tiup 是否安装正确。"
        exit 1
    fi

    # 3. 从版本行中解析出版本号（去掉前后空格），例如 "v6.5.11"
    local cluster_version
    cluster_version=$(echo "$version_line" | awk -F':' '{print $2}' | xargs)

    # 4. 解析出主版本号 (major) 和次版本号 (minor)
    #    例如 v6.5.11 -> major=6, minor=5
    local major minor
    major=$(echo "$cluster_version" | sed 's/^v//' | cut -d'.' -f1)
    minor=$(echo "$cluster_version" | sed 's/^v//' | cut -d'.' -f2)

    # 5. 判断版本是否低于 v6.5.0
    #    如果 major < 6 或者 major=6 且 minor<5 即视为版本过低，脚本退出
    if [[ "$major" -lt 6 ]]; then
        echo "ERROR: 集群 [$cluster_name] 的版本为 $cluster_version，低于 v6.5.0，脚本退出。"
        exit 1
    elif [[ "$major" -eq 6 && "$minor" -lt 5 ]]; then
        echo "ERROR: 集群 [$cluster_name] 的版本为 $cluster_version，低于 v6.5.0，脚本退出。"
        exit 1
    else
        echo "集群 [$cluster_name] 的版本为 $cluster_version，符合要求。"
    fi
}


check_tidb_version_for_cluster "$CLUSTER_NAME"

###############################################################################
# 打印表头的固定格式
###############################################################################

cat <<EOF > "$OUTPUT_FILE"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>检查报告 - $CLUSTER_NAME</title>
    <style>
        :root {
            --page-bg: #eef4fb;
            --surface: #ffffff;
            --surface-muted: #f8fbff;
            --text-main: #1f2937;
            --text-subtle: #475569;
            --border: #d6dee8;
            --border-soft: #e7edf5;
            --brand: #1d4ed8;
            --brand-soft: #dbeafe;
            --success: #166534;
            --success-soft: #dcfce7;
            --warning: #9a3412;
            --danger: #991b1b;
            --shadow-md: 0 10px 24px rgba(15, 23, 42, 0.06);
            --radius-lg: 22px;
            --radius-md: 16px;
            --radius-sm: 12px;
        }
        * {
            box-sizing: border-box;
        }
        html {
            scroll-behavior: smooth;
        }
        body {
            margin: 0;
            padding: 28px;
            color: var(--text-main);
            font-family: "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
            line-height: 1.65;
            background:
                radial-gradient(circle at top right, rgba(147, 197, 253, 0.22), transparent 28%),
                linear-gradient(180deg, #f8fbff 0%, var(--page-bg) 100%);
        }
        a {
            color: var(--brand);
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .report-shell {
            max-width: 1500px;
            margin: 0 auto;
        }
        .report-header {
            margin-bottom: 26px;
            padding: 30px 34px;
            border-radius: 28px;
            color: #ffffff;
            background: linear-gradient(135deg, #0f172a 0%, #1d4ed8 55%, #2563eb 100%);
            box-shadow: 0 22px 50px rgba(29, 78, 216, 0.22);
        }
        .report-header h2 {
            margin: 0 0 10px;
            font-size: 32px;
            line-height: 1.25;
        }
        .report-header p {
            margin: 0;
            color: rgba(255, 255, 255, 0.9);
        }
        .meta-grid,
        .intro-grid,
        .summary-overview,
        .summary-grid {
            display: grid;
            gap: 14px;
        }
        .meta-grid {
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            margin-top: 22px;
        }
        .meta-card {
            padding: 14px 16px;
            border-radius: var(--radius-md);
            border: 1px solid rgba(255, 255, 255, 0.18);
            background: rgba(255, 255, 255, 0.12);
            backdrop-filter: blur(4px);
        }
        .meta-label,
        .metric-label {
            display: block;
            font-size: 12px;
            letter-spacing: 0.08em;
            text-transform: uppercase;
        }
        .meta-label {
            color: rgba(255, 255, 255, 0.72);
        }
        .meta-value {
            display: block;
            margin-top: 6px;
            font-size: 15px;
            font-weight: 700;
            color: #ffffff;
        }
        .section-card,
        .summary-panel {
            margin-bottom: 24px;
            padding: 24px 28px;
            border: 1px solid var(--border);
            border-radius: var(--radius-lg);
            background: var(--surface);
            box-shadow: var(--shadow-md);
        }
        .section-card h3,
        .summary-panel h3 {
            margin-top: 0;
        }
        .intro-grid {
            grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
        }
        .intro-card,
        .metric-card,
        .summary-item {
            border-radius: var(--radius-md);
            border: 1px solid var(--border-soft);
            background: linear-gradient(180deg, #ffffff 0%, var(--surface-muted) 100%);
        }
        .intro-card {
            padding: 18px 20px;
        }
        .intro-card h4 {
            margin: 0 0 10px;
            padding: 0;
            border: none;
            font-size: 18px;
        }
        .intro-card ul {
            margin: 0;
            padding-left: 20px;
        }
        table {
            width: 100%;
            margin: 16px 0 26px;
            border-collapse: separate;
            border-spacing: 0;
            table-layout: auto;
            border: 1px solid var(--border);
            border-radius: var(--radius-md);
            background: var(--surface);
            box-shadow: var(--shadow-md);
            overflow: hidden;
        }
        th, td {
            text-align: left;
            vertical-align: top;
            padding: 12px 14px;
            border-right: 1px solid #edf2f7;
            border-bottom: 1px solid #edf2f7;
            word-break: break-word;
            overflow-wrap: break-word;
            white-space: normal;
        }
        th:last-child,
        td:last-child {
            border-right: none;
        }
        th {
            color: #1e3a8a;
            font-weight: 700;
            background: linear-gradient(180deg, #eff6ff 0%, #dbeafe 100%);
            white-space: normal;
        }
        tbody tr:nth-child(even),
        table tr:nth-child(even) {
            background: #fafcff;
        }
        tbody tr:hover,
        table tr:hover {
            background: #f0f7ff;
        }
        table tr:last-child td {
            border-bottom: none;
        }
        h2, h3, h4, h5 {
            text-align: left;
        }
        h3 {
            margin: 34px 0 18px;
            padding-left: 14px;
            border-left: 5px solid var(--brand);
            font-size: 25px;
            line-height: 1.3;
        }
        h3[id],
        h4[id] {
            scroll-margin-top: 20px;
        }
        h4 {
            margin: 28px 0 14px;
            padding-bottom: 8px;
            border-bottom: 1px solid var(--border-soft);
            font-size: 20px;
        }
        h5 {
            margin: 20px 0 10px;
            font-size: 16px;
            color: #334155;
        }
        p,
        li {
            color: var(--text-subtle);
        }
        pre {
            margin: 0;
            padding: 12px 14px;
            max-width: 100%;
            overflow: auto;
            border-radius: var(--radius-sm);
            background: #0f172a;
            color: #e2e8f0;
            font-family: Consolas, Monaco, monospace;
            font-size: 13px;
            line-height: 1.6;
            white-space: pre-wrap;
            word-break: break-word;
        }
        code {
            padding: 2px 6px;
            border-radius: 8px;
            background: #eef2ff;
            color: #3730a3;
            font-size: 0.95em;
        }
        .summary-panel > p {
            margin-bottom: 20px;
        }
        .summary-overview {
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            margin-bottom: 18px;
        }
        .review-note {
            margin: 0 0 16px;
            padding: 12px 14px;
            border-radius: var(--radius-sm);
            border: 1px solid #fcd34d;
            background: #fffbeb;
            color: #b45309;
        }
        .metric-card {
            padding: 16px 18px;
        }
        .metric-card-action {
            width: 100%;
            text-align: left;
            cursor: pointer;
            color: inherit;
            font: inherit;
        }
        .metric-card-action:hover {
            border-color: #fca5a5;
            box-shadow: 0 12px 28px rgba(239, 68, 68, 0.12);
        }
        .metric-card-action.active {
            border-color: #ef4444;
            background: linear-gradient(180deg, #fff1f2 0%, #ffe4e6 100%);
        }
        .issue-filter-card {
            cursor: pointer;
            color: inherit;
            font: inherit;
            width: 100%;
            text-align: left;
            transition: all 0.2s ease;
        }
        .issue-filter-card:hover {
            border-color: #fca5a5;
            box-shadow: 0 12px 28px rgba(239, 68, 68, 0.12);
        }
        .issue-filter-card.active {
            border-color: #ef4444;
            background: linear-gradient(180deg, #fff1f2 0%, #ffe4e6 100%);
        }

        /* 问题级别样式 - 参考健康评分预览.html */
        .issue-low {
            border-color: #93c5fd;
        }
        .issue-low .metric-value {
            color: #1d4ed8;
        }
        .issue-low .metric-label {
            color: #1d4ed8;
            font-weight: 600;
        }
        .issue-low .metric-note {
            color: #1d4ed8;
        }
        .issue-low:hover {
            border-color: #60a5fa;
            box-shadow: 0 12px 28px rgba(29, 78, 216, 0.12);
        }
        .issue-low.active {
            border-color: #2563eb;
            background: linear-gradient(180deg, #eff6ff 0%, #dbeafe 100%);
        }

        .issue-medium {
            border-color: #fdba74;
        }
        .issue-medium .metric-value {
            color: #9a3412;
        }
        .issue-medium .metric-label {
            color: #9a3412;
            font-weight: 600;
        }
        .issue-medium .metric-note {
            color: #9a3412;
        }
        .issue-medium:hover {
            border-color: #fb923c;
            box-shadow: 0 12px 28px rgba(154, 52, 18, 0.12);
        }
        .issue-medium.active {
            border-color: #ea580c;
            background: linear-gradient(180deg, #fff7ed 0%, #ffedd5 100%);
        }

        .issue-high {
            border-color: #fca5a5;
        }
        .issue-high .metric-value {
            color: #991b1b;
        }
        .issue-high .metric-label {
            color: #991b1b;
            font-weight: 600;
        }
        .issue-high .metric-note {
            color: #991b1b;
        }
        .issue-high:hover {
            border-color: #ef4444;
            box-shadow: 0 12px 28px rgba(153, 27, 27, 0.12);
        }
        .issue-high.active {
            border-color: #dc2626;
            background: linear-gradient(180deg, #fef2f2 0%, #fee2e2 100%);
        }

        .issue-critical {
            background: linear-gradient(135deg, #991b1b 0%, #dc2626 100%);
            border-color: #b91c1c;
        }
        .issue-critical .metric-label {
            color: rgba(255, 255, 255, 0.9);
            font-weight: 600;
        }
        .issue-critical .metric-value {
            color: #ffffff;
        }
        .issue-critical .metric-note {
            color: rgba(255, 255, 255, 0.9);
        }
        .issue-critical:hover {
            border-color: #991b1b;
            box-shadow: 0 12px 28px rgba(220, 38, 38, 0.25);
        }
        .issue-critical.active {
            border-color: #7f1d1d;
            background: linear-gradient(135deg, #7f1d1d 0%, #b91c1c 100%);
        }

        .filter-check-mark {
            position: absolute;
            top: 8px;
            right: 8px;
            font-size: 14px;
            font-weight: 700;
        }
        .metric-label {
            color: #64748b;
        }
        .metric-value {
            display: block;
            margin-top: 8px;
            font-size: 28px;
            font-weight: 700;
            line-height: 1.1;
            color: #0f172a;
        }
        .metric-note {
            display: block;
            margin-top: 10px;
            font-size: 12px;
            color: #64748b;
        }
        .metric-grade {
            display: inline-block;
            margin-left: 12px;
            font-size: 28px;
            font-weight: 700;
            line-height: 1.1;
            white-space: nowrap;
        }
        .summary-grid {
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
        }
        .summary-item {
            padding: 16px 18px;
        }
        .summary-item.is-hidden {
            display: none;
        }
        .summary-item h4 {
            margin: 0;
            padding: 0;
            border: none;
            font-size: 16px;
        }
        .summary-item p {
            margin: 10px 0 0;
        }
        .summary-meta {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            flex-wrap: wrap;
        }
        .summary-link {
            margin-top: 8px;
            font-size: 13px;
            color: #64748b;
        }
        .summary-link a {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            color: #64748b;
            font-weight: 600;
        }
        .summary-link a:hover {
            color: var(--brand);
        }
        .back-to-summary {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-left: 12px;
            padding: 4px 10px;
            border-radius: 999px;
            border: 1px solid #bfdbfe;
            background: #eff6ff;
            color: var(--brand);
            font-size: 12px;
            font-weight: 700;
            vertical-align: middle;
        }
        .back-to-summary:hover {
            background: #dbeafe;
        }

        /* 可折叠描述单元格 */
        .collapsible-cell .expand-toggle {
            display: inline-block;
            margin-top: 4px;
            color: var(--brand);
            font-size: 13px;
            cursor: pointer;
            user-select: none;
            padding: 2px 8px;
            border-radius: 4px;
            background: #f0f5ff;
        }
        .collapsible-cell .expand-toggle:hover {
            background: #dbeafe;
        }
        .collapsible-cell .expand-toggle.expanded {
            color: #64748b;
        }
        .collapsible-cell .hidden-content {
            margin-top: 4px;
        }
        .report-section.is-hidden,
        .chapter-heading.is-hidden,
        .chapter-extra.is-hidden {
            display: none;
        }
        .cell-scroll-y {
            max-height: 180px;
            overflow-y: auto;
            overflow-x: hidden;
            padding-right: 6px;
        }
        .cell-scroll-y::-webkit-scrollbar {
            width: 10px;
        }
        .cell-scroll-y::-webkit-scrollbar-track {
            background: #e2e8f0;
            border-radius: 999px;
        }
        .cell-scroll-y::-webkit-scrollbar-thumb {
            background: #94a3b8;
            border-radius: 999px;
        }
        .table-text-heavy th:last-child,
        .table-text-heavy td:last-child {
            width: 36%;
            min-width: 340px;
        }
        .table-text-heavy th:nth-last-child(2),
        .table-text-heavy td:nth-last-child(2) {
            width: 14%;
            min-width: 150px;
        }
        .table-text-heavy td:last-child .cell-scroll-y,
        .table-text-heavy td[data-long-text='true'] .cell-scroll-y {
            white-space: normal;
        }
        .status-badge {
            display: inline-flex;
            align-items: center;
            padding: 4px 10px;
            border-radius: 999px;
            border: 1px solid transparent;
            font-size: 13px;
            font-weight: 700;
            white-space: nowrap;
        }
        .status-ok {
            color: var(--success);
            background: var(--success-soft);
            border-color: #86efac;
        }
        .status-warn {
            color: var(--danger);
            background: #fee2e2;
            border-color: #fca5a5;
        }
        .status-info {
            color: var(--brand);
            background: var(--brand-soft);
            border-color: #93c5fd;
        }
        td[style*="color:red"],
        td[style*="color: red"],
        span[style*="color:red"],
        span[style*="color: red"] {
            color: var(--danger) !important;
            font-weight: 700;
        }
        td[style*="color:green"],
        td[style*="color: green"],
        span[style*="color:green"],
        span[style*="color: green"] {
            color: var(--success) !important;
            font-weight: 700;
        }
        td[style*="color:blue"],
        td[style*="color: blue"],
        span[style*="color:blue"],
        span[style*="color: blue"] {
            color: var(--brand) !important;
            font-weight: 700;
        }
        td[style*="color:red"],
        td[style*="color: red"] {
            background: #fff1f2;
        }
        td[style*="color:green"],
        td[style*="color: green"] {
            background: #f0fdf4;
        }
        td[style*="color:blue"],
        td[style*="color: blue"] {
            background: #eff6ff;
        }
        p[style*="color:red"],
        p[style*="color: red"] {
            padding: 12px 14px;
            border-radius: var(--radius-sm);
            border: 1px solid #fdba74;
            background: #fff7ed;
            color: var(--warning) !important;
        }
        .error {
            color: var(--danger);
        }
        @media (max-width: 960px) {
            body {
                padding: 16px;
            }
            .report-header {
                padding: 24px;
                border-radius: 22px;
            }
            .section-card,
            .summary-panel {
                padding: 20px;
            }
            th,
            td {
                padding: 10px 12px;
            }
        }
</style>
</head>
<body>
<div class="report-shell">
<section class="report-header">
<h2>检查报告 - $CLUSTER_NAME</h2>
<div class="meta-grid">
    <div class="meta-card">
        <span class="meta-label">集群名称</span>
        <span class="meta-value">$CLUSTER_NAME</span>
    </div>
    <div class="meta-card">
        <span class="meta-label">检查时间</span>
        <span class="meta-value">$CHECK_TIME</span>
    </div>
    <div class="meta-card">
        <span class="meta-label">报告文件</span>
        <span class="meta-value">$OUTPUT_FILE</span>
    </div>
    <div class="meta-card">
        <span class="meta-label">脚本版本</span>
        <span class="meta-value">$SCRIPT_VERSION</span>
    </div>
</div>
</section>

<section class="section-card">
<h3>一、检查介绍</h3>
<div class="intro-grid">
    <div class="intro-card">
        <h4>1.1 检查方法</h4>
        <ul>
            <li>客户端管理工具</li>
            <li>操作系统工具和命令检查操作系统</li>
        </ul>
    </div>
    <div class="intro-card">
        <h4>1.2 检查范围</h4>
        <ul>
            <li>TiDB 集群的软硬件基本信息、集群概览</li>
            <li>是否符合开发最佳实践、参数最佳实践、统计信息最佳实践、系统配置最佳实践、TOP SQL等</li>
        </ul>
    </div>
    <div class="intro-card">
        <h4>1.3 检查目的</h4>
        <ul>
            <li>评估当前集群运行状况及风险</li>
        </ul>
    </div>
</div>
</section>

<!-- SUMMARY_PLACEHOLDER -->

<h3 class="filterable-chapter" data-chapter="3">三、基础检查</h3>
EOF



###############################################################################
# 解析配置文件的模块名
###############################################################################

function parse_modules_config() {
    awk '
        BEGIN {found=0}
        /^\[modules\]/ {found=1; next}
        /^\[/ && found==1 {found=0}
        found==1 && !/^#/ && !/^\s*$/ {
            line=$0
            sub(/#.*/, "", line)
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            if(line != "") {
                print line
            }
        }
    ' "$CONFIG_FILE"
}

declare -A MODULES_CONF
MODULES_TMP=$(mktemp)
parse_modules_config > "$MODULES_TMP"
while IFS='=' read -r mk mv; do
    mk=$(echo "$mk" | xargs)
    mv=$(echo "$mv" | xargs)
    [[ -n "$mk" && -n "$mv" ]] && MODULES_CONF[$mk]=$mv
done < "$MODULES_TMP"
rm -f "$MODULES_TMP"


###############################################################################
#  3.1 硬件信息检查函数
###############################################################################

function check_hardware_info() {
cat <<EOF >> "$OUTPUT_FILE"
<h4 id="check31">3.1 硬件基本信息</h4>
<table>
    <thead>
        <tr>
            <th>IP 地址</th>
            <th>CPU 架构</th>
			<th>vcore 数量</th>
            <th>NUMA 信息</th>
            <th>内存信息</th>
            <th>操作系统版本</th>
        </tr>
    </thead>
    <tbody>
EOF

# 循环写入数据部分
for IP in $(echo "$HOST_IPS" | tr ',' ' '); do
    HW_INFO=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$IP" '
        CPU_ARCH=$(lscpu | grep "Architecture" | awk -F ":" "{print \$2}" | xargs || echo "N/A");
        CPU_VCORE=$(lscpu | grep "^CPU(s):" | awk -F ":" "{print \$2}" | xargs || echo "N/A");
        NUMA_INFO=$(numactl --hardware | grep "available:" | xargs || echo "N/A");
        MEMORY_INFO=$(free -h | awk "/Mem:/ {print \$2}" || echo "N/A");
        OS_VERSION=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d "\"" -f2 || echo "N/A");
        echo -e "${CPU_ARCH}\n${CPU_VCORE}\n${NUMA_INFO}\n${MEMORY_INFO}\n${OS_VERSION}"
    ' 2>/dev/null)

    CPU_ARCH=$(echo "$HW_INFO" | sed -n 1p)
    CPU_VCORE=$(echo "$HW_INFO" | sed -n 2p)
    NUMA_INFO=$(echo "$HW_INFO" | sed -n 3p)
    MEMORY_INFO=$(echo "$HW_INFO" | sed -n 4p)
    OS_VERSION=$(echo "$HW_INFO" | sed -n 5p)

    cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>${IP}</td>
            <td>${CPU_ARCH:-N/A}</td>
            <td>${CPU_VCORE:-N/A}</td>
            <td>${NUMA_INFO:-N/A}</td>
            <td>${MEMORY_INFO:-N/A}</td>
            <td>${OS_VERSION:-N/A}</td>
        </tr>
EOF
done

# 关闭表格
cat <<EOF >> "$OUTPUT_FILE"
    </tbody>
</table>
EOF
}

###############################################################################
#  3.2 软件信息检查函数
###############################################################################

function check_software_info() {
    # 通用函数：将 Bytes 转换为 GB
    convert_to_gb() {
        local bytes="$1"
        echo "scale=2; $bytes / (1024^3)" | bc
    }


    # 获取数据库基本信息
    local db_version=$(run_sql "SELECT version();" | sed -n '1p')
    local cluster_id=$(run_sql "SELECT DISTINCT type FROM METRICS_SCHEMA.pd_cluster_metadata;" | sed -n '1p')
    local region_count=$(run_sql "SELECT MAX(value) FROM METRICS_SCHEMA.pd_cluster_status WHERE type='leader_count';" | sed -n '1p')
    local storage_size=$(run_sql "SELECT MAX(value) FROM METRICS_SCHEMA.pd_cluster_status WHERE type='storage_size';" | sed -n '1p')
    local storage_size_gb=$(convert_to_gb "$storage_size")

    # 计算时间戳
    current_time=$(date -u +"%s")
    start_time=$((current_time - INSPECTION_WINDOW_HOURS * 3600))
    end_time=$current_time

    #echo "Start time: $start_time, End time: $end_time" >&2

    # 获取 QPS 峰值
    local qps_query="sum(rate(tidb_executor_statement_total[30s]))"
    local qps_response=$(curl -s -G "$PROME_ADDR/api/v1/query_range" \
        --data-urlencode "query=$qps_query" \
        --data-urlencode "start=$start_time" \
        --data-urlencode "end=$end_time" \
        --data-urlencode "step=30s" \
        --max-time 10)


    # 检查 Prometheus 是否返回数据
    local status=$(echo "$qps_response" | jq -r '.status')
    if [[ "$status" != "success" ]]; then
        echo "WARNING: Prometheus 查询失败，状态：$status。" >&2
    fi

    # 提取所有 QPS 值并计算最大值
    local max_qps=$(echo "$qps_response" | jq -r '.data.result[].values[][1]' | sort -nr | head -n1)

    # 检查 QPS 是否为空
    if [[ -z "$max_qps" ]]; then
        echo "WARNING: 未能获取 QPS 峰值。" >&2
    elif [[ "$max_qps" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        max_qps=$(printf "%.2f" "$max_qps")
    fi

    # 获取 SQL duration P99 均值
    local p99_query='histogram_quantile(0.99, sum(rate(tidb_server_handle_query_duration_seconds_bucket[30s])) by (le))'
    local p99_sql=$(curl -s -G "$PROME_ADDR/api/v1/query" \
         --data-urlencode "query=$p99_query" | \
    jq -r '.data.result[].value[1]' | awk '{printf "%.3f\n", $1 * 1000}')

    # 检查 P99 是否为空
    if [[ -z "$p99_sql" ]]; then
        echo "WARNING: 未能获取 SQL duration P99 均值。" >&2
    fi

    # 将数据填充到 HTML 表格
    cat <<EOF >> "$OUTPUT_FILE"
<h4 id="check32">3.2 软件基本信息</h4>
<table>
    <tr>
        <th>项目</th>
        <th>值</th>
    </tr>
    <tr><td>数据库版本</td><td>${db_version:-N/A}</td></tr>
    <tr><td>数据库 cluster ID</td><td>${cluster_id:-N/A}</td></tr>
    <tr><td>Region 数量（单副本）</td><td>${region_count:-N/A}</td></tr>
    <tr><td>已用数据库空间大小（多副本）</td><td>${storage_size_gb:-N/A} GB</td></tr>
    <tr><td>QPS 峰值（${INSPECTION_WINDOW_HOURS} H）</td><td>${max_qps:-N/A}</td></tr>
    <tr><td>SQL duration P99 均值（${INSPECTION_WINDOW_HOURS} H）</td><td>${p99_sql:-N/A} ms</td></tr>
</table>
EOF

    # 获取拓扑信息
    local topology=$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null | awk '
        BEGIN {role_idx=0; host_idx=0}
        /^ID[[:space:]]+Role/ {
            for (i=1; i<=NF; i++) {
                if ($i == "Role") { role_idx = i }
                if ($i == "Host") { host_idx = i }
            }
            next
        }
        role_idx > 0 && host_idx > 0 && /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
            role = $role_idx
            host = $host_idx
            gsub(/[()]/, "", host)
            if (host ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                print role, host
            }
        }')

    if [[ -z "$topology" ]]; then
        echo "无法获取集群 $CLUSTER_NAME 的拓扑信息，请检查 tiup cluster display 命令是否有效。" >> "$OUTPUT_FILE"
        return
    fi

 # 清理并统计每个 IP 上的组件分布
declare -A ip_roles

# 遍历 topology 中的 role 和 ip
while read -r role ip; do
    # 跳过无效行
    [[ -z "$ip" || -z "$role" || "$ip" == "----" || "$role" == "----" ]] && continue

    # 使用 IP 和角色作为键
    key="$ip,$role"
    if [[ -z "${ip_roles[$key]}" ]]; then
        # 如果该角色还没有计数，则初始化为 1
        ip_roles["$key"]=1
    else
        # 如果该角色已存在，则计数加 1
        ip_roles["$key"]=$((ip_roles["$key"] + 1))
    fi
done <<< "$topology"

# 填充拓扑信息表格
cat <<EOF >> "$OUTPUT_FILE"
<h4>拓扑信息：</h4>
<table>
    <tr>
        <th>IP</th>
        <th>组件分布</th>
    </tr>
EOF

# 输出每个 IP 上的角色及其数量
declare -A ip_display
for key in "${!ip_roles[@]}"; do
    ip=$(echo "$key" | cut -d',' -f1)
    role=$(echo "$key" | cut -d',' -f2)
    count=${ip_roles[$key]}

    # 将每个 IP 的组件和数量存入 ip_display 数组
    if [[ -z "${ip_display[$ip]}" ]]; then
        ip_display["$ip"]="$role * $count"
    else
        ip_display["$ip"]="${ip_display[$ip]}, $role * $count"
    fi
done

# 输出最终的结果
for ip in "${!ip_display[@]}"; do
    echo "    <tr><td>$ip</td><td>${ip_display[$ip]}</td></tr>" >> "$OUTPUT_FILE"
done

cat <<EOF >> "$OUTPUT_FILE"
</table>
EOF

}

###############################################################################
#  3.3 TiDB 集群总览检查函数
###############################################################################

function check_tidb_overview() {
    # HTML 表格头部
    cat <<EOF >> "$OUTPUT_FILE"
<h4 id="check33">3.3 TiDB 集群总览</h4>
<table>
    <tr>
        <th>检查条目</th>
        <th>检查标准</th>
        <th>检查结果</th>
        <th>结果描述</th>
    </tr>
EOF
    # 初始化错误计数器
    ERROR_COUNT33=0
	
    # 检查实例状态
    check_instance_status

    # 检查实例启动时间
    check_instance_start_time
	
	# 检查组件版本
	check_component_versions
	
	# 检查 label
	check_label_consistency
	
	# 检查磁盘容量
	check_capacity_usage
	
	# 检查空region比例和数量
	check_empty_region
	
	# 检查调度器
	check_pd_schedulers
	
	# 检查 GC
	check_gc_status

    # 关闭表格
    echo "</table>" >> "$OUTPUT_FILE"
}

function check_instance_status() {
    local tiup_output
    tiup_output=$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "high" "3.3" "实例状态检查" "无法获取集群状态，请检查 TiUP 是否可用"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>实例状态检查</td>
            <td>是否所有组件为 UP 状态</td>
            <td><span style='color:red;'>异常</span></td>
            <td>无法获取集群状态，请检查 TiUP 是否可用</td>
        </tr>
EOF
        return
    fi

    # 提取异常实例
    local exceptions
    exceptions=$(echo "$tiup_output" | grep -E '^[0-9.]+' | awk '
        {
            match($0, /Up|Down|Unknown/, m)
            status = m[0]
            if (status != "Up") {
                print $1, $2
            }
        }')

    if [[ -n "$exceptions" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "high" "3.3" "实例状态检查" "异常实例: $(echo "$exceptions" | awk '{printf "%s<br>", $0}' | sed 's/<br>$//')"
        local exception_details=""
        while read -r id role; do
            exception_details+="异常实例：$id，角色：$role<br>"
        done <<< "$exceptions"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>实例状态检查</td>
            <td>是否所有组件为 UP 状态</td>
            <td><span style='color:red;'>异常</span></td>
            <td>$exception_details</td>
        </tr>
EOF
    else
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>实例状态检查</td>
            <td>是否所有组件为 UP 状态</td>
            <td><span style='color:green;'>正常</span></td>
            <td>所有实例均为 UP 状态</td>
        </tr>
EOF
    fi
}



function check_instance_start_time() {
    local cluster_info current_time recent_restarts
    current_time=$(date +%s)
    cluster_info=$(run_sql "SELECT TYPE, INSTANCE, START_TIME FROM INFORMATION_SCHEMA.CLUSTER_INFO;" 2>/dev/null | tail -n +2)

    if [[ $? -ne 0 || -z "$cluster_info" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "medium" "3.3" "实例启动时间检查" "无法获取启动时间"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>实例启动时间检查</td>
            <td>是否最近一个月内未发生过重启</td>
            <td><span style='color:red;'>异常</span></td>
            <td>无法获取启动时间，请检查数据库连接</td>
        </tr>
EOF
        return
    fi

    recent_restarts=""
    while read -r type instance start_time; do
        local start_timestamp time_diff
        start_timestamp=$(date -d "$start_time" +%s)
        time_diff=$(( (current_time - start_timestamp) / 86400 ))
        if [[ $time_diff -lt 30 ]]; then
            recent_restarts+="异常实例：$instance，角色：$type，启动时间：$start_time<br>"
        fi
    done <<< "$cluster_info"

    if [[ -n "$recent_restarts" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "medium" "3.3" "实例启动时间检查" "近期重启:<br>${recent_restarts}"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>实例启动时间检查</td>
            <td>是否最近一个月内未发生过重启</td>
            <td><span style='color:red;'>异常</span></td>
            <td>$recent_restarts</td>
        </tr>
EOF
    else
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>实例启动时间检查</td>
            <td>是否最近一个月内未发生过重启</td>
            <td><span style='color:green;'>正常</span></td>
            <td>无近期重启实例</td>
        </tr>
EOF
    fi
}


function check_component_versions() {
    local component_hashes
    component_hashes=$(run_sql "
SELECT 
    TYPE, 
    GROUP_CONCAT(DISTINCT GIT_HASH) AS git_hashes, 
    COUNT(DISTINCT GIT_HASH) AS hash_count
FROM 
    INFORMATION_SCHEMA.CLUSTER_INFO
GROUP BY 
    TYPE
HAVING 
    COUNT(DISTINCT GIT_HASH) > 1;" 2>/dev/null | tail -n +2)

    if [[ $? -ne 0 ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "high" "3.3" "组件版本检查" "无法获取组件版本信息"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>组件版本检查</td>
            <td>是否存在多个组件版本</td>
            <td><span style='color:red;'>异常</span></td>
            <td>无法获取组件版本信息，请检查数据库连接</td>
        </tr>
EOF
        return
    fi

    if [[ -n "$component_hashes" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "high" "3.3" "组件版本检查" "版本不一致: $(echo "$component_hashes" | awk '{printf "%s<br>", $0}' | sed 's/<br>$//')"
        local component_details=""
        while read -r type git_hashes hash_count; do
            component_details+="组件类型：$type，GIT_HASH列表：$git_hashes<br>"
        done <<< "$component_hashes"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>组件版本检查</td>
            <td>是否存在多个组件版本</td>
            <td><span style='color:red;'>异常</span></td>
            <td>
                <div style="padding: 8px;">
                    $component_details
                </div>
            </td>
        </tr>
EOF
    else
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>组件版本检查</td>
            <td>是否存在多个组件版本</td>
            <td><span style='color:green;'>正常</span></td>
            <td>
                <div style="padding: 8px;">
                    无异常组件
                </div>
            </td>
        </tr>
EOF
    fi
}



function check_label_consistency() {
    local tiup_labels_output
    tiup_labels_output=$(tiup cluster display "$CLUSTER_NAME" --labels 2>/dev/null)

    if [[ $? -ne 0 || -z "$tiup_labels_output" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33+ 1))
        report_issue "critical" "3.3" "label 检查" "无法获取标签信息"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>label 检查</td>
            <td>是否符合行内标准</td>
            <td><span style='color:red;'>异常</span></td>
            <td>无法获取标签信息，请检查 TiUP 是否正常</td>
        </tr>
EOF
        return
    fi

    declare -A ip_hosts
    declare -A machine_labels
    local label_exceptions=""
    local current_ip=""
    local current_labels=""

    # 处理每一行，逐行读取
    while IFS= read -r line; do
        # 如果是 Machine 行（含 IP 地址）
        if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            # 如果上一行处理过，检查标签是否一致
            if [[ -n "$current_ip" && -n "$current_labels" ]]; then
                if [[ -n "${ip_hosts[$current_ip]}" && "${ip_hosts[$current_ip]}" != "$current_labels" ]]; then
                    label_exceptions+="异常：IP $current_ip 的 host 值不一致（$current_labels 和 ${ip_hosts[$current_ip]}）<br>"
                fi
            fi
            # 记录当前的 IP 地址
            current_ip=$(echo "$line" | awk '{print $1}')
            current_labels=""
        fi

        # 如果是 Store 行（含 port 和 labels 信息）
        if [[ "$line" =~ \{host:.*\} ]]; then
            # 提取标签信息
            local labels=$(echo "$line" | grep -oP '{host:.*?}' | sed 's/[{}]//g' | sed 's/host: //')
            
            # 检查是否不同机器共享相同标签（只检查不同的 Machine）
            if [[ -n "${machine_labels[$labels]}" && "${machine_labels[$labels]}" != "$current_ip" ]]; then
                label_exceptions+="异常：标签 $labels 在不同的 Machine 中重复使用（${machine_labels[$labels]} 和 $current_ip）<br>"
            fi
            
            # 记录该 IP 对应的 host 标签
            if [[ -z "$current_labels" ]]; then
                current_labels="$labels"
            fi
            ip_hosts[$current_ip]=$labels
            machine_labels[$labels]=$current_ip
        fi
    done <<< "$tiup_labels_output"

    # 最后一行处理
    if [[ -n "$current_ip" && -n "$current_labels" ]]; then
        if [[ -n "${ip_hosts[$current_ip]}" && "${ip_hosts[$current_ip]}" != "$current_labels" ]]; then
            label_exceptions+="异常：IP $current_ip 的 host 值不一致（$current_labels 和 ${ip_hosts[$current_ip]}）<br>"
        fi
    fi

    # 输出结果到 HTML
    if [[ -n "$label_exceptions" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "critical" "3.3" "label 检查" "标签不一致: $label_exceptions"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>label 检查</td>
            <td>是否符合行内标准</td>
            <td><span style='color:red;'>异常</span></td>
            <td>
                <div style="padding: 8px;">
                    $label_exceptions
                </div>
            </td>
        </tr>
EOF
    else
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>label 检查</td>
            <td>是否符合行内标准</td>
            <td><span style='color:green;'>正常</span></td>
            <td>
                <div style="padding: 8px;">
                    无异常
                </div>
            </td>
        </tr>
EOF
    fi
}



function check_capacity_usage() {
    local tiup_labels_output
    tiup_labels_output=$(tiup cluster display "$CLUSTER_NAME" --labels 2>/dev/null)

    if [[ $? -ne 0 || -z "$tiup_labels_output" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "critical" "3.3" "容量检查" "无法获取容量信息"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>容量检查</td>
            <td>容量是否超过 70%</td>
            <td><span style='color:red;'>异常</span></td>
            <td>无法获取容量信息，请检查 TiUP 是否正常</td>
        </tr>
EOF
        return
    fi

    # 解析输出，提取 Machine:Port, Capacity 和 Available 列
    local capacity_details
    capacity_details=$(echo "$tiup_labels_output" | awk '
        /^[0-9.]+/ { machine=$1 }
        /^[[:space:]]+[0-9]+/ {
            port=$1; store=$2; capacity=$6; available=$7;
            gsub(/GiB|MiB|TiB|B/, "", capacity);
            gsub(/GiB|MiB|TiB|B/, "", available);
            print machine ":" port, capacity, available;
        }
    ')

    local capacity_exceptions=""

    # 检查容量使用情况
    while read -r machine_port capacity available; do
        # 转换 Capacity 和 Available 为浮点数（以 GiB 为单位）
        local capacity_bytes available_bytes usage_percent
        capacity_bytes=$(awk "BEGIN {print $capacity * 1024 * 1024 * 1024}")
        available_bytes=$(awk "BEGIN {print $available * 1024 * 1024 * 1024}")

        # 检查是否有容量为 0 的情况
        if (( $(echo "$capacity == 0" | bc -l) )); then
            capacity_exceptions+="$machine_port 对应磁盘容量为 0，无法使用<br>"
            continue
        fi

        # 计算使用率
        usage_percent=$(awk "BEGIN {print ($capacity_bytes - $available_bytes) / $capacity_bytes * 100}")

        # 判断容量使用是否超过 70%
        if (( $(echo "$usage_percent > 70" | bc -l) )); then
            capacity_exceptions+="$machine_port 对应磁盘使用率过高（使用率: $(printf "%.2f" "$usage_percent")%）<br>"
        fi
    done <<< "$capacity_details"

    # 将结果写入 HTML
    if [[ -n "$capacity_exceptions" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        # 多级阈值评分
        local max_cap_pct=0
        while read -r _mp cap avail; do
            [[ -z "$cap" || -z "$avail" ]] && continue
            if (( $(echo "$cap > 0" | bc -l) )); then
                local u=$(awk "BEGIN {printf "%.0f", ($cap - $avail) / $cap * 100}")
                [[ $u -gt $max_cap_pct ]] && max_cap_pct=$u
            fi
        done <<< "$capacity_details"
        if [[ $max_cap_pct -ge 90 ]]; then
            report_issue "critical" "3.3" "容量检查" "磁盘使用率最高 ${max_cap_pct}%（≥90%）"
        elif [[ $max_cap_pct -ge 80 ]]; then
            report_issue "high" "3.3" "容量检查" "磁盘使用率最高 ${max_cap_pct}%（≥80%）"
        elif [[ $max_cap_pct -ge 70 ]]; then
            report_issue "medium" "3.3" "容量检查" "磁盘使用率最高 ${max_cap_pct}%（≥70%）"
        elif [[ $max_cap_pct -ge 60 ]]; then
            report_issue "low" "3.3" "容量检查" "磁盘使用率最高 ${max_cap_pct}%（≥60%）"
        else
            report_issue "low" "3.3" "容量检查" "$capacity_exceptions"
        fi
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>容量检查</td>
            <td>容量是否超过 70%</td>
            <td><span style='color:red;'>异常</span></td>
            <td>
                <div style="padding: 8px;">
                    $capacity_exceptions
                </div>
            </td>
        </tr>
EOF
    else
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>容量检查</td>
            <td>容量是否超过 70%</td>
            <td><span style='color:green;'>正常</span></td>
            <td>
                <div style="padding: 8px;">
                    所有节点磁盘容量正常
                </div>
            </td>
        </tr>
EOF
    fi
}



function check_empty_region() {
    # 查询 empty-region-count 的最大值
    local empty_region_count
    empty_region_count=$(run_sql "SELECT MAX(value) FROM METRICS_SCHEMA.pd_region_health WHERE type='empty-region-count';")

    # 查询 leader_count 的最大值
    local leader_count
    leader_count=$(run_sql "SELECT MAX(value) FROM METRICS_SCHEMA.pd_cluster_status WHERE type='leader_count';")

    local region_check_result
    local region_check_detail

    # 检查是否异常
    if [[ -z "$empty_region_count" || -z "$leader_count" || "$leader_count" -eq 0 ]]; then
        region_check_result="异常"
        region_check_detail="无法获取 empty-region-count 或 leader_count 的值"
    elif [[ "$empty_region_count" -gt 100000 && $((empty_region_count * 100 / leader_count)) -gt 30 ]]; then
        region_check_result="异常"
        region_check_detail="空 region 数：$empty_region_count，占比：$(awk "BEGIN {printf \"%.2f\", $empty_region_count/$leader_count * 100}")%"
    else
        region_check_result="正常"
        region_check_detail="空 region 数：$empty_region_count，占比：$(awk "BEGIN {printf \"%.2f\", $empty_region_count/$leader_count * 100}")%"
    fi

    # 填充 HTML 表格中对应行
    if [[ "$region_check_result" == "异常" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "medium" "3.3" "空 region 情况" "$region_check_detail"
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>空 region 情况</td>
            <td>空 region 数占比30%；<br>并且空 region 是否超过 10W</td>
            <td><span style='color:red;'>异常</span></td>
            <td>
                <div style="padding: 8px;">
                    $region_check_detail
                </div>
            </td>
        </tr>
EOF
    else
        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>空 region 情况</td>
            <td>空 region 数占比30%；<br>并且空 region 是否超过 10W</td>
            <td><span style='color:green;'>正常</span></td>
            <td>
                <div style="padding: 8px;">
                    $region_check_detail
                </div>
            </td>
        </tr>
EOF
    fi
}



function check_pd_schedulers() {
    local all_scheduler_sql="SELECT DISTINCT kind FROM METRICS_SCHEMA.pd_scheduler_status;"
    local allowed_scheduler_sql="SELECT DISTINCT kind FROM METRICS_SCHEMA.pd_scheduler_status WHERE type='allow' AND value=1;"
    local all_scheduler_output allowed_scheduler_output
    all_scheduler_output=$(run_sql "$all_scheduler_sql" 2>/dev/null)
    allowed_scheduler_output=$(run_sql "$allowed_scheduler_sql" 2>/dev/null)

    local all_schedulers=()
    local allowed_schedulers=()
    local missing_schedulers=()
    local scheduler
    declare -A allowed_scheduler_map

    while IFS= read -r scheduler; do
        scheduler=$(echo "$scheduler" | tr -d '\r' | xargs)
        [[ -z "$scheduler" ]] && continue
        all_schedulers+=("$scheduler")
    done <<< "$all_scheduler_output"

    while IFS= read -r scheduler; do
        scheduler=$(echo "$scheduler" | tr -d '\r' | xargs)
        [[ -z "$scheduler" ]] && continue
        allowed_schedulers+=("$scheduler")
        allowed_scheduler_map["$scheduler"]=1
    done <<< "$allowed_scheduler_output"

    for scheduler in "${all_schedulers[@]}"; do
        if [[ -z "${allowed_scheduler_map[$scheduler]:-}" ]]; then
            missing_schedulers+=("$scheduler")
        fi
    done

    local default_scheduler_reference
    default_scheduler_reference=$(cat <<'EOF'
<table>
    <tr>
        <th>PD 版本</th>
        <th>部署时默认 scheduler 名称</th>
    </tr>
    <tr>
        <td>4.0.x</td>
        <td>balance-region-scheduler, balance-leader-scheduler, balance-hot-region-scheduler, label-scheduler</td>
    </tr>
    <tr>
        <td>5.4.x</td>
        <td>balance-region-scheduler, balance-leader-scheduler, balance-hot-region-scheduler</td>
    </tr>
    <tr>
        <td>6.5.x</td>
        <td>balance-region-scheduler, balance-leader-scheduler, balance-hot-region-scheduler, split-bucket-scheduler</td>
    </tr>
    <tr>
        <td>8.5.x</td>
        <td>balance-region-scheduler, balance-leader-scheduler, balance-hot-region-scheduler, evict-slow-store-scheduler, evict-stopping-store-scheduler</td>
    </tr>
</table>
EOF
)

    local allowed_scheduler_display missing_scheduler_display
    if [[ ${#allowed_schedulers[@]} -gt 0 ]]; then
        allowed_scheduler_display=$(printf "%s<br>" "${allowed_schedulers[@]}")
    else
        allowed_scheduler_display="无<br>"
    fi

    if [[ ${#missing_schedulers[@]} -gt 0 ]]; then
        missing_scheduler_display=$(printf "%s<br>" "${missing_schedulers[@]}")
    else
        missing_scheduler_display="无<br>"
    fi

    if [[ ${#all_schedulers[@]} -eq 0 ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "high" "3.3" "PD 调度器检查" "未查询到调度器状态"
        cat <<EOF >> "$OUTPUT_FILE"
            <tr>
                <td>检查存在的调度器</td>
                <td>根据 METRICS_SCHEMA.pd_scheduler_status 检查调度器启用状态</td>
                <td><span style='color:red;'>异常</span></td>
                <td>
                    <div style="padding: 8px;">
                        未查询到调度器状态，请确认 METRICS_SCHEMA.pd_scheduler_status 是否有数据。<br>
                        部署默认 scheduler 参考：<br>
                        $default_scheduler_reference
                    </div>
                </td>
            </tr>
EOF
    elif [[ ${#missing_schedulers[@]} -eq 0 ]]; then
        cat <<EOF >> "$OUTPUT_FILE"
            <tr>
                <td>检查存在的调度器</td>
                <td>全量调度器均处于 allow=1 状态</td>
                <td><span style='color:green;'>正常</span></td>
                <td>
                    <div style="padding: 8px;">
                        当前调度器：<br>$allowed_scheduler_display<br>
                        部署默认 scheduler 参考：<br>
                        $default_scheduler_reference
                    </div>
                </td>
            </tr>
EOF
    else
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "high" "3.3" "PD 调度器检查" "缺失或未启用: $(printf "%s<br>" "${missing_schedulers[@]}" | sed '$ s/<br>$//')"
        cat <<EOF >> "$OUTPUT_FILE"
            <tr>
                <td>检查存在的调度器</td>
                <td>全量调度器与 allow=1 调度器应一致</td>
                <td><span style='color:red;'>异常</span></td>
                <td>
                    <div style="padding: 8px;">
                        当前调度器：<br>$allowed_scheduler_display<br>
                        缺失或未启用的调度器：<br>$missing_scheduler_display<br>
                        部署默认 scheduler 参考：<br>
                        $default_scheduler_reference
                    </div>
                </td>
            </tr>
EOF
    fi
}

function check_gc_status() { 
    # 查询 GC 信息的 SQL
    local gc_sql="SELECT VARIABLE_NAME, VARIABLE_VALUE FROM mysql.tidb WHERE VARIABLE_NAME IN ('tikv_gc_last_run_time', 'tikv_gc_safe_point', 'tikv_gc_life_time');"
    local gc_info
    gc_info=$(run_sql "$gc_sql" --batch --skip-column-names 2>/dev/null)

    if [[ -z "$gc_info" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "high" "3.3" "GC 状态检查" "无法获取 GC 信息"
        cat <<EOF >> "$OUTPUT_FILE"
    <tr>
        <td>GC 是否正常</td>
        <td>tikv_gc_last_run_time 和 tikv_gc_safe_point 相差不超过 tikv_gc_life_time；<br>tikv_gc_last_run_time 和当前时间相差不超过 1 天</td>
        <td><span style='color:red;'>异常</span></td>
        <td>
            <div style="padding: 8px;">
                无法获取 GC 信息，请检查数据库连接
            </div>
        </td>
    </tr>
EOF
        return
    fi

    # 提取 GC 相关信息
    local gc_last_run_time gc_safe_point gc_life_time
    gc_last_run_time=$(echo "$gc_info" | awk '/tikv_gc_last_run_time/ {print $2}')
    gc_safe_point=$(echo "$gc_info" | awk '/tikv_gc_safe_point/ {print $2}')
    gc_life_time=$(echo "$gc_info" | awk '/tikv_gc_life_time/ {print $2}')
	original_gc_life_time="$gc_life_time" # 保存原始值

    # 转换 tikv_gc_life_time 为小时
    if [[ "$gc_life_time" == *h* ]]; then
        gc_life_time=$(echo "$gc_life_time" | sed 's/h//') # 如果是小时，直接去掉 "h"
    elif [[ "$gc_life_time" == *m* ]]; then
        gc_life_time=$(echo "$gc_life_time" | sed 's/m//' | awk '{print $1 / 60}') # 如果是分钟，换算成小时
    elif [[ "$gc_life_time" == *s* ]]; then
        gc_life_time=$(echo "$gc_life_time" | sed 's/s//' | awk '{print $1 / 3600}') # 如果是秒，换算成小时
    else
        gc_life_time=0 # 无法识别时设置为 0，表示异常
    fi


    if [[ -z "$gc_last_run_time" || -z "$gc_safe_point" || -z "$gc_life_time" ]]; then
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        report_issue "high" "3.3" "GC 状态检查" "GC 信息不完整"
        cat <<EOF >> "$OUTPUT_FILE"
    <tr>
        <td>GC 是否正常</td>
        <td>tikv_gc_last_run_time 和 tikv_gc_safe_point 相差不超过 tikv_gc_life_time；<br>tikv_gc_last_run_time 和当前时间相差不超过 1 天</td>
        <td><span style='color:red;'>异常</span></td>
        <td>
            <div style="padding: 8px;">
                GC 信息不完整，请检查数据库配置或状态
            </div>
        </td>
    </tr>
EOF
        return
    fi

    # 当前时间
    local current_time current_time_epoch
    current_time=$(date "+%Y-%m-%d %H:%M:%S")
    current_time_epoch=$(date -d "$current_time" +%s)

    # 转换 GC 时间为秒数
    local gc_last_run_time_epoch gc_safe_point_epoch
    gc_last_run_time_epoch=$(date -d "${gc_last_run_time//-/ }" +%s)
    gc_safe_point_epoch=$(date -d "${gc_safe_point//-/ }" +%s)

    # 时间差计算（以秒为单位）
    local diff_last_run_to_now diff_last_run_to_safe
    diff_last_run_to_now=$((current_time_epoch - gc_last_run_time_epoch))
    diff_last_run_to_safe=$((gc_last_run_time_epoch - gc_safe_point_epoch))

    # 转换时间差为天
    local diff_last_run_to_now_days diff_last_run_to_safe_days
    diff_last_run_to_now_days=$((diff_last_run_to_now / 86400))
    diff_last_run_to_safe_days=$((diff_last_run_to_safe / 86400))

    # 检查逻辑
    local gc_life_time_days
    gc_life_time_days=$(awk "BEGIN {print $gc_life_time / 24}") # 将小时转换为天，结果为浮点数

    if [[ $(awk "BEGIN {print ($diff_last_run_to_now_days <= 1)}") -eq 1 && \
          $(awk "BEGIN {print ($diff_last_run_to_safe_days <= $gc_life_time_days)}") -eq 1 ]]; then
        gc_status="正常"
        gc_description="GC 工作正常<br>tikv_gc_last_run_time: $gc_last_run_time<br>tikv_gc_safe_point: $gc_safe_point<br>变量参数 tidb_gc_life_time: $original_gc_life_time" # 使用原始值
    else
        gc_status="异常"
        gc_description="GC 异常：<br>"
        if [[ "$diff_last_run_to_now_days" -gt 1 ]]; then
            gc_description+="GC 被阻塞，tikv_gc_last_run_time 距当前时间超过 1 天<br>"
            report_issue "high" "3.3" "GC 状态检查" "GC 被阻塞，last_run_time 距当前超过 1 天"
        fi
        if [[ $(awk "BEGIN {print ($diff_last_run_to_safe_days > $gc_life_time_days)}") -eq 1 ]]; then
            gc_description+="变量参数 tidb_gc_life_time 设置过大，当前值为 ${original_gc_life_time} 小时<br>"
            report_issue "medium" "3.3" "GC 状态检查" "tidb_gc_life_time=${original_gc_life_time} 设置过大"
        fi
        gc_description+="tikv_gc_last_run_time: $gc_last_run_time<br>tikv_gc_safe_point: $gc_safe_point<br>变量参数 tidb_gc_life_time: $original_gc_life_time"
    fi


    # 输出到 HTML
    if [[ "$gc_status" == "异常" ]]; then
        # 增加错误计数
        ERROR_COUNT33=$((ERROR_COUNT33 + 1))
        cat <<EOF >> "$OUTPUT_FILE"
    <tr>
        <td>GC 是否正常</td>
        <td>tikv_gc_last_run_time 和 tikv_gc_safe_point 相差不超过 tikv_gc_life_time；<br>tikv_gc_last_run_time 和当前时间相差不超过 1 天</td>
        <td><span style='color:red;'>异常</span></td>
        <td>
            <div style="padding: 8px;">
                $gc_description
            </div>
        </td>
    </tr>
EOF
    else
        cat <<EOF >> "$OUTPUT_FILE"
    <tr>
        <td>GC 是否正常</td>
        <td>tikv_gc_last_run_time 和 tikv_gc_safe_point 相差不超过 tikv_gc_life_time；<br>tikv_gc_last_run_time 和当前时间相差不超过 1 天</td>
        <td><span style='color:green;'>正常</span></td>
        <td>
            <div style="padding: 8px;">
                $gc_description
            </div>
        </td>
    </tr>
EOF
    fi
}

###############################################################################
#  3.4 开发规范最佳实践检查函数
###############################################################################

# 检查开发规范最佳实践
function check_dev_best_practices() {

    # 初始化错误计数器
    ERROR_COUNT34=0
	
    local html_header="<h4 id=\"check34\">3.4 开发规范最佳实践检查</h4>
    <p style=\"color: red; font-weight: bold; margin-bottom: 10px;\">注意：异常情况按前500个字符截断展示。</p>
    <table>
        <tr>
            <th>检查条目</th>
            <th>整改类型</th>
            <th>最佳实践描述</th>
            <th>检查结果</th>
            <th>异常情况</th>
        </tr>"
    echo "$html_header" >> "$OUTPUT_FILE"
	
    	# 初始化 3.4 完整清单 CSV（带 BOM，Excel 打开中文不乱码）
    if [[ ! -f "$DEV_BP_CSV_FILE" ]]; then
        printf '\xEF\xBB\xBF' > "$DEV_BP_CSV_FILE"
        echo "\"检查条目\",\"整改类型\",\"最佳实践描述\",\"检查结果\",\"异常情况完整清单\"" >> "$DEV_BP_CSV_FILE"
    fi

    # 确保 condition 变量定义
    condition="1=1"

    local checks=(
"ON|强烈建议整改|建表规范|表|无主键或唯一键|表需要有主键或唯一键|select concat(table_schema, '.' , table_name) from          INFORMATION_SCHEMA.TABLES      where          (table_name,table_schema) not in (             select table_name,table_schema              from INFORMATION_SCHEMA.tidb_indexes              where NON_UNIQUE=0         )         and    $condition  and    TABLE_TYPE = 'BASE TABLE'    and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|强烈建议整改|建表规范|表|大表使用主键自增属性|写入量较大的表，应避免使用连续自增的值对主键进行填充。|select concat(c.table_schema, '.' , c.table_name) FROM                  (         select table_schema, table_name         FROM INFORMATION_SCHEMA.COLUMNS         WHERE              extra = 'auto_increment'             and $condition                          and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys')     ) c                   join INFORMATION_SCHEMA.tables t                  ON t.TABLE_SCHEMA = c.TABLE_SCHEMA                   AND t.table_name = c.TABLE_NAME          WHERE                                t.table_rows > 10000000;"
"ON|强烈建议整改|建表规范|表|使用外键|TiDB 仅部分支持外键约束功能，不建议使用。|select concat( table_schema, '.' , table_name) from      INFORMATION_SCHEMA.KEY_COLUMN_USAGE  where      $condition          and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA')     and REFERENCED_TABLE_NAME is not null;"
"ON|强烈建议整改|数据类型|字段|使用longblob|longblob 类型最大列长度为4G。但由于 TiDB 单列的限制，TiDB 中默认单列存储最大不超过 6 MiB，可通过配置项将该限制调整至 120 MiB。|select              concat( table_schema, '.' , table_name, '.' , COLUMN_NAME )         from              INFORMATION_SCHEMA.COLUMNS         where              column_type='longblob'             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|强烈建议整改|数据类型|字段|使用longtext|longtext最大列长度为4G。但由于 TiDB 单列的限制，TiDB 中默认单列存储最大不超过 6 MiB，可通过配置项将该限制调整至 120 MiB。|select              concat( table_schema, '.' , table_name, '.' , COLUMN_NAME )         from              INFORMATION_SCHEMA.COLUMNS         where              column_type='longtext'             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|强烈建议整改|数据类型|字段|使用TIMESTAMP|禁止使用 TIMESTAMP类型（TIMESTAMP 数据类型受 2038 年问题的影响）。|select              concat( table_schema, '.' , table_name, '.' , COLUMN_NAME )         from              INFORMATION_SCHEMA.COLUMNS         where              column_type='timestamp'             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|强烈建议整改|数据类型|字段|存储精度浮点数使用float 或 double|浮点类型推荐使用 DECIMAL 类型，float 和 double 在存储的时候，存在精度损失的问题，很可能在值的比较时，得到不正确的结果，不建议使用。|select              concat( table_schema, '.' , table_name, '.' , COLUMN_NAME )         from              INFORMATION_SCHEMA.COLUMNS         where              column_type in ('double','float')             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|强烈建议整改|命名规范|表|表名使用中文|表命名只能使用英文字母、数字、下划线。|select concat(             table_schema,             '.',             table_name         )  FROM      information_schema.tables  WHERE      $condition     and table_name not REGEXP'[A-z]'      and table_name not REGEXP'[0-9]'     AND TABLE_SCHEMA NOT IN (         'mysql',         'PERFORMANCE_SCHEMA',         'INFORMATION_SCHEMA',         'METRICS_SCHEMA'     );"
"ON|强烈建议整改|命名规范|字段|表字段名使用中文|字段命名只能使用英文字母、数字、下划线|select          concat(             table_schema,             '.',             table_name,             '.',             column_name         ) FROM      information_schema.columns  WHERE      $condition     and column_name not REGEXP'[A-z]'      and column_name not REGEXP'[0-9]'     AND TABLE_SCHEMA NOT IN (         'mysql',         'PERFORMANCE_SCHEMA',         'INFORMATION_SCHEMA',         'METRICS_SCHEMA' ,'sys'    );"
"ON|建议整改|建表规范|表|主键类型不为bigint|尽量不选择字符串列作为主键|select              concat( table_schema, '.' , table_name, '.' , COLUMN_NAME )         from              INFORMATION_SCHEMA.COLUMNS         where              data_type <>'bigint'             and column_key='PRI'             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|建议整改|建表规范|表|表级别字符集检查|表级别字符集建议使用utf8mb4或gbk|select concat(                     table_schema,                      '.' ,                      table_name                 ) from              INFORMATION_SCHEMA.TABLES         where              TABLE_COLLATION not in ('utf8mb4_bin','gbk_chinese_ci')             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|建议整改|建表规范|字段|字段级别字符集检查|字段级别字符集建议utf8mb4或gbk，字符序为utf8mb4_bin或gbk_chinese_ci|select concat(             table_schema,             '.',             table_name,             '.',             COLUMN_NAME,             ' CHARACTER_SET_NAME is ',             CHARACTER_SET_NAME,             ' COLLATION_NAME is ',             COLLATION_NAME         )  AS tmp FROM     INFORMATION_SCHEMA. COLUMNS WHERE     (         CHARACTER_SET_NAME not in ('utf8mb4','gbk')         OR COLLATION_NAME not in ('utf8mb4_bin','gbk_chinese_ci')     ) AND $condition AND TABLE_SCHEMA NOT IN (     'mysql',     'PERFORMANCE_SCHEMA',     'INFORMATION_SCHEMA',     'METRICS_SCHEMA' ,'sys');"
"ON|建议整改|建表规范|字段|设置NOT NULL无默认值|字段设置了NOT NULL需设置默认值|select      concat( table_schema, '.' , table_name, '.' , COLUMN_NAME ) from      INFORMATION_SCHEMA.COLUMNS where      is_nullable='NO'     and COLUMN_DEFAULT is NULL     and $condition     and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|建议整改|建表规范|表|表无注释|表需要有注释|select          concat(             table_schema,              '.' ,              table_name         )            from      INFORMATION_SCHEMA.tables where      table_comment=''     and $condition     and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|建议整改|建表规范|字段|字段无注释|字段需要有注释|select      concat( table_schema, '.' , table_name, '.' , COLUMN_NAME ) from      INFORMATION_SCHEMA.COLUMNS where      (COLUMN_COMMENT is null     or COLUMN_COMMENT = '')     and $condition     and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|建议整改|建表规范|表|表字段数超过80个|出于为性能考虑，尽量避免存储超宽表，表字段数不建议超过 80 个|select           concat(             table_schema,             '.',             table_name         ) from  (      SELECT         table_schema,table_name     FROM         information_schema.columns     where              $condition         and TABLE_SCHEMA NOT IN (             'mysql',             'PERFORMANCE_SCHEMA',             'INFORMATION_SCHEMA',             'METRICS_SCHEMA'  ,'sys'       )      group by table_schema,table_name      having count(1) > 80 ) t;"
"ON|建议整改|建表规范|表|表平均单行数据超过64k|出于为性能考虑，尽量避免存储超宽表，建议单行的总数据大小不要超过 64K|select      concat(             table_schema,             '.',             table_name         )  from      information_schema.tables  where      $condition     AND AVG_ROW_LENGTH > 65536     AND TABLE_SCHEMA NOT IN (         'mysql',         'PERFORMANCE_SCHEMA',         'INFORMATION_SCHEMA',         'METRICS_SCHEMA'  ,'sys'   );"
"ON|建议整改|建表规范|索引|存在冗余索引|避免冗余索引|select             concat(              a.table_schema,              '.' ,              a.table_name,              '索引' ,              a.index_name,             '和',             b.index_name,             '冗余'                   )      FROM  (  (  SELECT   information_schema . statistics . TABLE_SCHEMA  AS  table_schema ,   information_schema . statistics . TABLE_NAME  AS  table_name ,   information_schema . statistics . INDEX_NAME  AS  index_name ,  max(   information_schema . statistics . NON_UNIQUE   ) AS  non_unique ,  max(    IF (  isnull(   information_schema . statistics . SUB_PART   ),  0,  1  )  ) AS  subpart_exists ,  group_concat(   information_schema . statistics . COLUMN_NAME   ORDER BY   information_schema . statistics . SEQ_IN_INDEX  ASC SEPARATOR ','  ) AS  index_columns   FROM   information_schema . statistics   WHERE  (  (   information_schema . statistics . INDEX_TYPE  = 'BTREE'  )  AND $condition  )  GROUP BY   information_schema . statistics . TABLE_SCHEMA ,   information_schema . statistics . TABLE_NAME ,   information_schema . statistics . INDEX_NAME   ) a  JOIN (  SELECT   information_schema . statistics . TABLE_SCHEMA  AS  table_schema ,   information_schema . statistics . TABLE_NAME  AS  table_name ,   information_schema . statistics . INDEX_NAME  AS  index_name ,  max(   information_schema . statistics . NON_UNIQUE   ) AS  non_unique ,  max(    IF (  isnull(   information_schema . statistics . SUB_PART   ),  0,  1  )  ) AS  subpart_exists ,  group_concat(   information_schema . statistics . COLUMN_NAME   ORDER BY   information_schema . statistics . SEQ_IN_INDEX  ASC SEPARATOR ','  ) AS  index_columns   FROM   information_schema . statistics   WHERE  (  (   information_schema . statistics . INDEX_TYPE  = 'BTREE'  )  AND (   information_schema . statistics . TABLE_SCHEMA  NOT IN (  'mysql',  'sys',  'INFORMATION_SCHEMA',  'PERFORMANCE_SCHEMA'  )  )  )  GROUP BY   information_schema . statistics . TABLE_SCHEMA ,   information_schema . statistics . TABLE_NAME ,   information_schema . statistics . INDEX_NAME   ) b ON (  (  (  a. table_schema  = b. table_schema   )  AND (  a. table_name  = b. table_name   )  )  )  )  WHERE  (  (  a. index_name  <> b. index_name   )  AND (  (  (  a. index_columns  = b. index_columns   )  AND (  (  a. non_unique  > b. non_unique   )  OR (  (  a. non_unique  = b. non_unique   )  AND (    IF (  (a. index_name  = 'PRIMARY'),  '',  a. index_name   ) >  IF (  (b. index_name  = 'PRIMARY'),  '',  b. index_name   )  )  )  )  )  OR (  (  locate(  concat(a. index_columns , ','),  b. index_columns   ) = 1  )  AND (a. non_unique  = 1)  )  OR (  (  locate(  concat(b. index_columns , ','),  a. index_columns   ) = 1  )  AND (b. non_unique  = 0)  )  )  );"
"ON|建议整改|建表规范|索引|表索引个数超5个|单张表的索引数量控制在 5 个以内|select concat(                          table_schema,                           '.' ,                           table_name )          from      (     select          a.table_schema,         a.table_name,         count(*)      from          (             select distinct table_schema,table_name,key_name              from information_schema.tidb_indexes             where $condition         ) a     group by a.table_schema,a.table_name      having count(*)>5     ) t;"
"ON|建议整改|建表规范|索引|表索引字段个数超5个|索引中的字段数建议不超过 5 个|select      concat(             table_schema,             '.',             table_name,             '.',             KEY_NAME         ) as t from  (     select distinct         table_schema,         table_name,         KEY_NAME     from          information_schema.tidb_indexes       where          $condition         AND TABLE_SCHEMA NOT IN (             'mysql',             'PERFORMANCE_SCHEMA',             'INFORMATION_SCHEMA',             'METRICS_SCHEMA'  ,'sys'       )     group by TABLE_SCHEMA,table_name,KEY_NAME     having count(1) > 1 ) t;"
"ON|建议整改|建表规范|索引|唯一索引存在字段可为空|表需要有主键或者唯一索引，需要唯一索引所有字段非空（避免出现多条空值的重复记录）|select      concat(                          c.table_schema,                          '.',                          c.table_name,                          '.',                          c.COLUMN_NAME                  )  from      (         select              table_schema,             table_name,             column_name,             is_nullable         from              information_schema.columns         WHERE                $condition             AND TABLE_SCHEMA NOT IN (                 'mysql',                 'PERFORMANCE_SCHEMA',                 'INFORMATION_SCHEMA',                 'METRICS_SCHEMA'    ,'sys'         )             and is_nullable = 'YES'     ) c     join Information_Schema.Key_Column_Usage k     on          c.TABLE_SCHEMA = k.TABLE_SCHEMA         and c.TABLE_NAME = k.TABLE_NAME         and c.COLUMN_NAME = k.COLUMN_NAME;"
"ON|建议整改|数据类型|字段|使用blob或text|不推荐使用复杂的数据类型TEXT和BLOB|select              concat(                     table_schema,                      '.' ,                      table_name,                     '.' ,                     COLUMN_NAME)   from              INFORMATION_SCHEMA.COLUMNS         where              data_type in ( 'blob','text' )             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|建议整改|数据类型|字段|使用mediumtext|mediutext最大支持16M，TiDB 限制了单条 KV entry 不超过 6MiB。可以修改配置文件中的 txn-entry-size-limit 配置项进行调整，最大可以修改到 120MiB|select              concat( table_schema, '.' , table_name, '.' , COLUMN_NAME )         from              INFORMATION_SCHEMA.COLUMNS         where              column_type='mediumtext'             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|建议整改|数据类型|字段|使用enum、set类型|不建议使用 ENUM、SET 类型，尽量使用 TINYINT 来代替|select              concat( table_schema, '.' , table_name, '.' , COLUMN_NAME )         from              INFORMATION_SCHEMA.COLUMNS         where              column_type in ('enum','set')             and $condition             and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA','sys');"
"ON|建议整改|数据类型|字段|使用JSON类型|JSON在TiDB v6.5之前为实验特性，不建议生产环境使用|select      concat( table_schema, '.' , table_name, '.' , COLUMN_NAME ) from      INFORMATION_SCHEMA.COLUMNS where      data_type ='json'     and $condition     and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA');"
"ON|提示|建表规范|表|使用分区|分区表功能与运维特性在 v6.1 之后逐渐 GA 与完善，尽量保证当前版本 >= v6.1|select          concat(             table_schema,              '.' ,              table_name)     from      (         select distinct              table_schema, table_name         from              information_schema.PARTITIONS         where              partition_name is not null              and $condition                  and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA')     ) t;"
"ON|提示|命名规范|表|表名存在大写|表名建议小写|select          concat(                          table_schema,                           '.' ,                           table_name         )from      information_schema.tables  where      $condition      and CAST(table_NAME AS BINARY) RLIKE '[A-Z]'     and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA');"
"ON|提示|命名规范|字段|字段名存在大写|字段名建议小写|select      concat(                          table_schema,                           '.' ,                           table_name,                          '.' ,                          COLUMN_NAME                  ) from      information_schema.columns  where      $condition      and CAST(COLUMN_NAME AS BINARY) RLIKE '[A-Z]'     and TABLE_SCHEMA not in ('mysql','PERFORMANCE_SCHEMA','INFORMATION_SCHEMA','METRICS_SCHEMA');"
    )

    for check in "${checks[@]}"; do
        IFS='|' read -r status rectification_type category object_type check_item description sql <<< "$check"

        # 清理 SQL 中的换行、回车（可选）
        sql=$(echo "$sql" | tr -d '\n' | tr -d '\r')

        # 使用 run_sql 执行 SQL
        local result
        result=$(run_sql "$sql")
        local ret=$?  # 记录返回码

        if [[ $ret -ne 0 ]]; then
            # 如果 SQL 执行出错，在这里打印警告并跳过后续处理
            echo "Error executing SQL for $check_item. Skipping." >&2
            continue
        fi

        local check_result exception_info full_exception_info exception_display
        if [[ -n "$result" ]]; then
            check_result="<span style='color:red;'>异常</span>"
            ERROR_COUNT34=$((ERROR_COUNT34 + 1))
            local sev="low"
            # Map check_item to severity per inspection checklist
            if [[ "$check_item" == "使用外键" ]]; then
                sev="high"
            elif [[ "$check_item" == "无主键或唯一键" || "$check_item" == "大表使用主键自增属性" || "$check_item" == "使用longblob" || "$check_item" == "使用longtext" || "$check_item" == "使用TIMESTAMP" || "$check_item" == "存储精度浮点数使用float 或 double" || "$check_item" == "表名使用中文" || "$check_item" == "表字段名使用中文" || "$check_item" == "主键类型不为bigint" || "$check_item" == "表级别字符集检查" || "$check_item" == "字段级别字符集检查" ]]; then
                sev="medium"
            elif [[ "$check_item" == "设置NOT NULL无默认值" || "$check_item" == "表无注释" || "$check_item" == "字段无注释" || "$check_item" == "表字段数超过80个" || "$check_item" == "表平均单行数据超过64k" || "$check_item" == "存在冗余索引" || "$check_item" == "表索引个数超5个" || "$check_item" == "表索引字段个数超5个" || "$check_item" == "唯一索引存在字段可为空" || "$check_item" == "使用blob或text" || "$check_item" == "使用mediumtext" || "$check_item" == "使用enum、set类型" || "$check_item" == "使用JSON类型" ]]; then
                sev="low"
            elif [[ "$check_item" == "使用分区" || "$check_item" == "表名存在大写" || "$check_item" == "字段名存在大写" ]]; then
                sev="notice"
            else
                case "$rectification_type" in
                    强烈建议整改) sev="medium" ;;
                    建议整改) sev="low" ;;
                    提示) sev="notice" ;;
                esac
            fi
                report_issue "$sev" "3.4" "$check_item" "$description: $(echo "$result" | awk '{printf "%s<br>", $0}' | sed 's/<br>$//')"
        
            full_exception_info=$(echo "$result" | tr '\n' ',' | sed 's/,$//' | tr ',' '\n')
            exception_display="$full_exception_info"
            [[ ${#exception_display} -gt 500 ]] && exception_display="${exception_display:0:500}..."
            exception_info="<pre>$exception_display</pre>"
        else
            check_result="<span style='color:green;'>正常</span>"
            exception_info=""
            full_exception_info="无"
        fi

        cat <<EOF >> "$OUTPUT_FILE"
        <tr>
            <td>$check_item</td>
            <td>$rectification_type</td>
            <td>$description</td>
            <td>$check_result</td>
            <td>$exception_info</td>
        </tr>
EOF

    local csv_check_result
    if [[ -n "$result" ]]; then
        csv_check_result="异常"
    else
        csv_check_result="正常"
    fi
    
    echo "$(escape_csv "$check_item"),$(escape_csv "$rectification_type"),$(escape_csv "$description"),$(escape_csv "$csv_check_result"),$(escape_csv "$full_exception_info")" >> "$DEV_BP_CSV_FILE"

    done

    echo "</table>" >> "$OUTPUT_FILE"
	echo "检查信息已保存到 $OUTPUT_FILE"
	echo "3.4 开发规范最佳实践完整清单已保存到 $DEV_BP_CSV_FILE"
}

###############################################################################
#  3.5 数据库参数最佳实践检查
###############################################################################

ERROR_COUNT35=0

# (1) 解析指定区段的函数（改为"整行 == [...]"来匹配）
function parse_config_section() {
    local section="$1"
    local output_file="$2"

    # 这里使用 "$0 == \"[section]\"" 进行**字符串精确比对**
    awk -v section="$section" '
        BEGIN {
            found=0
            target = "[" section "]"
        }
        {
            # 如果匹配到精确行 [section]，found=1
            if ($0 == target) {
                found=1
                next
            }
            # 如果再遇到新的 [xxx]，说明离开此 section
            if (found==1 && $0 ~ /^\[/) {
                found=0
            }
            # 如果 still found==1 且不是注释/空行，就写到输出
            if (found==1 && !/^#/ && !/^[[:space:]]*$/) {
                line=$0
                sub(/#.*/, "", line)
                gsub(/^[ \t]+|[ \t]+$/, "", line)
                if (line != "") {
                    print line
                }
            }
        }
    ' "$CONFIG_FILE" > "$output_file"
}

# (2) 检查 [variables_params] 内容
function check_tidb_variables() {
    local result_ref="$1"
    local tmp_result=""
    
    parse_config_section "variables_params" "/tmp/variables_params.txt"
    
    declare -A standard_var_values
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        local key=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
        local value=$(echo "$line" | cut -d'=' -f2 | tr -d ' ')
        standard_var_values["$key"]="$value"
    done < /tmp/variables_params.txt
    
    rm -f /tmp/variables_params.txt
    
    for param in "${!standard_var_values[@]}"; do
        local standard_value="${standard_var_values[$param]}"
    
        # 修改后的 SQL 查询，CURRENT_VALUE 在 DEFAULT_VALUE 之前
        local query="SELECT VARIABLE_NAME, CURRENT_VALUE, DEFAULT_VALUE \
                     FROM INFORMATION_SCHEMA.VARIABLES_INFO \
                     WHERE LOWER(VARIABLE_NAME) = LOWER('$param');"
    
        local query_result
        query_result=$(run_sql "$query" 2>/dev/null)
    
        if [[ -n "$query_result" ]]; then
            local variable_name=$(echo "$query_result" | awk '{print $1}')
            local current_value=$(echo "$query_result" | awk '{print $2}')  # CURRENT_VALUE
            local default_value=$(echo "$query_result" | awk '{print $3}')  # DEFAULT_VALUE
    
            if [[ "${current_value,,}" != "${standard_value,,}" ]]; then
                ERROR_COUNT35=$((ERROR_COUNT35 + 1))
                report_issue "low" "3.5" "Variables: $variable_name" "当前=$current_value, 标准=$standard_value, 默认=$default_value"
                
                tmp_result+="<tr>
                    <td>TiDB</td>
                    <td>$variable_name</td>
                    <td>$default_value</td>
                    <td>$current_value</td>
                    <td>$standard_value</td>
                    <td><span style='color: red;'>否</span></td>
                </tr>"
            fi
        fi
    done
    
    eval "$result_ref=\"\$tmp_result\""
}




# (3) 检查 [tidb_config_params] 内容
function check_tidb_config() {
    local config_table_ref="$1"
    local instance_ref="$2"
    local tmp_result=""
    local -a tmp_instances=()
    
    parse_config_section "tidb_config_params" "/tmp/tidb_config_params.txt"
    
    declare -A standard_config_values
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        local key=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
        local value=$(echo "$line" | cut -d'=' -f2 | tr -d ' ')
        standard_config_values["$key"]="$value"
    done < /tmp/tidb_config_params.txt
    
    rm -f /tmp/tidb_config_params.txt
    
    # 获取所有相关配置
    local mysql_query="SELECT TYPE, INSTANCE, \`KEY\`, VALUE 
                       FROM INFORMATION_SCHEMA.CLUSTER_CONFIG;"
    
    run_sql "$mysql_query" \
          > /tmp/cluster_config.txt 2>/dev/null
    
    while IFS=$'\t' read -r component instance key current_value; do
        # 提取 IP 前缀
        local ip_prefix=$(echo "$instance" | sed -E 's/:[0-9]+$//')
    
        # 检查标准值
        local standard_val="${standard_config_values[$key]}"
        if [[ -n "$standard_val" && "${current_value,,}" != "${standard_val,,}" ]]; then
            local normalized_html="<span style='color: red;'>否</span>"
            local remark="-"

            if [[ "$key" == "new_collations_enabled_on_first_bootstrap" ]]; then
                normalized_html="<span style='color: #b45309;'>仅参考</span>"
                remark="此参数仅在集群首次初始化时生效，部署后无法变更，仅供参考。"
            else
                ERROR_COUNT35=$((ERROR_COUNT35 + 1))
                report_issue "low" "3.5" "Config: $key" "实例=$ip_prefix, 当前=$current_value, 标准=$standard_val"
            fi
    
            # 拼接 HTML 行
            tmp_result+="<tr>
                <td>$component</td>
                <td>$ip_prefix</td>
                <td>$key</td>
                <td>$current_value</td>
                <td>$standard_val</td>
                <td>$normalized_html</td>
                <td>$remark</td>
            </tr>"
        fi
    done < /tmp/cluster_config.txt
    
    rm -f /tmp/cluster_config.txt
    
    eval "$config_table_ref=\"\$tmp_result\""
    eval "$instance_ref=\"\${tmp_instances[*]}\""
}



# (4) 主逻辑：若 [modules] 中启用 check_db_params，则执行
function check_db_params() {
    local parameter_check_output=""
    check_tidb_variables parameter_check_output
    
    local config_check_output=""
    local selected_instances=""  # 这个变量现在可能不再需要，因为我们展示所有不标准的参数
    
    check_tidb_config config_check_output selected_instances
    
    cat <<EOF >> "$OUTPUT_FILE"
<h4 id="check35">3.5 数据库参数最佳实践检查</h4>
<h5>Variables</h5>
<table>
    <tr>
        <th>组件</th>
        <th>参数名</th>
        <th>默认值</th>
        <th>当前值</th>
        <th>标准化值</th>
        <th>是否标准化</th>
    </tr>
    $parameter_check_output
</table>

<h5>Config</h5>
<table>
    <tr>
        <th>组件</th>
        <th>实例</th>
        <th>参数名</th>
        <th>当前值</th>
        <th>标准化值</th>
        <th>是否标准化</th>
        <th>备注</th>
    </tr>
    $config_check_output
</table>
EOF
}

###############################################################################
#  3.6 统计信息检查函数
###############################################################################


check_stats_best_practices() {
    # 初始化 ERROR_COUNT36
    ERROR_COUNT36=0

    # 开始表格
    cat <<EOF >> "$OUTPUT_FILE"
<h4 id="check36">3.6 统计信息最佳实践检查</h4>
<p style="color: red; font-weight: bold; margin-bottom: 10px;">注意：异常情况按前500个字符截断展示。</p>
<table>
    <tr>
        <th>检查条目</th>
        <th>检查标准</th>
        <th>检查结果</th>
        <th>异常情况</th>
    </tr>
EOF

    # 所有检查项放在一个数组中，通过“|”分割
    # 格式： "检查项|检查标准|SQL语句"
    local stats_checks=(
        "是否存在统计信息收集失败的表|检查打印出最近5个统计信息收集失败的表|show analyze status where (table_schema,table_name) in (select table_schema,table_name from INFORMATION_SCHEMA.analyze_status where state!='finished' order by start_time desc limit 5);"
        "是否存在健康度小于90%的表|检查打印出健康度小于90%的表|SELECT CONCAT(t.table_schema, '.', t.table_name,',')  FROM information_schema.tables t INNER JOIN (SELECT table_id, IF(modify_count >= count, 0, (1 - modify_count / count) * 100) AS healthy, modify_count, count FROM mysql.stats_meta WHERE count != 0 HAVING healthy < 90 UNION ALL SELECT table_id, 0, modify_count, count FROM mysql.stats_meta WHERE count = 0 AND modify_count != 0) x ON t.tidb_table_id = x.table_id;"
        "是否存在没有直方图的表|检查打印出没有直方图的表|SELECT CONCAT(table_schema, '.', table_name, ',') AS db_table FROM information_schema.tables WHERE table_schema NOT IN ('INFORMATION_SCHEMA', 'METRICS_SCHEMA', 'PERFORMANCE_SCHEMA', 'test', 'mysql', 'sys') AND tidb_table_id NOT IN (SELECT DISTINCT table_id FROM mysql.stats_histograms);"
        "是否存在宽表没有设置收集策略|宽表(columns > 200)，建议设置正确的收集策略|select c.table_schema,c.table_name from (select table_schema,table_name,count(*) as cnt from information_schema.columns where table_schema not in ('INFORMATION_SCHEMA','METRICS_SCHEMA','PERFORMANCE_SCHEMA','test','mysql','sys') group by table_schema,table_name having cnt>200) c inner join information_schema.tables t on c.table_schema=t.table_schema and c.table_name=t.table_name left join mysql.analyze_options o on t.tidb_table_id=o.table_id where o.column_choice is null or o.column_choice in ('DEFAULT','ALL');"
        "是否存在分区表统计收集策略不合理|在动态分区裁剪模式，分区表(超过30个分区)，建议设置正确的收集策略|SELECT CONCAT(p.table_schema, '.', p.table_name, ',') AS db_table FROM (SELECT table_schema, table_name, COUNT(*) AS cnt FROM information_schema.partitions WHERE table_schema NOT IN ('INFORMATION_SCHEMA', 'METRICS_SCHEMA', 'PERFORMANCE_SCHEMA', 'test', 'mysql', 'sys') GROUP BY table_schema, table_name HAVING cnt > 30) p INNER JOIN information_schema.tables t ON p.table_schema = t.table_schema AND p.table_name = t.table_name LEFT JOIN mysql.analyze_options o ON t.tidb_table_id = o.table_id WHERE o.column_choice IS NULL OR o.column_choice IN ('DEFAULT', 'ALL');"
        "是否v1/v2统计信息并存|判断系统v1/v2统计信息混用|SELECT '存在混用' AS coexist FROM mysql.stats_histograms WHERE stats_ver = 1 AND EXISTS ( SELECT 1 FROM mysql.stats_histograms WHERE stats_ver = 2 ) LIMIT 1;"
        "是否存在无效表的统计信息|检查打印已删除的无效表的统计信息|select distinct table_id from mysql.stats_histograms h where h.table_id not in (select t.tidb_table_id from information_schema.tables t union all select p.TIDB_PARTITION_ID from information_schema.partitions p);"
        "是否存在被锁定统计信息的表|v6.5的锁定统计信息不建议使用，建议v8.1版本以上使用|select t.table_schema,t.table_name from mysql.stats_table_locked l inner join information_schema.tables t on l.table_id=t.tidb_table_id;"
		"是否存在普通表缺失统计信息|检查是否存在普通表缺失统计信息|WITH tb AS (SELECT table_schema, table_name, tidb_table_id FROM information_schema.tables WHERE table_schema NOT IN ('mysql','INFORMATION_SCHEMA','PERFORMANCE_SCHEMA','METRICS_SCHEMA') AND table_type = 'BASE TABLE' AND COALESCE(create_options,'') NOT LIKE '%partitioned%'), st AS (SELECT table_id, MAX(stats_ver) AS max_stats_ver FROM mysql.stats_histograms GROUP BY table_id) SELECT CONCAT(tb.table_schema, '.', tb.table_name) AS schema_table FROM tb LEFT JOIN st ON tb.tidb_table_id = st.table_id WHERE COALESCE(st.max_stats_ver, 0) = 0 ORDER BY tb.table_schema, tb.table_name;"
		"是否存在分区缺失partition统计信息|检查是否存在分区缺失partition统计信息|WITH pt AS (SELECT p.table_schema, p.table_name, p.partition_name, p.tidb_partition_id FROM information_schema.partitions p WHERE p.partition_name IS NOT NULL AND p.table_schema NOT IN ('mysql','INFORMATION_SCHEMA','PERFORMANCE_SCHEMA','METRICS_SCHEMA')), st AS (SELECT table_id, MAX(COALESCE(stats_ver, 0)) AS max_stats_ver FROM mysql.stats_histograms GROUP BY table_id) SELECT CONCAT(pt.table_schema, '.', pt.table_name, '.', pt.partition_name) AS partitioned_table FROM pt LEFT JOIN st ON pt.tidb_partition_id = st.table_id WHERE COALESCE(st.max_stats_ver, 0) = 0 ORDER BY pt.table_schema, pt.table_name, pt.partition_name;"
		"是否存在分区表缺失global统计信息|检查是否存在分区表缺失global统计信息|SELECT CONCAT(info2.tb_schema, '.', info2.tb_name, ',') AS schema_table FROM (SELECT info.tb_schema, info.tb_name, SUM(stats_ver) AS stats_version FROM (SELECT tb.TABLE_SCHEMA AS tb_schema, tb.TABLE_NAME AS tb_name, tb.tidb_table_id, sm.table_id, sm.hist_id, sm.version, sm.stats_ver FROM information_schema.tables tb LEFT JOIN mysql.stats_histograms sm ON tb.tidb_table_id = sm.table_id WHERE tb.TABLE_TYPE = 'BASE TABLE' AND tb.CREATE_OPTIONS = 'partitioned' AND tb.TABLE_SCHEMA NOT IN ('mysql','INFORMATION_SCHEMA','PERFORMANCE_SCHEMA','METRICS_SCHEMA')) info GROUP BY info.tb_schema, info.tb_name) info2 WHERE info2.stats_version = 0 OR info2.stats_version IS NULL ORDER BY info2.tb_schema, info2.tb_name;"
    )

    for check_line in "${stats_checks[@]}"; do
        IFS='|' read -r item standard query <<< "$check_line"

        # 2) 执行查询：用 run_sql 函数即可自动处理是否有 -p 参数
        local result
        result=$(run_sql "$query")

        # 根据结果填充检查结果和异常情况
        local check_result
        local abnormal
        if [[ -z "$result" ]]; then
            check_result="<span style='color: green;'>正常</span>"
            abnormal=""
        else
            check_result="<span style='color: red;'>异常</span>"
            local cleaned_result
            cleaned_result=$(echo "$result" | sed 's/,[[:space:]]*$//')
            local abnormal_display="$cleaned_result"
            [[ ${#abnormal_display} -gt 500 ]] && abnormal_display="${abnormal_display:0:500}..."
            abnormal="<pre>$abnormal_display</pre>"
            ERROR_COUNT36=$((ERROR_COUNT36 + 1))
            # Per-item severity mapping from inspection checklist
            local stats_sev="medium"
            case "$item" in
                是否存在健康度小于90%的表) stats_sev="notice" ;;
                是否存在统计信息收集失败的表|是否存在宽表没有设置收集策略|是否存在分区表统计收集策略不合理|是否存在被锁定统计信息的表) stats_sev="low" ;;
                是否存在没有直方图的表|是否v1/v2统计信息并存|是否存在无效表的统计信息|是否存在普通表缺失统计信息|是否存在分区缺失partition统计信息|是否存在分区表缺失global统计信息) stats_sev="medium" ;;
            esac
            report_issue "$stats_sev" "3.6" "$item" "$(echo "$cleaned_result" | awk '{printf "%s<br>", $0}' | sed 's/<br>$//')"
        fi

        # 将结果添加到表格中
        cat <<EOF >> "$OUTPUT_FILE"
    <tr>
        <td>$item</td>
        <td>$standard</td>
        <td>$check_result</td>
        <td>$abnormal</td>
    </tr>
EOF
    done

    # 结束表格
    cat <<EOF >> "$OUTPUT_FILE"
</table>
EOF
}

###############################################################################
#  3.7 系统配置最佳实践检查
###############################################################################
# 解析TiKV组件的数据目录以获取挂载点
function get_tikv_mount_points() {
    local cluster_name="$1"
    tiup cluster display "$cluster_name" 2>/dev/null | awk '
    BEGIN { tikv_flag=0; data_dir_idx=0 }
    /^ID[[:space:]]+Role/ {
        for (i = 1; i <= NF; i++) {
            if ($i == "Data" && $(i+1) == "Dir") { data_dir_idx = i; break }
        }
        tikv_flag=1
        next
    }
    /^[[:space:]]*$/ { tikv_flag=0 }
    tikv_flag && $2 == "tikv" && data_dir_idx > 0 {
        data_dir = $data_dir_idx
        # 提取挂载点，例如 /data/tidb-data/tikv-20166 -> /data
        split(data_dir, arr, "/")
        mount_point = "/" arr[2]
        mounts[mount_point] = 1
    }
    END {
        for (mp in mounts) {
            print mp
        }
    }'
}

# 获取所有TiKV挂载点，去重并用逗号分隔
TIKV_MOUNT_POINTS=$(get_tikv_mount_points "$CLUSTER_NAME" | sort | uniq | paste -sd "," -)

# 提取集群中所有TiKV组件所在的主机及其挂载点
declare -A HOST_TO_MOUNTS
while IFS=' ' read -r host data_dir; do
    mount_point=$(echo "$data_dir" | awk -F'/' '{print "/"$2}')
    HOST_TO_MOUNTS["$host"]+="$mount_point,"
done < <(tiup cluster display "$CLUSTER_NAME" 2>/dev/null | awk '
    BEGIN { tikv_flag=0; host_idx=0; data_dir_idx=0 }
    /^ID[[:space:]]+Role/ {
        for (i = 1; i <= NF; i++) {
            if ($i == "Host") { host_idx = i }
            if ($i == "Data" && $(i+1) == "Dir") { data_dir_idx = i }
        }
        tikv_flag=1
        next
    }
    /^[[:space:]]*$/ { tikv_flag=0 }
    tikv_flag && $2 == "tikv" && host_idx > 0 && data_dir_idx > 0 {
        print $host_idx, $data_dir_idx
    }
')

# 移除每个主机挂载点后多余的逗号
for host in "${!HOST_TO_MOUNTS[@]}"; do
    HOST_TO_MOUNTS["$host"]=$(echo "${HOST_TO_MOUNTS[$host]}" | sed 's/,$//')
done

# 生成主机与挂载点的对应关系文件
HOST_MOUNTS_FILE=$(mktemp)
for host in "${!HOST_TO_MOUNTS[@]}"; do
    echo "$host:${HOST_TO_MOUNTS[$host]}"
done > "$HOST_MOUNTS_FILE"

function check_sys_config() {
    echo "<h4 id=\"check37\">3.7 系统配置最佳实践检查</h4>" >> "$OUTPUT_FILE"
    
    # 插入检查表格
    cat <<'TABLE' >> "$OUTPUT_FILE"
<table>
    <tr>
        <th>检查条目</th>
        <th>检查标准</th>
    </tr>
    <tr>
        <td>检查磁盘挂载参数</td>
        <td>TiKV 磁盘的挂载参数含 <code>nodelalloc</code> 和 <code>noatime</code></td>
    </tr>
    <tr>
        <td>检查 swap 是否关闭</td>
        <td>关闭</td>
    </tr>
    <tr>
        <td>检查透明大页是否关闭</td>
        <td>关闭</td>
    </tr>
    <tr>
        <td>检查 TiDB 用户 ID 和组 ID 是否一致</td>
        <td>一致，且所有服务器 ID 相同</td>
    </tr>
    <tr>
        <td>TiDB 系统密码是否不过期</td>
        <td>有效期超过 9999 天</td>
    </tr>
    <tr>
        <td>时间同步是否正常</td>
        <td>NTP 或 Chrony 的时间同步正常</td>
    </tr>
    <tr>
        <td>检查 /etc/sysctl.conf 参数</td>
        <td>符合官网最佳实践</td>
    </tr>
    <tr>
        <td>检查 /etc/security/limits.conf 参数</td>
        <td>tidb nofile(soft/hard) ≥ 1000000，tidb soft stack ≥ 10240</td>
    </tr>
    <tr>
        <td>检查时区是否相同</td>
        <td>所有服务器时区一致</td>
    </tr>
    <tr>
        <td>检查CPU调频策略是否为performance</td>
        <td>scaling_governor = performance</td>
    </tr>
    <tr>
        <td>检查clocksource是否为tsc</td>
        <td>current_clocksource = tsc</td>
    </tr>
    <tr>
        <td>检查操作系统版本是否支持</td>
        <td>发行版 ID 在 TiDB 官方支持列表内</td>
    </tr>
    <tr>
        <td>检查操作系统版本是否相同</td>
        <td>各主机 PRETTY_NAME 一致</td>
    </tr>
    <tr>
        <td>检查操作系统内核是否相同</td>
        <td>各主机 uname -r 一致</td>
    </tr>
    <tr>
        <td>检查irqbalance服务是否开启</td>
        <td>irqbalance = active(running)</td>
    </tr>
</table>
TABLE
    
    # 添加空行和异常结果输出标题
    echo "<br>" >> "$OUTPUT_FILE"
    echo "<p>异常结果输出：</p>" >> "$OUTPUT_FILE"



# 在检查之前先初始化 HOST_EXCEPTIONS 数组和错误计数
declare -A HOST_EXCEPTIONS
# 3.7 跨主机一致性采集数组（key=host_ip）
declare -A TZ_BY_HOST OSPRETTY_BY_HOST KERNEL_BY_HOST
ERROR_COUNT37=0

# 遍历所有主机 IP，分别检查
for host_ip in $(echo "$HOST_IPS" | tr "," "\n"); do
    echo "    正在检查主机 $host_ip"
    host_errors=""  # 用于收集当前主机的所有异常


if [[ -n "${HOST_TO_MOUNTS[$host_ip]}" ]]; then
    # 从 HOST_TO_MOUNTS 数组中以逗号分隔获取挂载点列表
    IFS=',' read -ra MP_ARRAY <<< "${HOST_TO_MOUNTS[$host_ip]}"
    for mount_point in "${MP_ARRAY[@]}"; do
        # 通过 SSH 远程检查该挂载点是否挂载
        mounted=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$host_ip" "mountpoint -q '$mount_point' && echo yes || echo no")
        if [[ "$mounted" != "yes" ]]; then
            host_errors+="检查磁盘挂载参数|挂载点 $mount_point 未挂载<br>"
            report_issue "high" "3.7" "磁盘挂载" "主机=$host_ip, 挂载点 $mount_point 未挂载"
        else
            fstype=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$host_ip" "findmnt -no FSTYPE '$mount_point'" 2>/dev/null)
            if [[ "$fstype" != "ext4" ]]; then
                host_errors+="检查磁盘挂载参数|挂载点 $mount_point 文件系统类型错误: $fstype (应为 ext4)<br>"
                report_issue "high" "3.7" "磁盘挂载" "主机=$host_ip, 挂载点 $mount_point 文件系统=$fstype (应为 ext4)"
            fi
            mount_params=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$host_ip" "findmnt -no OPTIONS '$mount_point'" 2>/dev/null)
            # 缺少 noatime 挂载参数 → low
            if [[ ! "$mount_params" =~ noatime ]]; then
                host_errors+="检查磁盘挂载参数|挂载点 $mount_point 缺少 noatime 挂载参数: $mount_params<br>"
                report_issue "low" "3.7" "磁盘挂载" "主机=$host_ip, 挂载点 $mount_point 缺少 noatime: $mount_params"
            fi
            # 缺少 nodelalloc 挂载参数 → high
            if [[ ! "$mount_params" =~ nodelalloc ]]; then
                host_errors+="检查磁盘挂载参数|挂载点 $mount_point 缺少 nodelalloc 挂载参数: $mount_params<br>"
                report_issue "high" "3.7" "磁盘挂载" "主机=$host_ip, 挂载点 $mount_point 缺少 nodelalloc: $mount_params"
            fi
        fi
    done
fi



    # 检查 swap
    if [[ -x "$(command -v swapon)" ]]; then
        swap_status=$(swapon --show 2>/dev/null)
    else
        swap_status=$(cat /proc/swaps | tail -n +2 2>/dev/null || echo "")
    fi
    if [[ -n $swap_status ]]; then
        host_errors+="检查 swap 是否关闭|swap 未关闭: $swap_status<br>"
        report_issue "high" "3.7" "swap 检查" "主机=$host_ip, swap 未关闭"
    fi

    # 检查透明大页：仅判断运行时是否为 [never]（与 tiup cluster check 一致）
THP_STATUS=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$host_ip" "cat /sys/kernel/mm/transparent_hugepage/enabled" 2>/dev/null || echo "未检测到透明大页配置")

if [[ "$THP_STATUS" == *"[never]"* ]]; then
    :
else
    host_errors+="检查透明大页是否关闭|透明大页未禁用: THP_STATUS=$THP_STATUS<br>"
    report_issue "high" "3.7" "透明大页" "主机=$host_ip, THP=$THP_STATUS"
fi


    # 检查 TiDB 用户 ID 和组 ID
    tidb_uid=$(id -u tidb 2>/dev/null || echo "不存在")
    tidb_gid=$(id -g tidb 2>/dev/null || echo "不存在")
    if [[ "$tidb_uid" == "不存在" || "$tidb_gid" == "不存在" ]]; then
        host_errors+="检查 TiDB 用户 ID 和组 ID 是否一致|用户 tidb 不存在<br>"
        report_issue "low" "3.7" "TiDB UID/GID" "主机=$host_ip, 用户 tidb 不存在"
    elif [[ "$tidb_uid" -ne "$tidb_gid" ]]; then
        host_errors+="检查 TiDB 用户 ID 和组 ID 是否一致|UID=$tidb_uid, GID=$tidb_gid 不一致<br>"
        report_issue "low" "3.7" "TiDB UID/GID" "主机=$host_ip, UID=$tidb_uid, GID=$tidb_gid 不一致"
    fi

    # 检查 TiDB 密码有效期
    max_days=$(chage -l tidb 2>/dev/null | grep "Maximum number of days between password change" | awk -F: '{print $2}' | tr -d ' ')
    if [[ -z $max_days || "$max_days" -le 9999 ]]; then
        host_errors+="TiDB 系统密码是否不过期|密码有效期不足 9999 天，当前为 $max_days 天<br>"
        report_issue "notice" "3.7" "TiDB 密码过期" "主机=$host_ip, 有效期 $max_days 天 < 9999"
    fi

    # 检查时间同步
    if systemctl is-active --quiet ntpd; then
        ntp_status=$(ntpstat 2>/dev/null)
        if [[ $ntp_status != *"synchronised to NTP server"* ]]; then
            host_errors+="时间同步是否正常|NTP 未正常同步<br>"
            report_issue "critical" "3.7" "时间同步" "主机=$host_ip, NTP 未正常同步"
        fi
    elif systemctl is-active --quiet chronyd; then
        leap_status=$(chronyc tracking | grep "Leap status" || true)
        if [[ $leap_status != *"Normal"* ]]; then
            host_errors+="时间同步是否正常|Chrony 状态异常<br>"
            report_issue "critical" "3.7" "时间同步" "主机=$host_ip, Chrony 状态异常"
        fi
    else
        host_errors+="时间同步是否正常|未检测到 NTP 或 Chrony 服务运行<br>"
        report_issue "critical" "3.7" "时间同步" "主机=$host_ip, 未检测到 NTP/Chrony"
    fi

    # sysctl.conf 参数检查 —— 将错误追加到 host_errors 中
    declare -A sysctl_params=(
        ["fs.file-max"]="1000000"
        ["net.core.somaxconn"]="32768"
        ["net.ipv4.tcp_tw_recycle"]="0"
        ["net.ipv4.tcp_syncookies"]="0"
        ["vm.overcommit_memory"]="1"
        ["vm.min_free_kbytes"]="1048576"
    )
    for param in "${!sysctl_params[@]}"; do
        expected_value="${sysctl_params[$param]}"
        actual_value=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$host_ip" "bash -l -c 'sysctl -n $param'" 2>/dev/null || echo "未设置")
        # net.ipv4.tcp_tw_recycle 在 kernel 4.12+ 已移除，不存在即为已禁用，视为符合
        if [[ "$param" == "net.ipv4.tcp_tw_recycle" && "$actual_value" == "未设置" ]]; then
            continue
        fi

        # vm.min_free_kbytes 使用下限检查逻辑：应 >= 1048576
        if [[ "$param" == "vm.min_free_kbytes" ]]; then
            if is_number "$actual_value" && (( actual_value < expected_value )); then
                host_errors+="检查 /etc/sysctl.conf 参数|$param 设置过低: 应不低于 $expected_value, 实际值 $actual_value<br>"
                report_issue "high" "3.7" "sysctl.conf" "主机=$host_ip, $param: 应不低于 $expected_value, 实际=$actual_value"
            fi
        # 其他参数使用精确匹配逻辑
        elif [[ "$actual_value" != "$expected_value" ]]; then
            host_errors+="检查 /etc/sysctl.conf 参数|$param: 期望值 $expected_value，实际值 $actual_value<br>"
            report_issue "high" "3.7" "sysctl.conf" "主机=$host_ip, $param: 期望=$expected_value, 实际=$actual_value"
        fi
    done

    # limits.conf 参数检查 —— 低于下限即告警（格式: ["参数"]="下限值"）
    declare -A limits_params=(
        ["tidb soft nofile"]="1000000"
        ["tidb hard nofile"]="1000000"
        ["tidb soft stack"]="10240"
    )
    for param in "${!limits_params[@]}"; do
        min_value="${limits_params[$param]}"
        search_pattern=$(echo "$param" | awk '{for(i=2;i<=NF;i++) printf "%s\\s+", $i}' | sed 's/\\s+$//')
        regex="^\s*tidb\s+${search_pattern}\s+([0-9]+)"
        matches=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$host_ip" "grep -P '$regex' /etc/security/limits.conf" | awk '{print $NF}')
        if [[ -z "$matches" ]]; then
            host_errors+="检查 /etc/security/limits.conf 参数|$param 未设置（应不低于 $min_value）<br>"
            report_issue "high" "3.7" "limits.conf" "主机=$host_ip, $param 未设置（应不低于 $min_value）"
        else
            while IFS= read -r value; do
                if is_number "$value" && (( value < min_value )); then
                    host_errors+="检查 /etc/security/limits.conf 参数|$param 设置过低: 应不低于 $min_value, 实际值 $value<br>"
                    report_issue "high" "3.7" "limits.conf" "主机=$host_ip, $param: 应不低于 $min_value, 实际=$value"
                fi
            done <<< "$matches"
        fi
    done

    # ---- 3.7 系统配置补充检查：每台主机一次 SSH 采集多项指标 ----
    sys_raw=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$host_ip" \
        'tz=$(timedatectl show -p Timezone --value 2>/dev/null); [ -z "$tz" ] && tz=$(cat /etc/timezone 2>/dev/null); [ -z "$tz" ] && tz=$(date +%Z 2>/dev/null); gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null); cs=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null); irq=$(systemctl is-active irqbalance 2>/dev/null); osid=""; ospretty=""; if [ -f /etc/os-release ]; then . /etc/os-release; osid=$ID; ospretty=$PRETTY_NAME; fi; kr=$(uname -r 2>/dev/null); printf "%s|%s|%s|%s|%s|%s|%s\n" "$tz" "$gov" "$cs" "$irq" "$osid" "$ospretty" "$kr"' 2>/dev/null)
    IFS='|' read -r _tz _gov _cs _irq _osid _ospretty _kr <<<"$sys_raw"
    _tz="${_tz// /}"; _osid="${_osid//\"/}"
    TZ_BY_HOST["$host_ip"]="${_tz:-未知}"
    OSPRETTY_BY_HOST["$host_ip"]="${_ospretty:-未知}"
    KERNEL_BY_HOST["$host_ip"]="${_kr:-未知}"

    # CPU 调频策略是否为 performance
    if [[ -n "$_gov" && "$_gov" != "performance" ]]; then
        host_errors+="检查CPU调频策略是否为performance|scaling_governor=$_gov (应为 performance)<br>"
        report_issue "high" "3.7" "CPU 调频策略" "主机=$host_ip, scaling_governor=$_gov (应为 performance)"
    fi
    # clocksource 是否为 tsc
    if [[ -n "$_cs" && "$_cs" != "tsc" ]]; then
        host_errors+="检查clocksource是否为tsc|current_clocksource=$_cs (应为 tsc)<br>"
        report_issue "high" "3.7" "clocksource" "主机=$host_ip, current_clocksource=$_cs (应为 tsc)"
    fi
    # irqbalance 服务是否开启
    if [[ -n "$_irq" && "$_irq" != "active" ]]; then
        host_errors+="检查irqbalance服务是否开启|irqbalance 状态=$_irq (应为 active)<br>"
        report_issue "medium" "3.7" "irqbalance" "主机=$host_ip, irqbalance=$_irq (应为 active)"
    fi
    # 操作系统版本是否支持
    _supported_os="centos rhel rocky rockylinux almalinux ol oraclelinux openeuler euleros ubuntu debian amzn kylin kylinlinux uos uniontech anolis tlinux tencentos fedora bclinux neokylin"
    if [[ -n "$_osid" ]] && ! echo " $_supported_os " | grep -q " $_osid "; then
        host_errors+="检查操作系统版本是否支持|发行版 ID=$_osid 不在 TiDB 官方支持列表<br>"
        report_issue "high" "3.7" "操作系统版本支持" "主机=$host_ip, OS ID=$_osid 不在官方支持列表"
    fi

    # 保存该主机的异常信息到 HOST_EXCEPTIONS 数组
    HOST_EXCEPTIONS["$host_ip"]="$host_errors"
	
	# 计算当前主机错误数量并累加
    ERRORS=$(echo "$host_errors" | grep -o "<br>" | wc -l)
    ERROR_COUNT37=$((ERROR_COUNT37 + ERRORS))
done

# ---- 3.7 跨主机一致性检查 ----
cluster_errors=""
# 时区是否相同
_tz_set=$(printf '%s\n' "${TZ_BY_HOST[@]}" | grep -v '^未知$' | sort -u)
if [[ $(echo "$_tz_set" | grep -c .) -gt 1 ]]; then
    _tz_detail=$(for _h in "${!TZ_BY_HOST[@]}"; do printf '%s=%s ' "$_h" "${TZ_BY_HOST[$_h]}"; done)
    cluster_errors+="检查时区是否相同|各主机时区不一致: $_tz_detail<br>"
    report_issue "medium" "3.7" "时区是否相同" "各主机时区不一致: $_tz_detail"
    ERROR_COUNT37=$((ERROR_COUNT37 + 1))
fi
# 操作系统版本是否相同
_os_set=$(printf '%s\n' "${OSPRETTY_BY_HOST[@]}" | grep -v '^未知$' | sort -u)
if [[ $(echo "$_os_set" | grep -c .) -gt 1 ]]; then
    _os_detail=$(for _h in "${!OSPRETTY_BY_HOST[@]}"; do printf '%s=%s ' "$_h" "${OSPRETTY_BY_HOST[$_h]}"; done)
    cluster_errors+="检查操作系统版本是否相同|各主机 OS 版本不一致: $_os_detail<br>"
    report_issue "notice" "3.7" "操作系统版本是否相同" "各主机 OS 版本不一致: $_os_detail"
    ERROR_COUNT37=$((ERROR_COUNT37 + 1))
fi
# 操作系统内核是否相同
_kr_set=$(printf '%s\n' "${KERNEL_BY_HOST[@]}" | grep -v '^未知$' | sort -u)
if [[ $(echo "$_kr_set" | grep -c .) -gt 1 ]]; then
    _kr_detail=$(for _h in "${!KERNEL_BY_HOST[@]}"; do printf '%s=%s ' "$_h" "${KERNEL_BY_HOST[$_h]}"; done)
    cluster_errors+="检查操作系统内核是否相同|各主机内核不一致: $_kr_detail<br>"
    report_issue "notice" "3.7" "操作系统内核是否相同" "各主机内核不一致: $_kr_detail"
    ERROR_COUNT37=$((ERROR_COUNT37 + 1))
fi
# 跨主机异常写入异常表，保持与异常计数一致
if [[ -n "$cluster_errors" ]]; then
    HOST_EXCEPTIONS["集群(跨主机)"]="$cluster_errors"
fi



# 将异常信息添加到HTML报告中
if [[ ${#HOST_EXCEPTIONS[@]} -gt 0 ]]; then
    cat <<EOF >> "$OUTPUT_FILE"
<table>
    <tr>
        <th>IP地址</th>
        <th>异常描述</th>
    </tr>
EOF

    for host_ip in "${!HOST_EXCEPTIONS[@]}"; do
        EXCEPTION_DESC=$(echo -e "${HOST_EXCEPTIONS[$host_ip]}" | sed ':a;N;$!ba;s/\n//g')
        echo "<tr>
    <td>$host_ip</td>
    <td class=\"error\">$EXCEPTION_DESC</td>
</tr>" >> "$OUTPUT_FILE"
    done

    cat <<EOF >> "$OUTPUT_FILE"
</table>
EOF
else
    echo "<p>所有主机均未检测到异常。</p>" >> "$OUTPUT_FILE"
fi

}

###############################################################################
#  3.8 crontab 情况检查函数
###############################################################################

function check_crontab() {
    echo "<h4 id=\"check38\">3.8 crontab 情况</h4>" >> "$OUTPUT_FILE"
    echo "<table>" >> "$OUTPUT_FILE"
    echo "<tr><th>IP 地址</th><th>用户</th><th>crontab 内容</th></tr>" >> "$OUTPUT_FILE"

    IFS=',' read -r -a IP_ARRAY <<< "$HOST_IPS"

    for IP in "${IP_ARRAY[@]}"; do
        echo "    正在检查主机 $IP" 

        # 获取 crontab 内容
        CRONTAB_CONTENT=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$IP" "crontab -l 2>/dev/null")

        # 如果 crontab 内容为空，则设置为 "-".
        if [[ -z "$CRONTAB_CONTENT" ]]; then
            CRONTAB_CONTENT="-"
        fi

        # 如果 SSH 命令失败，也显示为无法获取
        if [[ $? -ne 0 ]]; then
            CRONTAB_CONTENT="无法获取 crontab 内容"
        fi

        # 将结果写入 HTML 文件
        echo "<tr><td>$IP</td><td>$OS_USER</td><td>$CRONTAB_CONTENT</td></tr>" >> "$OUTPUT_FILE"
    done

    echo "</table>" >> "$OUTPUT_FILE"
}



###############################################################################
#  3.9 dmesg 日志检查函数
###############################################################################
function check_dmesg_logs() { 
    # 初始化错误计数器
    ERROR_COUNT39=0

    echo "<h4 id=\"check39\">3.9 dmesg 日志</h4>" >> "$OUTPUT_FILE"
    echo "<p class=\"review-note\">注：本项展示最近 1 周内 dmesg 日志的后 20 行信息，仅供巡检参考。</p>" >> "$OUTPUT_FILE"
    echo "<table>" >> "$OUTPUT_FILE"
    echo "    <tr>" >> "$OUTPUT_FILE"
        echo "        <th>IP 地址</th>" >> "$OUTPUT_FILE"
        echo "        <th>日志状态</th>" >> "$OUTPUT_FILE"
        echo "        <th>日志摘要</th>" >> "$OUTPUT_FILE"
    echo "    </tr>" >> "$OUTPUT_FILE"

    IFS=',' read -ra ADDR <<< "$HOST_IPS"
    for ip in "${ADDR[@]}"; do
        # 去除 IP 地址前后的空格
        ip=$(echo "$ip" | xargs)

        # 输出“正在检查主机”并保持适当的缩进
        echo "    正在检查主机 $ip"  # 增加缩进

        # SSH 到主机并获取最近 1 周内的 dmesg 日志后 20 行，转换为人类可读时间
        dmesg_output=$(ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$OS_USER@$ip" "bash -s" << 'EOF'
            # 获取当前时间戳和系统启动时间（单位：秒）
            current_time=$(date +%s)
            window_seconds=$((7 * 24 * 3600))
            boot_time=$(awk '{print int($1)}' /proc/uptime)
            system_boot_time=$((current_time - boot_time))

            # 计算最近 1 周时间窗起点
            window_start_time=$((current_time - window_seconds))

            # 定义最小的 dmesg 时间戳（相对于系统启动时间的秒数）
            min_dmesg_time=$((window_start_time - system_boot_time))

            # 从 dmesg 中获取最近的 2000 行日志，再筛选最近 1 周内的后 20 行
            dmesg | tail -n 2000 | awk -v min_time="$min_dmesg_time" -v boot_time="$system_boot_time" -v window_start_time="$window_start_time" '
            {
                if (match($0, /^\[ *([0-9\.]+)\] (.*)/, arr)) {
                    dmesg_time = arr[1]
                    msg = arr[2]
                    msg_time = boot_time + dmesg_time
                    if (msg_time >= window_start_time) {
                        # 将时间戳转换为整数，避免科学计数法表示
                        msg_time_int = sprintf("%.0f", msg_time)
                        # 将时间戳转换为人类可读的格式
                        cmd = "date -d @" msg_time_int " \"+%Y-%m-%d %H:%M:%S\""
                        cmd | getline human_time
                        close(cmd)
                        print human_time " " msg
                    }
                }
            }
            ' | tail -n 20
EOF
        )

        # 输出最近 1 周 dmesg 后 20 行信息
        if [ -n "$dmesg_output" ]; then
            exception_status="信息"
            exception_summary="$dmesg_output"
            # 转义 HTML 特殊字符
            exception_summary=$(echo "$exception_summary" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
            # 将换行符替换为 <br>
            exception_summary=$(echo "$exception_summary" | sed ':a;N;$!ba;s/\n/<br>/g')

            # 输出到 HTML 表格
            echo "    <tr>" >> "$OUTPUT_FILE"
            echo "        <td>$ip</td>" >> "$OUTPUT_FILE"
            echo "        <td><span style=\"color:blue;\">$exception_status</span></td>" >> "$OUTPUT_FILE"
            echo "        <td>$exception_summary</td>" >> "$OUTPUT_FILE"
            echo "    </tr>" >> "$OUTPUT_FILE"
        fi
    done

    echo "</table>" >> "$OUTPUT_FILE"
}

###############################################################################
#  3.10 数据库的错误日志统计函数
###############################################################################


function check_db_error_logs() {
    cat <<EOF >> "$OUTPUT_FILE"
<h4 id="check310">3.10 数据库的错误日志统计</h4>

<table>
    <tr>
        <th>IP 地址</th>
        <th>组件</th>
        <th>错误日志数量</th>
    </tr>
EOF

# 获取 TiDB 实例的日志文件路径，使用 run_sql 替代 mysql 查询
LOG_INFO=$(run_sql "SELECT instance, value FROM information_schema.cluster_config WHERE type='tidb' AND \`key\`='log.file.filename';")

IFS=$'\n'
for line in $LOG_INFO; do
    INSTANCE=$(echo "$line" | awk -F'\t' '{print $1}')
    LOG_FILE=$(echo "$line" | awk -F'\t' '{print $2}')
    # 获取 IP 地址
    IP=${INSTANCE%%:*}
    COMPONENT="tidb-server"

    # 输出“正在检查主机”并保持适当的缩进
    echo "    正在检查主机 $IP"  # 增加缩进

    # 检查日志文件是否存在
    REMOTE_RESULT=$(ssh -i "$SSH_KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=5 \
        -o LogLevel=ERROR \
        "$OS_USER@$IP" "
    if [ -f '$LOG_FILE' ]; then
        START_TIME=\$(head -1 '$LOG_FILE' | sed -E 's/^\\[([^]]+)\\].*/\\1/')
        END_TIME=\$(tail -1 '$LOG_FILE' | sed -E 's/^\\[([^]]+)\\].*/\\1/')
        ERROR_COUNT=\$(grep -c '\\[ERROR\\]' '$LOG_FILE')
        printf 'exists\t%s\t%s\t%s\n' \"\$START_TIME\" \"\$END_TIME\" \"\$ERROR_COUNT\"
    else
        printf 'not_exists\tN/A\tN/A\tN/A\n'
    fi
    ")
    
    LOG_EXISTS=$(echo "$REMOTE_RESULT" | awk -F'\t' '{print $1}')
    START_TIME=$(echo "$REMOTE_RESULT" | awk -F'\t' '{print $2}')
    END_TIME=$(echo "$REMOTE_RESULT" | awk -F'\t' '{print $3}')
    ERROR_COUNT=$(echo "$REMOTE_RESULT" | awk -F'\t' '{print $4}')
    
    if [[ "$LOG_EXISTS" != "exists" ]]; then
        START_TIME="N/A"
        END_TIME="N/A"
        ERROR_COUNT="N/A"
    fi

    # 将结果添加到报告中
    cat <<EOF >> "$OUTPUT_FILE"
    <tr>
        <td>$IP</td>
        <td>$COMPONENT</td>
        <td>
            分析的日志为 $LOG_FILE<br>
            日志的时间范围：$START_TIME - $END_TIME<br>
            [ERROR] 类型报错有 $ERROR_COUNT 条
        </td>
    </tr>
EOF

done

# 添加表格结束标签
cat <<EOF >> "$OUTPUT_FILE"
</table>
EOF
}


###############################################################################
# 3.11 用户对象占用空间分布函数
###############################################################################

function check_user_space() {
# 查询 schema 数据
SCHEMA_QUERY="SELECT TABLE_SCHEMA, ROUND(SUM(index_length) / 1024 / 1024 / 1024, 2) AS index_length_GB, ROUND(SUM(data_length) / 1024 / 1024 / 1024, 2) AS data_length_GB, ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS total_GB FROM information_schema.tables WHERE TABLE_SCHEMA NOT IN ('METRICS_SCHEMA', 'PERFORMANCE_SCHEMA', 'INFORMATION_SCHEMA', 'mysql') GROUP BY TABLE_SCHEMA;"

# 查询 Top 10 table 数据
TOP10_QUERY="SELECT base.schema_name, base.table_name, base.rows_count, cols.column_count, base.size_GB FROM (SELECT TABLE_SCHEMA AS schema_name, TABLE_NAME AS table_name, TABLE_ROWS AS rows_count, ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024 / 1024, 2) AS size_GB FROM information_schema.tables WHERE TABLE_SCHEMA NOT IN ('METRICS_SCHEMA', 'PERFORMANCE_SCHEMA', 'INFORMATION_SCHEMA', 'mysql')) AS base LEFT JOIN (SELECT TABLE_SCHEMA AS schema_name, TABLE_NAME AS table_name, COUNT(COLUMN_NAME) AS column_count FROM information_schema.columns GROUP BY TABLE_SCHEMA, TABLE_NAME) AS cols ON base.schema_name = cols.schema_name AND base.table_name = cols.table_name ORDER BY base.size_GB DESC LIMIT 10;"

# 执行查询并获取结果
SCHEMA_DATA=$(run_sql "$SCHEMA_QUERY" -s -N 2>/dev/null)
TOP10_DATA=$(run_sql "$TOP10_QUERY" -s -N 2>/dev/null)

# 输出 HTML 表格
cat <<EOF >> "$OUTPUT_FILE"
<h4 id="check311">3.11 用户对象占用空间分布</h4>
<h5>schema</h5>
<table>
    <tr>
        <th>schema_name</th>
        <th>index_length_GB</th>
        <th>data_length_GB</th>
        <th>total_GB</th>
    </tr>
EOF

# 填充 schema 数据
if [[ -n "$SCHEMA_DATA" ]]; then
    echo "$SCHEMA_DATA" | while IFS=$'\t' read -r schema_name index_length_GB data_length_GB total_GB; do
        echo "    <tr><td>$schema_name</td><td>$index_length_GB</td><td>$data_length_GB</td><td>$total_GB</td></tr>" >> "$OUTPUT_FILE"
    done
fi

# 关闭 schema 表格
cat <<EOF >> "$OUTPUT_FILE"
</table>

<h5>Top 10 table</h5>
<table>
    <tr>
        <th>schema_name</th>
        <th>table_name</th>
        <th>rows_count</th>
        <th>column_count</th>
        <th>size(GB)</th>
    </tr>
EOF

# 填充 Top 10 table 数据
if [[ -n "$TOP10_DATA" ]]; then
    echo "$TOP10_DATA" | while IFS=$'\t' read -r schema_name table_name rows_count column_count size; do
        echo "    <tr><td>$schema_name</td><td>$table_name</td><td>$rows_count</td><td>$column_count</td><td>$size</td></tr>" >> "$OUTPUT_FILE"
    done
fi

# 关闭 Top 10 table 表格
cat <<EOF >> "$OUTPUT_FILE"
</table>
EOF
}



###############################################################################
# 服务 4.1/4.2/4.3
# 通用的 Prometheus 查询函数：获取 CPU 使用情况
###############################################################################
function fetch_avg_max_cpu() {
    local avg_query="$1"
    local max_query="$2"
    local avg_response max_response
    avg_response=$(curl -s -G "http://$PROME_ADDR/api/v1/query" --data-urlencode "query=$avg_query")
    max_response=$(curl -s -G "http://$PROME_ADDR/api/v1/query" --data-urlencode "query=$max_query")

    declare -A avg_map
    declare -A max_map

    if echo "$avg_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        while IFS=$'\t' read -r inst val; do
            avg_map["$inst"]="$val"
        done < <(
            echo "$avg_response" | jq -r '.data.result[] | [.metric.instance, (.value[1] | (tonumber*100))] | @tsv'
        )
    fi

    if echo "$max_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        while IFS=$'\t' read -r inst val; do
            max_map["$inst"]="$val"
        done < <(
            echo "$max_response" | jq -r '.data.result[] | [.metric.instance, (.value[1] | (tonumber*100))] | @tsv'
        )
    fi

    for inst in "${!avg_map[@]}"; do
        local a="${avg_map[$inst]}"
        local m="${max_map[$inst]:-0}"
        printf "%s\t%.2f\t%.2f\n" "$inst" "$a" "$m"
    done
}

###############################################################################
# 服务 4.2
# 获取 TiDB memory 参数的函数
###############################################################################
function get_tidb_memory_param() {
    local instance="$1"
    local sql_output
    sql_output=$(run_sql "select MEMORY_LIMIT/1024/1024/1024 from information_schema.MEMORY_USAGE;" 2>/dev/null)
    local val
    val=$(echo "$sql_output" | head -n1)
    
    # Format the MEMORY_LIMIT to 2 decimal places
    printf "%.2f" "$val"
}


###############################################################################
# 服务 4.2
# 通用的内存查询函数，单位转换为 GB 
###############################################################################
function fetch_avg_max_mem() {
    local avg_query="$1"
    local max_query="$2"
    local avg_response max_response
    avg_response=$(curl -s -G "http://$PROME_ADDR/api/v1/query" --data-urlencode "query=$avg_query")
    max_response=$(curl -s -G "http://$PROME_ADDR/api/v1/query" --data-urlencode "query=$max_query")

    declare -A avg_map
    declare -A max_map

    if echo "$avg_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        while IFS=$'\t' read -r inst val; do
            avg_map["$inst"]="$val"
        done < <(
            echo "$avg_response" | jq -r '.data.result[] | [.metric.instance, ((.value[1] | tonumber)/1073741824)] | @tsv'  # Convert to GB
        )
    fi

    if echo "$max_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        while IFS=$'\t' read -r inst val; do
            max_map["$inst"]="$val"
        done < <(
            echo "$max_response" | jq -r '.data.result[] | [.metric.instance, ((.value[1] | tonumber)/1073741824)] | @tsv'  # Convert to GB
        )
    fi

    for inst in "${!avg_map[@]}"; do
        local a="${avg_map[$inst]}"
        local m="${max_map[$inst]:-0}"
        printf "%s\t%.2f\t%.2f\n" "$inst" "$a" "$m"
    done
}


###############################################################################
# 服务 4.1/4.2/4.3
# 通用的 Prometheus 查询函数：获取 CPU 使用情况
###############################################################################
function fetch_avg_max_cpu() {
    local avg_query="$1"
    local max_query="$2"
    local avg_response max_response
    avg_response=$(curl -s -G "http://$PROME_ADDR/api/v1/query" --data-urlencode "query=$avg_query")
    max_response=$(curl -s -G "http://$PROME_ADDR/api/v1/query" --data-urlencode "query=$max_query")

    declare -A avg_map
    declare -A max_map

    if echo "$avg_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        while IFS=$'\t' read -r inst val; do
            avg_map["$inst"]="$val"
        done < <(
            echo "$avg_response" | jq -r '.data.result[] | [.metric.instance, (.value[1] | (tonumber*100))] | @tsv'
        )
    fi

    if echo "$max_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        while IFS=$'\t' read -r inst val; do
            max_map["$inst"]="$val"
        done < <(
            echo "$max_response" | jq -r '.data.result[] | [.metric.instance, (.value[1] | (tonumber*100))] | @tsv'
        )
    fi

    for inst in "${!avg_map[@]}"; do
        local a="${avg_map[$inst]}"
        local m="${max_map[$inst]:-0}"
        printf "%s\t%.2f\t%.2f\n" "$inst" "$a" "$m"
    done
}

###############################################################################
# 服务 4.2
# 获取 TiDB memory 参数的函数
###############################################################################
function get_tidb_memory_param() {
    local instance="$1"
    local sql_output
    sql_output=$(run_sql "select MEMORY_LIMIT/1024/1024/1024 from information_schema.MEMORY_USAGE;" 2>/dev/null)
    local val
    val=$(echo "$sql_output" | head -n1)
    
    # Format the MEMORY_LIMIT to 2 decimal places
    printf "%.2f" "$val"
}


###############################################################################
# 服务 4.2
# 通用的内存查询函数，单位转换为 GB 
###############################################################################
function fetch_avg_max_mem() {
    local avg_query="$1"
    local max_query="$2"
    local avg_response max_response
    avg_response=$(curl -s -G "http://$PROME_ADDR/api/v1/query" --data-urlencode "query=$avg_query")
    max_response=$(curl -s -G "http://$PROME_ADDR/api/v1/query" --data-urlencode "query=$max_query")

    declare -A avg_map
    declare -A max_map

    if echo "$avg_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        while IFS=$'\t' read -r inst val; do
            avg_map["$inst"]="$val"
        done < <(
            echo "$avg_response" | jq -r '.data.result[] | [.metric.instance, ((.value[1] | tonumber)/1073741824)] | @tsv'  # Convert to GB
        )
    fi

    if echo "$max_response" | jq -e '.status == "success"' >/dev/null 2>&1; then
        while IFS=$'\t' read -r inst val; do
            max_map["$inst"]="$val"
        done < <(
            echo "$max_response" | jq -r '.data.result[] | [.metric.instance, ((.value[1] | tonumber)/1073741824)] | @tsv'  # Convert to GB
        )
    fi

    for inst in "${!avg_map[@]}"; do
        local a="${avg_map[$inst]}"
        local m="${max_map[$inst]:-0}"
        printf "%s\t%.2f\t%.2f\n" "$inst" "$a" "$m"
    done
}


###############################################################################
# 4.1 Performance statistics by PD 检查
###############################################################################
function check_pd_performance() {
    local output_file="$OUTPUT_FILE"
    local hours="${INSPECTION_WINDOW_HOURS}h"

    cat <<EOF >> "$output_file"
<h3 class="filterable-chapter" data-chapter="4">四、Performance Statistics</h3>
<p style="color: red;">注：4.1/4.2/4.3 检查消耗的CPU/内存是否超过建议阈值，红色行为异常 </p>
<h4 id="check41">4.1 Performance statistics by PD</h4>
<p>巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时</p>
<table>
    <tr>
        <th>PD Instance</th>
        <th>Monitoring Items</th>
        <th>Avg Metrics</th>
        <th>Max Metrics</th>
        <th>参数值</th>
        <th>建议阈值</th>
        <th>备注</th>
    </tr>
EOF

    local cpu_avg="avg_over_time(rate(process_cpu_seconds_total{job=\"pd\"}[1m])[${hours}:])"
    local cpu_max="max_over_time(rate(process_cpu_seconds_total{job=\"pd\"}[1m])[${hours}:])"
    while IFS=$'\t' read -r prom_instance avg_cpu max_cpu; do
        local instance_display="$prom_instance"
        # 获取服务器的 vcore 数量
        local cpu_param_val
        cpu_param_val=$(lscpu | grep "^CPU(s):" | awk -F ":" '{print $2}' | xargs || echo "N/A")
        local row_style=""
        local remark="读取服务器 vcore 数量"

        # 如果 cpu_param_val 是有效的数值，计算 80% 阈值
        if [[ "$cpu_param_val" =~ ^[0-9]+$ ]]; then
            # 计算阈值并乘以 100% 以获取最大值
            local threshold=$(echo "$cpu_param_val * 0.8 * 100" | bc)
			#local threshold=$(echo "$cpu_param_val * 0.000008 * 100" | bc)

            # 判断 max_cpu 是否超过阈值
            local max_cpu_value=$(echo "$max_cpu" | sed 's/%//')
            if (( $(echo "$max_cpu_value > $threshold" | bc -l) )); then
                report_issue "high" "4.1" "PD CPU($instance_display)" "avg=${avg_cpu}%, max=${max_cpu}%, vcore=${cpu_param_val}"
                row_style="color: red;"
                remark="<span style='color:red;'>读取服务器 vcore 数量</span>"
            fi
        fi

        cat <<EOF >> "$output_file"
<tr style="$row_style">
    <td>$instance_display</td>
    <td>cpu usage</td>
    <td>${avg_cpu}%</td>
    <td>${max_cpu}%</td>
    <td>${cpu_param_val}</td>
    <td>应低于 80% * cpu limit</td>
    <td>${remark}</td>
</tr>
EOF
    done < <(fetch_avg_max_cpu "$cpu_avg" "$cpu_max")

    cat <<EOF >> "$output_file"
</table>
EOF
}


###############################################################################
# 4.2 Performance statistics by TiDB 检查（采用 4.3 类似的映射方法）
###############################################################################

# 构建 TIDB_PORT_MAP：映射格式为 [host:service_port] -> "host:metrics_port"
declare -A TIDB_PORT_MAP
function build_tidb_port_map() {
    local cluster="$1"
    while read -r host_port host_ip ports; do
        # 从 ports 中提取服务端口和 metrics 端口
        local service_port metrics_port
        service_port=$(echo "$ports" | cut -d'/' -f1 | xargs)
        metrics_port=$(echo "$ports" | cut -d'/' -f2 | xargs)
        # 检查提取结果是否为空
        if [[ -z "$host_ip" || -z "$service_port" || -z "$metrics_port" ]]; then
            continue
        fi
        # 建立映射：key = "host:service_port", value = "host:metrics_port"
        TIDB_PORT_MAP["$host_ip:$service_port"]="$host_ip:$metrics_port"
    done < <(
        # 过滤出 tidb 节点的行，要求行首为 IP 地址（去除 header 等干扰行）
        tiup cluster display "$cluster" 2>/dev/null \
        | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" \
        | grep -E "\btidb\b" \
        | awk '{print $1, $3, $4}'
    )
}
build_tidb_port_map "$CLUSTER_NAME"

# 构造反向映射 TIDB_INV_MAP：key = "host:metrics_port", value = "host:service_port"
declare -A TIDB_INV_MAP
for key in "${!TIDB_PORT_MAP[@]}"; do
    TIDB_INV_MAP["${TIDB_PORT_MAP[$key]}"]="$key"
done

# 辅助函数：将 Prometheus 返回的 tidb instance（metrics 端口）转换为数据库中使用的服务端口
function map_tidb_instance() {
    local prom_inst="$1"
    if [[ -n "${TIDB_INV_MAP[$prom_inst]}" ]]; then
        echo "${TIDB_INV_MAP[$prom_inst]}"
    else
        echo "$prom_inst"
    fi
}

function is_number() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}



# 服务 4.2 Performance statistics by TiDB 检查（采用 4.3 类似的映射方法）
function check_tidb_performance() {
    local output_file="$OUTPUT_FILE"
    local hours="${INSPECTION_WINDOW_HOURS}h"  # 以小时为单位

    cat <<EOF >> "$output_file"
<h4 id="check42">4.2 Performance statistics by TiDB</h4>
<p>巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时</p>
<table>
    <tr>
        <th>TiDB Instance</th>
        <th>Monitoring Items</th>
        <th>Avg Metrics</th>
        <th>Max Metrics</th>
        <th>参数值</th>
        <th>建议阈值</th>
        <th>备注</th>
    </tr>
EOF

    # 从数据库中查询 performance.max-procs 参数
    declare -A TIDB_MAX_PROCS
    local sql_output
    sql_output=$(run_sql "show config where name='performance.max-procs';")
    while IFS=$'\t' read -r type inst name value; do
        if [[ -n "$value" ]]; then
            TIDB_MAX_PROCS["$inst"]="$value"
        else
            TIDB_MAX_PROCS["$inst"]="N/A"
        fi
    done <<< "$sql_output"

    # 查询 Prometheus 中的 CPU 使用情况
    local cpu_avg="avg_over_time(rate(process_cpu_seconds_total{job=\"tidb\"}[1m])[${hours}:])"
    local cpu_max="max_over_time(rate(process_cpu_seconds_total{job=\"tidb\"}[1m])[${hours}:])"
    while IFS=$'\t' read -r prom_instance avg_cpu max_cpu; do
        # 使用 map_tidb_instance() 将 Prometheus 上报的 instance（metrics 端口）转换为服务端口
        local instance_display
        instance_display=$(map_tidb_instance "$prom_instance")
        local raw_cpu_val="${TIDB_MAX_PROCS[$instance_display]}"
        local cpu_param_val
        local remark
        if [[ -z "$raw_cpu_val" ]]; then
            cpu_param_val="N/A"
            remark="读取 performance.max-procs 的值"
        elif [[ "$raw_cpu_val" == "0" ]]; then
            cpu_param_val=$(lscpu | grep "^CPU(s):" | awk -F ":" '{print $2}' | xargs || echo "N/A")
            remark="因未设置 performance.max-procs，读取服务器 vcore 数量"
        else
            cpu_param_val="$raw_cpu_val"
            remark="默认读取 performance.max-procs 的值"
        fi

        local row_style=""
        # Avg/Max 默认带 % 单位（值为 rate*100，即单核占比百分比）
        local avg_display="${avg_cpu}%"
        local max_display="${max_cpu}%"
        # 计算阈值：参数值 * 100 * 0.8 (80%)
        if is_number "$cpu_param_val" && is_number "$max_cpu"; then
            #local threshold=$(echo "$cpu_param_val * 100 * 0.0008" | bc -l)
		    local threshold=$(echo "$cpu_param_val * 100 * 0.8" | bc -l)
            # 判断 max_cpu 是否超过阈值并设置红色
            if (( $(echo "$max_cpu > $threshold" | bc -l) )); then
                report_issue "high" "4.2" "TiDB CPU($instance_display)" "avg=${avg_cpu}%, max=${max_cpu}%"
                row_style="color: red;"
                max_display="<span style='color:red;'>${max_cpu}%</span>"
                avg_display="<span style='color:red;'>${avg_cpu}%</span>"
                cpu_param_val="<span style='color:red;'>${cpu_param_val}</span>"
                remark="<span style='color:red;'>${remark}</span>"
            fi
        fi

        cat <<EOF >> "$output_file"
<tr style="$row_style">
    <td>$instance_display</td>
    <td>cpu usage</td>
    <td>${avg_display}</td>
    <td>${max_display}</td>
    <td>${cpu_param_val}</td>
    <td>应低于 80% * cpu limit</td>
    <td>${remark}</td>
</tr>
EOF
    done < <(fetch_avg_max_cpu "$cpu_avg" "$cpu_max")

    # 查询 Prometheus 中的 memory 使用情况
    local mem_avg="avg_over_time(process_resident_memory_bytes{job=\"tidb\"}[${hours}])"
    local mem_max="max_over_time(process_resident_memory_bytes{job=\"tidb\"}[${hours}])"
    while IFS=$'\t' read -r prom_instance avg_mem max_mem; do
        local instance_display
        instance_display=$(map_tidb_instance "$prom_instance")
        local mem_param_val_raw
        mem_param_val_raw=$(get_tidb_memory_param "$instance_display")

        # 获取内存参数值的单位
        local mem_param_val=$(echo "$mem_param_val_raw" | sed 's/[^0-9.]//g')
        local mem_param_unit=$(echo "$mem_param_val_raw" | sed 's/[0-9.]//g')

        # 统一转换内存单位，转换为 GB
        if [[ "$mem_param_unit" == "GB" && "$mem_param_val" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            # 如果参数值是 GB，将其转换为 GB
            mem_param_val=$(echo "$mem_param_val * 1" | bc -l)
        fi

        local row_style=""
        local remark="读取 information_schema.MEMORY_USAGE 的 MEMORY_LIMIT 字段"
        # Avg/Max 默认带 GB 单位
        local avg_display="${avg_mem} GB"
        local max_display="${max_mem} GB"

        # 判断 max_mem 是否超过阈值并设置红色
        if is_number "$mem_param_val" && is_number "$max_mem"; then
            #local mem_threshold=$(echo "$mem_param_val * 0.0009" | bc -l)  # 90% 阈值
		    local mem_threshold=$(echo "$mem_param_val * 0.9" | bc -l)  # 90% 阈值
            if (( $(echo "$max_mem > $mem_threshold" | bc -l) )); then
                report_issue "high" "4.2" "TiDB 内存($instance_display)" "avg=${avg_mem} GB, max=${max_mem} GB"
                row_style="color: red;"
                max_display="<span style='color:red;'>${max_mem} GB</span>"
                avg_display="<span style='color:red;'>${avg_mem} GB</span>"
                mem_param_val_raw="<span style='color:red;'>${mem_param_val_raw} GB</span>"
                remark="<span style='color:red;'>读取 information_schema.MEMORY_USAGE 的 MEMORY_LIMIT 字段</span>"
            fi
        fi

        cat <<EOF >> "$output_file"
<tr style="$row_style">
    <td>$instance_display</td>
    <td>memory usage</td>
    <td>${avg_display}</td>
    <td>${max_display}</td>
    <td>${mem_param_val_raw}</td>
    <td>应低于 90% * 内存 limit</td>
    <td>${remark}</td>
</tr>
EOF
    done < <(fetch_avg_max_mem "$mem_avg" "$mem_max")

    cat <<EOF >> "$output_file"
</table>
EOF
}

###############################################################################
# 4.3 Performance statistics by TiKV 检查
###############################################################################
# 建立 TiKV 的 server_port -> status_port 映射
declare -A TIKV_PORT_MAP
function build_tikv_port_map() {
    local cluster="$1"
    while read -r host_port host_ip ports; do
        local server_port status_port
        server_port=$(echo "$ports" | cut -d'/' -f1)
        status_port=$(echo "$ports" | cut -d'/' -f2)
        TIKV_PORT_MAP["$host_ip:$server_port"]="$host_ip:$status_port"
    done < <(
        tiup cluster display "$cluster" 2>/dev/null \
        | grep " tikv " \
        | awk '{print $1, $3, $4}'
    )
}
build_tikv_port_map "$CLUSTER_NAME"

# 构造反向映射，将状态端口映射到服务端口
declare -A TIKV_INV_MAP
for key in "${!TIKV_PORT_MAP[@]}"; do
    TIKV_INV_MAP["${TIKV_PORT_MAP[$key]}"]="$key"
done

# 辅助函数：将 Prometheus 返回的 TiKV instance（状态端口）映射为 show config 中的 instance（服务端口）
function map_tikv_instance() {
    local prom_inst="$1"
    if [[ -n "${TIKV_INV_MAP[$prom_inst]}" ]]; then
        echo "${TIKV_INV_MAP[$prom_inst]}"
    else
        echo "$prom_inst"
    fi
}

# 从数据库读取 TiKV 相关配置，并做端口映射（直接采用查询结果，不再转换）
function fetch_config_value() {
    local param_name="$1"
    local query="show config where name='$param_name';"
    local result
    result=$(run_sql "$query")
    echo "$result" | awk -F'\t' '{print $2, $4}'
}

declare -A GRPC_MAP
declare -A SCHED_MAP
declare -A URP_MAP
declare -A RAFT_MAP
declare -A APPLY_MAP

# grpc poll cpu -> server.grpc-concurrency
while read -r inst val; do
    GRPC_MAP["$inst"]="$val"
done < <(fetch_config_value "server.grpc-concurrency")

# scheduler worker cpu -> storage.scheduler-worker-pool-size
while read -r inst val; do
    SCHED_MAP["$inst"]="$val"
done < <(fetch_config_value "storage.scheduler-worker-pool-size")

# unified read pool -> readpool.unified.max-thread-count
while read -r inst val; do
    URP_MAP["$inst"]="$val"
done < <(fetch_config_value "readpool.unified.max-thread-count")

# raft store cpu -> raftstore.store-pool-size
while read -r inst val; do
    RAFT_MAP["$inst"]="$val"
done < <(fetch_config_value "raftstore.store-pool-size")

# async apply cpu -> raftstore.apply-pool-size
while read -r inst val; do
    APPLY_MAP["$inst"]="$val"
done < <(fetch_config_value "raftstore.apply-pool-size")




function check_tikv_performance() {
    cat <<EOF >> "$OUTPUT_FILE"
<h4 id="check43">4.3 Performance statistics by TiKV</h4>
<p>巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时</p>
<table>
    <tr>
        <th>TiKV Instance</th>
        <th>Monitoring Items</th>
        <th>Avg Metrics (%)</th>
        <th>Max Metrics (%)</th>
        <th>参数值</th>
        <th>建议阈值</th>
        <th>备注</th>
    </tr>
EOF

    local hours="${INSPECTION_WINDOW_HOURS}h"

    # grpc poll cpu
    local grpc_avg="sum by(instance)( rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"grpc_server.*\"}[$hours]) )"
    local grpc_max="sum by(instance)( max_over_time(rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"grpc_server.*\"}[1m])[$hours:]) )"
    while IFS=$'\t' read -r prom_instance avg_cpu max_cpu; do
        local instance_display
        instance_display=$(map_tikv_instance "$prom_instance")
        local param_val="${GRPC_MAP[$instance_display]}"
        [[ -z "$param_val" ]] && param_val="N/A"
        local row_style=""

        # 获取服务器的 grpc 参数值
        if [[ "$param_val" =~ ^[0-9]+$ ]]; then
            # 计算阈值 80% * param_val * 100
            #local threshold=$(echo "$param_val * 0.000008 * 100" | bc)
			local threshold=$(echo "$param_val * 0.8 * 100" | bc)

            # 去掉 max_cpu 中的百分号并转换为数值
            local max_cpu_value=$(echo "$max_cpu" | sed 's/%//')

            # 判断 max_cpu 是否超过阈值
            if (( $(echo "$max_cpu_value > $threshold" | bc -l) )); then
                report_issue "high" "4.3" "TiKV gRPC($instance_display)" "avg=${avg_cpu}%, max=${max_cpu}%"
                row_style="color: red;"
            fi
        fi

        cat <<EOF >> "$OUTPUT_FILE"
<tr style="$row_style">
    <td>$instance_display</td>
    <td>grpc poll cpu</td>
    <td>${avg_cpu}%</td>
    <td>${max_cpu}%</td>
    <td>${param_val}</td>
    <td>应低于 80% * server.grpc-concurrency</td>
    <td>根据 grpc 参数值计算</td>
</tr>
EOF
    done < <(fetch_avg_max_cpu "$grpc_avg" "$grpc_max")

    # scheduler worker cpu
    local sched_avg="sum by(instance)( rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"sched_.*\"}[$hours]) )"
    local sched_max="sum by(instance)( max_over_time(rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"sched_.*\"}[1m])[$hours:]) )"
    while IFS=$'\t' read -r prom_instance avg_cpu max_cpu; do
        local instance_display
        instance_display=$(map_tikv_instance "$prom_instance")
        local param_val="${SCHED_MAP[$instance_display]}"
        [[ -z "$param_val" ]] && param_val="N/A"
        local row_style=""

        # 获取服务器的 scheduler 参数值
        if [[ "$param_val" =~ ^[0-9]+$ ]]; then
            # 计算阈值 80% * param_val * 100
            local threshold=$(echo "$param_val * 0.9 * 100" | bc)

            # 去掉 max_cpu 中的百分号并转换为数值
            local max_cpu_value=$(echo "$max_cpu" | sed 's/%//')

            # 判断 max_cpu 是否超过阈值
            if (( $(echo "$max_cpu_value > $threshold" | bc -l) )); then
                report_issue "high" "4.3" "TiKV scheduler($instance_display)" "avg=${avg_cpu}%, max=${max_cpu}%"
                row_style="color: red;"
            fi
        fi

        cat <<EOF >> "$OUTPUT_FILE"
<tr style="$row_style">
    <td>$instance_display</td>
    <td>scheduler worker cpu</td>
    <td>${avg_cpu}%</td>
    <td>${max_cpu}%</td>
    <td>${param_val}</td>
    <td>应低于 90% * storage.scheduler-worker-pool-size</td>
    <td>根据 scheduler 参数值计算</td>
</tr>
EOF
    done < <(fetch_avg_max_cpu "$sched_avg" "$sched_max")

    # unified read pool cpu
    local urp_avg="sum by(instance)( rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"unified_read_po.*\"}[$hours]) )"
    local urp_max="sum by(instance)( max_over_time(rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"unified_read_po.*\"}[1m])[$hours:]) )"
    while IFS=$'\t' read -r prom_instance avg_cpu max_cpu; do
        local instance_display
        instance_display=$(map_tikv_instance "$prom_instance")
        local param_val="${URP_MAP[$instance_display]}"
        [[ -z "$param_val" ]] && param_val="N/A"
        local row_style=""

        # 获取服务器的 unified read pool 参数值
        if [[ "$param_val" =~ ^[0-9]+$ ]]; then
            # 计算阈值 80% * param_val * 100
            local threshold=$(echo "$param_val * 0.8 * 100" | bc)

            # 去掉 max_cpu 中的百分号并转换为数值
            local max_cpu_value=$(echo "$max_cpu" | sed 's/%//')

            # 判断 max_cpu 是否超过阈值
            if (( $(echo "$max_cpu_value > $threshold" | bc -l) )); then
                report_issue "high" "4.3" "TiKV unified_read_pool($instance_display)" "avg=${avg_cpu}%, max=${max_cpu}%"
                row_style="color: red;"
            fi
        fi

        cat <<EOF >> "$OUTPUT_FILE"
<tr style="$row_style">
    <td>$instance_display</td>
    <td>unified read pool cpu</td>
    <td>${avg_cpu}%</td>
    <td>${max_cpu}%</td>
    <td>${param_val}</td>
    <td>应低于 80% * readpool.unified.max-thread-count</td>
    <td>根据 unified read pool 参数值计算</td>
</tr>
EOF
    done < <(fetch_avg_max_cpu "$urp_avg" "$urp_max")

    # raft store cpu
    local raft_avg="sum by(instance)( rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"raftstore_.*\"}[$hours]) )"
    local raft_max="sum by(instance)( max_over_time(rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"raftstore_.*\"}[1m])[$hours:]) )"
    while IFS=$'\t' read -r prom_instance avg_cpu max_cpu; do
        local instance_display
        instance_display=$(map_tikv_instance "$prom_instance")
        local param_val="${RAFT_MAP[$instance_display]}"
        [[ -z "$param_val" ]] && param_val="N/A"
        local row_style=""

        # 获取服务器的 raft store 参数值
        if [[ "$param_val" =~ ^[0-9]+$ ]]; then
            # 计算阈值 80% * param_val * 100
            local threshold=$(echo "$param_val * 0.8 * 100" | bc)

            # 去掉 max_cpu 中的百分号并转换为数值
            local max_cpu_value=$(echo "$max_cpu" | sed 's/%//')

            # 判断 max_cpu 是否超过阈值
            if (( $(echo "$max_cpu_value > $threshold" | bc -l) )); then
                report_issue "high" "4.3" "TiKV raftstore($instance_display)" "avg=${avg_cpu}%, max=${max_cpu}%"
                row_style="color: red;"
            fi
        fi

        cat <<EOF >> "$OUTPUT_FILE"
<tr style="$row_style">
    <td>$instance_display</td>
    <td>raft store cpu</td>
    <td>${avg_cpu}%</td>
    <td>${max_cpu}%</td>
    <td>${param_val}</td>
    <td>应低于 80% * raftstore.store-pool-size</td>
    <td>根据 raft store 参数值计算</td>
</tr>
EOF
    done < <(fetch_avg_max_cpu "$raft_avg" "$raft_max")

    # async apply cpu
    local apply_avg="sum by(instance)( rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"apply_.*\"}[$hours]) )"
    local apply_max="sum by(instance)( max_over_time(rate(tikv_thread_cpu_seconds_total{job=\"tikv\", name=~\"apply_.*\"}[1m])[$hours:]) )"
    while IFS=$'\t' read -r prom_instance avg_cpu max_cpu; do
        local instance_display
        instance_display=$(map_tikv_instance "$prom_instance")
        local param_val="${APPLY_MAP[$instance_display]}"
        [[ -z "$param_val" ]] && param_val="N/A"
        local row_style=""

        # 获取服务器的 async apply 参数值
        if [[ "$param_val" =~ ^[0-9]+$ ]]; then
            # 计算阈值 80% * param_val * 100
            local threshold=$(echo "$param_val * 0.9 * 100" | bc)

            # 去掉 max_cpu 中的百分号并转换为数值
            local max_cpu_value=$(echo "$max_cpu" | sed 's/%//')

            # 判断 max_cpu 是否超过阈值
            if (( $(echo "$max_cpu_value > $threshold" | bc -l) )); then
                report_issue "high" "4.3" "TiKV async_apply($instance_display)" "avg=${avg_cpu}%, max=${max_cpu}%"
                row_style="color: red;"
            fi
        fi

        cat <<EOF >> "$OUTPUT_FILE"
<tr style="$row_style">
    <td>$instance_display</td>
    <td>async apply cpu</td>
    <td>${avg_cpu}%</td>
    <td>${max_cpu}%</td>
    <td>${param_val}</td>
    <td>应低于 90% * raftstore.apply-pool-size</td>
    <td>根据 async apply 参数值计算</td>
</tr>
EOF
    done < <(fetch_avg_max_cpu "$apply_avg" "$apply_max")

    cat <<EOF >> "$OUTPUT_FILE"
</table>
EOF
}

###############################################################################
# 5.3 SQL ordered by Elapsed Time
###############################################################################


function check_sql_order_by_elapsed_time() {
	echo "<h3 class=\"filterable-chapter\" data-chapter=\"5\">五、SQL Statistics</h3>" >> "$OUTPUT_FILE"
    echo "<h4 id=\"check53\">5.3 SQL ordered by Elapsed Time</h4>" >> "$OUTPUT_FILE"
    # 将巡检时间窗写出来：如 “记录巡检时间窗 48 小时 SQL 执行耗时排序 TOP 15”
    echo "<p>记录巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时 SQL 执行耗时排序 TOP 15</p>" >> "$OUTPUT_FILE"

    # 插入该功能说明文字，参考您给出的图片要求
    echo "<ul>" >> "$OUTPUT_FILE"
    echo "  <li><b>Elapsed Time(s)</b>：SQL 执行总耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Executions</b>：SQL 执行总次数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Elap per Exec(s)</b>：每次执行平均耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Min query Time(s)</b>：SQL 最小执行耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Max query Time(s)</b>：SQL 最大执行耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Avg total keys</b>：Coprocessor 扫过的 key 的平均数量</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Avg processed keys</b>：Coprocessor 处理的 key 的平均数量（不包含 MVCC）</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Time Percentage</b>：巡检时间内 SQL 总体耗时占比</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Digest</b>：SQL 指纹</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Text</b>：SQL 文本</li>" >> "$OUTPUT_FILE"
    echo "</ul>" >> "$OUTPUT_FILE"

    # 1) 获取 insp_time（在设定巡检时间窗内所有 SQL 的总耗时，单位秒）
    local insp_time
    insp_time=$(run_sql "
SELECT
  COALESCE(SUM(sum_latency)/1000000000, 0)
FROM information_schema.cluster_statements_summary_history a
WHERE a.summary_begin_time <= NOW()
  AND a.summary_end_time >= DATE_ADD(NOW(), INTERVAL - ${INSPECTION_WINDOW_MINUTES} MINUTE)
  AND a.query_sample_text NOT LIKE '%/*+ monitoring */%';
    " 2>/dev/null)

    # 如果 insp_time 为空或 0，做个简单判断，防止后续除以 0 出错
    if [[ -z "$insp_time" || "$insp_time" == "0" ]]; then
        echo "<p><b>在最近 ${INSPECTION_WINDOW_HOURS} 小时内无有效 SQL 统计信息，或总耗时为 0。</b></p>" >> "$OUTPUT_FILE"
        return
    fi

    # 2) 执行主查询，获取排名前 15 的 SQL 记录
    local result
    result=$(run_sql "
/*+ monitoring */ 
SELECT
       total_latency_s,
       total_execs,
       avg_latency_s,
       min_latency_s,
       max_latency_s,
       avg_total_keys,
       avg_processed_keys,
       percentage,
       sql_digest,
       sql_text
  FROM (
    SELECT 
         SUM(sum_latency)/1000000000 AS total_latency_s,             -- SQL 总耗时（秒）
         SUM(exec_count)            AS total_execs,                 -- SQL 总执行次数
         AVG(avg_latency)/1000000000 AS avg_latency_s,              -- 平均执行耗时（秒）
         MIN(min_latency)/1000000000 AS min_latency_s,              -- 最小执行耗时（秒）
         MAX(max_latency)/1000000000 AS max_latency_s,              -- 最大执行耗时（秒）
         ROUND(AVG(avg_total_keys)) AS avg_total_keys,              -- 平均扫描 keys 数量
         ROUND(AVG(avg_processed_keys)) AS avg_processed_keys,      -- 平均处理 keys 数量
         ROUND(SUM(sum_latency)/1000000000 / ${insp_time} * 100, 2) AS percentage, -- 总耗时占比
         DIGEST                     AS sql_digest,                 -- SQL Digest
         MIN(QUERY_SAMPLE_TEXT)     AS sql_text                    -- 示例 SQL 文本
      FROM information_schema.cluster_statements_summary_history a
     WHERE a.summary_begin_time <= NOW()
       AND a.summary_end_time >= DATE_ADD(NOW(), INTERVAL - ${INSPECTION_WINDOW_MINUTES} MINUTE)
       AND a.query_sample_text NOT LIKE '%/*+ monitoring */%'
     GROUP BY DIGEST
  ) aaa
  ORDER BY total_latency_s DESC
  LIMIT 15;
    " 2>/dev/null)

    # 3) 将查询结果写成 HTML 表格
    echo "<table>" >> "$OUTPUT_FILE"
    echo "  <tr>" >> "$OUTPUT_FILE"
    echo "    <th>Elapsed Time(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Executions</th>" >> "$OUTPUT_FILE"
    echo "    <th>Elap per Exec(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Min query Time(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Max query Time(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Avg total keys</th>" >> "$OUTPUT_FILE"
    echo "    <th>Avg processed keys</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Time Percentage</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Digest</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Text</th>" >> "$OUTPUT_FILE"
    echo "  </tr>" >> "$OUTPUT_FILE"

# 逐行解析查询结果
echo "$result" | while IFS=$'\t' read -r total_latency_s total_execs avg_latency_s \
    min_latency_s max_latency_s avg_total_keys avg_processed_keys percentage sql_digest sql_text
do
    echo "  <tr>" >> "$OUTPUT_FILE"
echo "    <td>$(printf "%.3f" "$total_latency_s")</td>" >> "$OUTPUT_FILE"  # 保留3位小数
echo "    <td>$total_execs</td>" >> "$OUTPUT_FILE"
echo "    <td>$(printf "%.3f" "$avg_latency_s")</td>" >> "$OUTPUT_FILE"
echo "    <td>$(printf "%.3f" "$min_latency_s")</td>" >> "$OUTPUT_FILE"
echo "    <td>$(printf "%.3f" "$max_latency_s")</td>" >> "$OUTPUT_FILE"
echo "    <td>$avg_total_keys</td>" >> "$OUTPUT_FILE"
echo "    <td>$avg_processed_keys</td>" >> "$OUTPUT_FILE"
echo "    <td>${percentage}%</td>" >> "$OUTPUT_FILE"
echo "    <td>$sql_digest</td>" >> "$OUTPUT_FILE"
echo "    <td>${sql_text//</&lt;}</td>" >> "$OUTPUT_FILE"

    echo "  </tr>" >> "$OUTPUT_FILE"
done


    echo "</table>" >> "$OUTPUT_FILE"
    echo "<br>" >> "$OUTPUT_FILE"
}


###############################################################################
#  服务 5.2 , 5.3
#  获取 ng-monitoring 地址 (NG_ADDR)，TopSQL API /topsql/v1/* 由 ng-monitoring 提供
#  默认端口 12020。tiup cluster display 中 ng-monitoring 有两种呈现方式：
#    1) 独立的 ng-monitoring 组件行（ID 形如 host:12020）
#    2) 与 prometheus 同机部署，端口列在 prometheus 行的 Ports 中（如 9090/9115/9100/12020）
#  优先按方式 1 查找；找不到则按方式 2 从 prometheus 行的端口列表里取 12020（或最后一个端口）
###############################################################################
function get_ng_addr() {
    local id line host ports port

    # 1) 优先查找独立的 ng-monitoring 组件行
    id="$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null \
      | awk '$2=="ng-monitoring" {print $1; exit;}')"
    if [[ -n "$id" ]]; then
        echo "$id"   # 形如 192.0.2.10:12020
        return 0
    fi

    # 2) 否则从 prometheus 行解析（ng-monitoring 与 prometheus 同机部署）
    line="$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null \
      | awk '$2=="prometheus" {print $3, $4; exit;}')"
    if [[ -z "$line" ]]; then
        echo "未找到 prometheus / ng-monitoring 信息" >&2
        return 1
    fi
    host="${line%% *}"                       # 192.0.2.10
    ports="${line#* }"                       # 9090/9115/9100/12020
    # 优先取 ng-monitoring 默认端口 12020；找不到则取端口列表最后一个
    port="$(echo "$ports" | tr '/' '\n' | awk '/^12020$/{print; exit}')"
    [[ -z "$port" ]] && port="$(echo "$ports" | awk -F'/' '{print $NF}')"
    if [[ -z "$host" || -z "$port" ]]; then
        echo "解析 ng-monitoring 端口失败: $line" >&2
        return 1
    fi
    echo "${host}:${port}"
}

NG_ADDR=$(get_ng_addr)
echo "NG_ADDR(ng-monitoring)=${NG_ADDR}"

###############################################################################
# 5.1 + 5.2 make_url_request、pull_tidb_topsql、pull_tikv_topsql 逻辑
###############################################################################

start_secs=$(date -d "now -${INSPECTION_WINDOW_MINUTES} min" +%s)
end_secs=$(date -d "now" +%s)

# 初始化临时文件
tidb_inst_resp_file=$(mktemp)
echo "[]" > "$tidb_inst_resp_file"

tikv_inst_resp_file=$(mktemp)
echo "[]" > "$tikv_inst_resp_file"

# 定义 make_url_request 函数
function make_url_request() {
    local url=$1
    local component=$2
    local max_retries=3
    local wait_time=1
    local resp code body tmp_json tmp_file

    for ((retry=1; retry<=max_retries; retry++)); do
        if (( TOTAL_RETRY_COUNT >= 5 )); then
            echo "累计重试次数已达到 5 次，退出该函数。"
            return 1
        fi

        resp=$(curl -s --connect-timeout 3 --max-time 10 -w "\n%{http_code}" "$url")
        code=${resp##*$'\n'}
        body=${resp%$'\n'*}

        if [[ "$code" == "200" ]]; then
            # 先校验 body 是否为合法 JSON
            if ! echo "$body" | jq -e . >/dev/null 2>&1; then
                echo "TopSQL 接口返回的不是合法 JSON，跳过本次结果 (可能 TopSQL 功能未启用或 Dashboard 未配置): $url" >&2
                # 不计入重试次数，因为这是配置问题而非网络问题
                if [[ $retry -lt $max_retries ]]; then
                    sleep "$wait_time"
                    continue
                fi
                return 1
            fi

            tmp_json=$(mktemp)
            echo "$body" > "$tmp_json"

            if [[ "$component" == "TiDB" ]]; then
                tmp_file=$(mktemp)
                if jq -s '.[0] + [.[1]]' "$tidb_inst_resp_file" "$tmp_json" > "$tmp_file" 2>/dev/null; then
                    mv "$tmp_file" "$tidb_inst_resp_file"
                else
                    rm -f "$tmp_file" "$tmp_json"
                    echo "拼接 TiDB TopSQL JSON 失败: $url" >&2
                    TOTAL_RETRY_COUNT=$((TOTAL_RETRY_COUNT + 1))
                    if [[ $retry -lt $max_retries ]]; then
                        sleep "$wait_time"
                        continue
                    fi
                    return 1
                fi
            else
                tmp_file=$(mktemp)
                if jq -s '.[0] + [.[1]]' "$tikv_inst_resp_file" "$tmp_json" > "$tmp_file" 2>/dev/null; then
                    mv "$tmp_file" "$tikv_inst_resp_file"
                else
                    rm -f "$tmp_file" "$tmp_json"
                    echo "拼接 TiKV TopSQL JSON 失败: $url" >&2
                    TOTAL_RETRY_COUNT=$((TOTAL_RETRY_COUNT + 1))
                    if [[ $retry -lt $max_retries ]]; then
                        sleep "$wait_time"
                        continue
                    fi
                    return 1
                fi
            fi

            rm -f "$tmp_json"
            return 0
        else
            echo "请求失败 code=$code: $url" >&2
            TOTAL_RETRY_COUNT=$((TOTAL_RETRY_COUNT + 1))
            if (( TOTAL_RETRY_COUNT >= 5 )); then
                echo "累计重试次数已达到 5 次，退出该函数。"
                return 1
            fi
            if [[ $retry -lt $max_retries ]]; then
                sleep "$wait_time"
            fi
        fi
    done

    echo "所有重试失败: $url" >&2
    return 1
}

function pull_tidb_topsql() {
    # 先用 tiup cluster display 找到所有 role=tidb 的行，取第 3 列(Host) 和第 4 列(Ports)
    local tidb_addr_list
    tidb_addr_list=$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null \
        | awk '$2=="tidb" {print $3,$4}')

    if [[ -z "$tidb_addr_list" ]]; then
        #echo "未找到 TiDB 节点"
        return
    fi

    # 遍历每行，形如 "192.0.2.10 4003/10083"
    while read -r line; do
        [ -z "$line" ] && continue

        # 拆分出 host 和 端口串
        local host ports second_port
        host=$(echo "$line" | awk '{print $1}')    # 例: 192.0.2.10
        ports=$(echo "$line" | awk '{print $2}')   # 例: 4003/10083

        # 获取第二个端口
        second_port=$(echo "$ports" | awk -F'/' '{print $2}')
        # 如果需要第一个端口，可以使用以下命令：
        # first_port=$(echo "$ports" | awk -F'/' '{print $1}')

        # 拼接 IP:Port，比如 192.0.2.10:10083
        local tidb_ipport="${host}:${second_port}"
        # 直接使用 TiDB 的 metrics 端口地址
        local tidb_metrics_addr="${host}:${second_port}"
        #echo "[TiDB] Pull from $tidb_ipport"

        # 构造请求 URL
        local url="http://${NG_ADDR}/topsql/v1/summary?end=${end_secs}&instance=${tidb_ipport}&instance_type=tidb&start=${start_secs}&top=15"
        make_url_request "$url" "TiDB"
    done <<< "$tidb_addr_list"
}

function pull_tikv_topsql() {
    local tikv_addr_list
    tikv_addr_list=$(tiup cluster display "$CLUSTER_NAME" 2>/dev/null \
        | awk '$2=="tikv" {print $1}')

    if [[ -z "$tikv_addr_list" ]]; then
        echo "No TiKV found."
        return
    fi

    while read -r line; do
        [ -z "$line" ] && continue
        # line e.g. "192.0.2.10:20166"
        local tikv_ipport="$line"
        local url="http://${NG_ADDR}/topsql/v1/summary?end=$end_secs&instance=$tikv_ipport&instance_type=tikv&start=$start_secs&top=15"
        #echo "[TiKV] Pull from $tikv_ipport"
        make_url_request "$url" "TiKV"
    done <<< "$tikv_addr_list"
}


#########################################
# 5.1 + 5.2 主逻辑
#########################################

function check_sql_order_by_tidb_cpu_time() {
    echo "<h4 id=\"check51\">5.1 SQL ordered by TiDB CPU Time</h4>" >> "$OUTPUT_FILE"
    echo "<p>记录巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时内，TiDB 维度 CPU 时间总和排名 TOP 15</p>" >> "$OUTPUT_FILE"
	echo "<p style=\"color: red;\">注：按 SQL 指纹统计所有 TiDB 侧消耗的 CPU 总时间；若表格没有数据，可能是没有打开 dashboard 的 Top SQL 功能</p>" >> "$OUTPUT_FILE"



    echo "<ul>" >> "$OUTPUT_FILE"
    echo "  <li><b>CPU Time(s)</b>：SQL 执行 CPU 总消耗 (秒)</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Exec counts per sec</b>：每秒执行 SQL 次数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Latency per exec(s)</b>：每次执行平均 SQL 耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Scan record per sec</b>：每秒扫描表记录数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Scan indexes per sec</b>：每秒扫描索引记录数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Plan digest counts</b>：产生执行计划数量</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Digest</b>：SQL 指纹</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Text</b>：SQL 文本(参数化后)</li>" >> "$OUTPUT_FILE"
    echo "</ul>" >> "$OUTPUT_FILE"

    # 从临时文件中读取 TiDB 数据
    local len_tidb
    len_tidb=$(jq 'length' "$tidb_inst_resp_file" 2>/dev/null || echo 0)
    if [[ "$len_tidb" -eq 0 ]]; then
        echo "<p><b>未能获取 TiDB TopSQL 数据，或无记录。</b></p>" >> "$OUTPUT_FILE"
        return
    fi

    local agg_json
    agg_json=$(jq '
      [.[].data[]] 
      | group_by(.sql_digest)
      | map({
          sql_digest: .[0].sql_digest,
          sql_text: .[0].sql_text,
          cpu_time_ms: (map(.cpu_time_ms) | add),
          exec_count_per_sec: (map(.exec_count_per_sec) | add),
          duration_per_exec_ms: (map(.duration_per_exec_ms) | add),
          scan_records_per_sec: (map(.scan_records_per_sec) | add),
          scan_indexes_per_sec: (map(.scan_indexes_per_sec) | add),
          plans: (map(.plans[]) | flatten)
       })
      | map(. + {
          unique_plan_counts: (
            .plans
            | group_by(.plan_digest)
            | length
          )
       })
      | sort_by(.cpu_time_ms) | reverse
    ' "$tidb_inst_resp_file")

    echo "<table>" >> "$OUTPUT_FILE"
    echo "  <tr>" >> "$OUTPUT_FILE"
    echo "    <th>CPU Time(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Exec counts per sec</th>" >> "$OUTPUT_FILE"
    echo "    <th>Latency per exec(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Scan record per sec</th>" >> "$OUTPUT_FILE"
    echo "    <th>Scan indexes per sec</th>" >> "$OUTPUT_FILE"
    echo "    <th>Plan digest counts</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Digest</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Text</th>" >> "$OUTPUT_FILE"
    echo "  </tr>" >> "$OUTPUT_FILE"

    echo "$agg_json" | jq -r '.[] | select(.sql_digest != null)
        | [
            ((.cpu_time_ms / 1000)|tostring),
            (.exec_count_per_sec|tostring),
            ((.duration_per_exec_ms / 1000)|tostring),
            (.scan_records_per_sec|tostring),
            (.scan_indexes_per_sec|tostring),
            (.unique_plan_counts|tostring),
            .sql_digest,
            .sql_text
          ]
          | @tsv' \
    | while IFS=$'\t' read -r cpu_time_s exec_ps latency_ps scan_rec_ps scan_idx_ps plan_cnt sql_digest sql_text
    do
        echo "  <tr>" >> "$OUTPUT_FILE"
        echo "    <td>$cpu_time_s</td>" >> "$OUTPUT_FILE"
        echo "    <td>$exec_ps</td>" >> "$OUTPUT_FILE"
        echo "    <td>$latency_ps</td>" >> "$OUTPUT_FILE"
        echo "    <td>$scan_rec_ps</td>" >> "$OUTPUT_FILE"
        echo "    <td>$scan_idx_ps</td>" >> "$OUTPUT_FILE"
        echo "    <td>$plan_cnt</td>" >> "$OUTPUT_FILE"
        echo "    <td>$sql_digest</td>" >> "$OUTPUT_FILE"
        echo "    <td>${sql_text//</&lt;}</td>" >> "$OUTPUT_FILE"
        echo "  </tr>" >> "$OUTPUT_FILE"
    done

    echo "</table><br>" >> "$OUTPUT_FILE"
}

function check_sql_order_by_tikv_cpu_time() {
    echo "<h4 id=\"check52\">5.2 SQL ordered by TiKV CPU Time</h4>" >> "$OUTPUT_FILE"
    echo "<p>记录巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时内，TiKV 维度 CPU 时间总和排名 TOP 15</p>" >> "$OUTPUT_FILE"
	echo "<p style=\"color: red;\">注：按 SQL 指纹统计所有在 TiKV 侧消耗的 CPU 总时间；若表格没有数据，可能是没有打开 dashboard 的 Top SQL 功能</p>" >> "$OUTPUT_FILE"


    echo "<ul>" >> "$OUTPUT_FILE"
    echo "  <li><b>CPU Time(s)</b>：SQL 执行 CPU 总消耗 (秒)</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Exec counts per sec</b>：每秒执行 SQL 次数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Latency per exec(s)</b>：每次执行平均 SQL 耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Scan record per sec</b>：每秒扫描表记录数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Scan indexes per sec</b>：每秒扫描索引记录数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Plan digest counts</b>：产生执行计划数量</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Digest</b>：SQL 指纹</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Text</b>：SQL 文本(参数化后)</li>" >> "$OUTPUT_FILE"
    echo "</ul>" >> "$OUTPUT_FILE"

    # 从临时文件中读取 TiKV 数据
    local len_tikv
    len_tikv=$(jq 'length' "$tikv_inst_resp_file" 2>/dev/null || echo 0)
    if [[ "$len_tikv" -eq 0 ]]; then
        echo "<p><b>未能获取 TiKV TopSQL 数据，或无记录。</b></p>" >> "$OUTPUT_FILE"
        return
    fi

    local agg_json
    agg_json=$(jq '
      [.[].data[]]
      | group_by(.sql_digest)
      | map({
          sql_digest: .[0].sql_digest,
          sql_text: .[0].sql_text,
          cpu_time_ms: (map(.cpu_time_ms) | add),
          exec_count_per_sec: (map(.exec_count_per_sec) | add),
          duration_per_exec_ms: (map(.duration_per_exec_ms) | add),
          scan_records_per_sec: (map(.scan_records_per_sec) | add),
          scan_indexes_per_sec: (map(.scan_indexes_per_sec) | add),
          plans: (map(.plans[]) | flatten)
       })
      | map(. + {
          unique_plan_counts: (
            .plans
            | group_by(.plan_digest)
            | length
          )
       })
      | sort_by(.cpu_time_ms) | reverse
    ' "$tikv_inst_resp_file")

    echo "<table>" >> "$OUTPUT_FILE"
    echo "  <tr>" >> "$OUTPUT_FILE"
    echo "    <th>CPU Time(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Exec counts per sec</th>" >> "$OUTPUT_FILE"
    echo "    <th>Latency per exec(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Scan record per sec</th>" >> "$OUTPUT_FILE"
    echo "    <th>Scan indexes per sec</th>" >> "$OUTPUT_FILE"
    echo "    <th>Plan digest counts</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Digest</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Text</th>" >> "$OUTPUT_FILE"
    echo "  </tr>" >> "$OUTPUT_FILE"

    echo "$agg_json" | jq -r '.[] | select(.sql_digest != null)
        | [
            ((.cpu_time_ms / 1000)|tostring),
            (.exec_count_per_sec|tostring),
            ((.duration_per_exec_ms / 1000)|tostring),
            (.scan_records_per_sec|tostring),
            (.scan_indexes_per_sec|tostring),
            (.unique_plan_counts|tostring),
            .sql_digest,
            .sql_text
          ]
          | @tsv' \
    | while IFS=$'\t' read -r cpu_time_s exec_ps latency_ps scan_rec_ps scan_idx_ps plan_cnt sql_digest sql_text
    do
        echo "  <tr>" >> "$OUTPUT_FILE"
        echo "    <td>$cpu_time_s</td>" >> "$OUTPUT_FILE"
        echo "    <td>$exec_ps</td>" >> "$OUTPUT_FILE"
        echo "    <td>$latency_ps</td>" >> "$OUTPUT_FILE"
        echo "    <td>$scan_rec_ps</td>" >> "$OUTPUT_FILE"
        echo "    <td>$scan_idx_ps</td>" >> "$OUTPUT_FILE"
        echo "    <td>$plan_cnt</td>" >> "$OUTPUT_FILE"
        echo "    <td>$sql_digest</td>" >> "$OUTPUT_FILE"
        echo "    <td>${sql_text//</&lt;}</td>" >> "$OUTPUT_FILE"
        echo "  </tr>" >> "$OUTPUT_FILE"
    done

    echo "</table><br>" >> "$OUTPUT_FILE"
}

#########################################
# 5.4 SQL ordered by Executions
#########################################

function check_sql_order_by_executions() {
    echo "<h4 id=\"check54\">5.4 SQL ordered by Executions</h4>" >> "$OUTPUT_FILE"
    # 说明：记录巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时内 SQL 执行次数信息 TOP 15，按照从大到小的顺序排列。
    echo "<p>记录巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时内 SQL 执行次数信息 TOP 15，按照从大到小的顺序排列。</p>" >> "$OUTPUT_FILE"
    echo "<p>OLTP 系统，这部分数据比较重要；OLAP 系统重复执行的频率较低，则意义不大。</p>" >> "$OUTPUT_FILE"

    # 这里插入列的说明，与截图要求对应
    echo "<ul>" >> "$OUTPUT_FILE"
    echo "  <li><b>Executions</b>：SQL 执行总次数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Elap Per Exec(s)</b>：每次执行平均 SQL 耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Parse Per Exec(s)</b>：每次执行平均解析耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Compile Per Exec(s)</b>：每次执行平均编译耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Min query Time(s)</b>：SQL 最小执行耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Max query Time(s)</b>：SQL 最大执行耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Avg total keys</b>：Coprocessor 扫过的 key 的平均数量</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Avg processed keys</b>：Coprocessor 处理的 key 的平均数量（不包含 MVCC）</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Time Percentage</b>：巡检时间内 SQL 总体耗时占比</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Digest</b>：SQL 指纹</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Text</b>：SQL 文本</li>" >> "$OUTPUT_FILE"
    echo "</ul>" >> "$OUTPUT_FILE"

    # 1) 获取过去 INSPECTION_WINDOW_MINUTES 分钟内所有 SQL 的总耗时(秒)，用于计算占比
    local insp_time
    insp_time=$(run_sql "
SELECT
  COALESCE(SUM(sum_latency)/1000000000, 0)
FROM information_schema.cluster_statements_summary_history a
WHERE a.summary_begin_time <= NOW()
  AND a.summary_end_time >= DATE_ADD(NOW(), INTERVAL - ${INSPECTION_WINDOW_MINUTES} MINUTE)
  AND a.query_sample_text NOT LIKE '%/*+ monitoring */%';
    " 2>/dev/null)

    # 如果 insp_time 为空或 0，则不再往下处理
    if [[ -z "$insp_time" || "$insp_time" == "0" ]]; then
        echo "<p><b>在最近 ${INSPECTION_WINDOW_HOURS} 小时内无有效 SQL 统计信息，或总耗时为 0。</b></p>" >> "$OUTPUT_FILE"
        return
    fi

    # 2) 查询“按执行次数”排序的 SQL 列表
    local result
    result=$(run_sql "
/*+ monitoring */ SELECT
       DENSE_RANK() OVER w AS total_execs_rank,
       aaa.total_execs,
       aaa.avg_latency_s,
       aaa.avg_parse_latency_s,
       aaa.avg_compile_latency_s,
       aaa.min_latency_s,
       aaa.max_latency_s,
       aaa.avg_total_keys,
       aaa.avg_processed_keys,
       aaa.percentage,
       aaa.sql_digest,
       aaa.sql_text
  FROM (
      SELECT
          SUM(exec_count)                  AS total_execs,
          AVG(avg_latency)/1000000000      AS avg_latency_s,
          AVG(avg_parse_latency)/1000000000    AS avg_parse_latency_s,
          AVG(avg_compile_latency)/1000000000  AS avg_compile_latency_s,
          MIN(min_latency)/1000000000      AS min_latency_s,
          MAX(max_latency)/1000000000      AS max_latency_s,
          AVG(avg_total_keys)              AS avg_total_keys,
          AVG(avg_processed_keys)          AS avg_processed_keys,
          ROUND(SUM(sum_latency)/1000000000/${insp_time}* 100, 2) AS percentage,
          DIGEST                           AS sql_digest,
          MIN(QUERY_SAMPLE_TEXT)           AS sql_text
        FROM information_schema.cluster_statements_summary_history a
       WHERE a.summary_begin_time <= NOW()
         AND a.summary_end_time >= DATE_ADD(NOW(), INTERVAL - ${INSPECTION_WINDOW_MINUTES} MINUTE)
         AND a.query_sample_text NOT LIKE '%/*+ monitoring */%'
       GROUP BY SAMPLE_USER, DIGEST, SCHEMA_NAME
  ) aaa
  WINDOW w AS (ORDER BY total_execs DESC)
  LIMIT 15;
    " 2>/dev/null)

    # 3) 将结果写入 HTML 表格
    echo "<table>" >> "$OUTPUT_FILE"
    echo "  <tr>" >> "$OUTPUT_FILE"
    echo "    <th>Executions</th>" >> "$OUTPUT_FILE"
    echo "    <th>Elap Per Exec(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Parse Per Exec(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Compile Per Exec(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Min query Time(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Max query Time(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Avg total keys</th>" >> "$OUTPUT_FILE"
    echo "    <th>Avg processed keys</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Time Percentage</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Digest</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Text</th>" >> "$OUTPUT_FILE"
    echo "  </tr>" >> "$OUTPUT_FILE"

    # 逐行解析: total_execs_rank total_execs avg_latency_s avg_parse_latency_s ...
    echo "$result" | while IFS=$'\t' read -r rank total_execs avg_latency_s \
                          avg_parse_s avg_compile_s min_latency_s max_latency_s \
                          avg_total_keys avg_processed_keys percentage sql_digest sql_text
    do
        # 格式化数值
        avg_latency_s=$(printf "%.3f" "$avg_latency_s")
        avg_parse_s=$(printf "%.3f" "$avg_parse_s")
        avg_compile_s=$(printf "%.3f" "$avg_compile_s")
        min_latency_s=$(printf "%.3f" "$min_latency_s")
        max_latency_s=$(printf "%.3f" "$max_latency_s")
        avg_total_keys=$(printf "%.0f" "$avg_total_keys")
        avg_processed_keys=$(printf "%.0f" "$avg_processed_keys")
        percentage=$(printf "%.2f%%" "$(echo "$percentage" | bc)")

        echo "  <tr>" >> "$OUTPUT_FILE"
        echo "    <td>$total_execs</td>" >> "$OUTPUT_FILE"
        echo "    <td>$avg_latency_s</td>" >> "$OUTPUT_FILE"
        echo "    <td>$avg_parse_s</td>" >> "$OUTPUT_FILE"
        echo "    <td>$avg_compile_s</td>" >> "$OUTPUT_FILE"
        echo "    <td>$min_latency_s</td>" >> "$OUTPUT_FILE"
        echo "    <td>$max_latency_s</td>" >> "$OUTPUT_FILE"
        echo "    <td>$avg_total_keys</td>" >> "$OUTPUT_FILE"
        echo "    <td>$avg_processed_keys</td>" >> "$OUTPUT_FILE"
        echo "    <td>$percentage</td>" >> "$OUTPUT_FILE"
        echo "    <td>$sql_digest</td>" >> "$OUTPUT_FILE"
        echo "    <td>${sql_text//</&lt;}</td>" >> "$OUTPUT_FILE"
        echo "  </tr>" >> "$OUTPUT_FILE"
    done

    echo "</table>" >> "$OUTPUT_FILE"
    echo "<br>" >> "$OUTPUT_FILE"
}

#########################################
# 5.5 SQL ordered by Plans
#########################################

function check_sql_order_by_plans() {
    echo "<h4 id=\"check55\">5.5 SQL ordered by Plans</h4>" >> "$OUTPUT_FILE"
    echo "<p>记录巡检时间窗 ${INSPECTION_WINDOW_HOURS} 小时内 SQL 执行计划变化 TOP 15，按照执行计划变化次数由大到小排序。</p>" >> "$OUTPUT_FILE"

    # 插入列说明，参考你的截图
    echo "<ul>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL plans</b>：SQL 执行计划变化数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Elapsed Time(s)</b>：SQL 执行总耗时</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Executions</b>：SQL 执行总次数</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Min sql Plan(s)</b>：耗时最小的执行计划耗时 (plan elapsed, plan digest)</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Max sql Plan(s)</b>：耗时最大的执行计划耗时 (plan elapsed, plan digest)</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Avg total keys</b>：Coprocessor 扫过的 key 的平均数量</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>Avg processed keys</b>：Coprocessor 处理的 key 的平均数量（不包含 MVCC）</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Time Percentage</b>：巡检时间占 SQL 总体耗时占比</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Digest</b>：SQL 指纹</li>" >> "$OUTPUT_FILE"
    echo "  <li><b>SQL Text</b>：SQL 文本</li>" >> "$OUTPUT_FILE"
    echo "</ul>" >> "$OUTPUT_FILE"

    # 1) 获取指定时间窗内所有 SQL 总耗时 (秒)，用来计算占比
    local insp_time
    insp_time=$(run_sql "
SELECT
  COALESCE(SUM(sum_latency)/1000000000, 0)
FROM information_schema.cluster_statements_summary_history a
WHERE a.summary_begin_time <= NOW()
  AND a.summary_end_time >= DATE_ADD(NOW(), INTERVAL - ${INSPECTION_WINDOW_MINUTES} MINUTE)
  AND a.query_sample_text NOT LIKE '%/*+ monitoring */%';
    " 2>/dev/null)

    # 若 insp_time 为空或 0，则不再继续
    if [[ -z "$insp_time" || "$insp_time" == "0" ]]; then
        echo "<p><b>在最近 ${INSPECTION_WINDOW_HOURS} 小时内无有效 SQL 统计信息，或总耗时为 0。</b></p>" >> "$OUTPUT_FILE"
        return
    fi

    # 2) 执行主查询，获取 plan_digest_counts > 1 且按执行次数降序排名前 15
    local result
    result=$(run_sql "
/*+ monitoring */ SELECT DENSE_RANK() OVER w AS 'plan_counts_rank', aaa.*
FROM (
    SELECT
        COUNT(DISTINCT plan_digest) AS plan_digest_counts,
        ROUND(SUM(sum_latency) / 1000000000, 3) AS total_latency_s,
        SUM(exec_count) AS total_execs,
        CONCAT(ROUND(MIN(min_latency) / 1000000000, 3), ' , ', (
            SELECT plan_digest
            FROM information_schema.cluster_statements_summary_history sub_min
            WHERE sub_min.DIGEST = a.DIGEST
                AND sub_min.sample_user = a.SAMPLE_USER
                AND sub_min.schema_name = a.SCHEMA_NAME 
                AND sub_min.summary_begin_time <= NOW()
                AND sub_min.summary_end_time >= DATE_ADD(NOW(), INTERVAL - ${INSPECTION_WINDOW_MINUTES} MINUTE)
                AND sub_min.QUERY_SAMPLE_TEXT NOT LIKE '%/*+ monitoring */%'
            ORDER BY min_latency ASC
            LIMIT 1
        )) AS plan_digest_for_min_latency,
        CONCAT(ROUND(MAX(max_latency) / 1000000000, 3), ' , ', (
            SELECT plan_digest
            FROM information_schema.cluster_statements_summary_history sub_max
            WHERE sub_max.DIGEST = a.DIGEST
                AND sub_max.sample_user = a.SAMPLE_USER
                AND sub_max.schema_name = a.SCHEMA_NAME 
                AND sub_max.summary_begin_time <= NOW()
                AND sub_max.summary_end_time >= DATE_ADD(NOW(), INTERVAL - ${INSPECTION_WINDOW_MINUTES} MINUTE)
                AND sub_max.QUERY_SAMPLE_TEXT NOT LIKE '%/*+ monitoring */%'
            ORDER BY max_latency DESC
            LIMIT 1
        )) AS plan_digest_for_max_latency,
        ROUND(AVG(AVG_TOTAL_KEYS)) AS avg_total_keys,
        ROUND(AVG(AVG_PROCESSED_KEYS)) AS avg_processed_keys,
        ROUND(SUM(sum_latency)/1000000000/${insp_time} * 100, 2) AS percentage,
        DIGEST AS sql_digest,
        MIN(QUERY_SAMPLE_TEXT) AS sql_text
    FROM information_schema.cluster_statements_summary_history a
    WHERE a.summary_begin_time <= NOW()
        AND summary_end_time >= DATE_ADD(NOW(), INTERVAL - ${INSPECTION_WINDOW_MINUTES} MINUTE)
        AND a.QUERY_SAMPLE_TEXT NOT LIKE '%/*+ monitoring */%'
    GROUP BY
        SAMPLE_USER,
        DIGEST,
        SCHEMA_NAME
    HAVING COUNT(DISTINCT plan_digest) > 1
) aaa WINDOW w AS (
    ORDER BY plan_digest_counts DESC
) LIMIT 15;
    " 2>/dev/null)

    # 3) 写入 HTML 表格
    echo "<table>" >> "$OUTPUT_FILE"
    echo "  <tr>" >> "$OUTPUT_FILE"
    echo "    <th>SQL plans</th>" >> "$OUTPUT_FILE"
    echo "    <th>Elapsed Time(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Executions</th>" >> "$OUTPUT_FILE"
    echo "    <th>Min sql Plan(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Max sql Plan(s)</th>" >> "$OUTPUT_FILE"
    echo "    <th>Avg total keys</th>" >> "$OUTPUT_FILE"
    echo "    <th>Avg processed keys</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL Time Percentage</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL digest</th>" >> "$OUTPUT_FILE"
    echo "    <th>SQL text</th>" >> "$OUTPUT_FILE"
    echo "  </tr>" >> "$OUTPUT_FILE"

    # result 每行字段：
    # plan_counts_rank, plan_digest_counts, total_latency_s, total_execs,
    # plan_digest_for_min_latency, plan_digest_for_max_latency,
    # avg_total_keys, avg_processed_keys, percentage, sql_digest, sql_text
    echo "$result" | while IFS=$'\t' read -r rank plan_digest_counts total_latency_s total_execs \
                                plan_digest_for_min_latency plan_digest_for_max_latency \
                                avg_total_keys avg_processed_keys percentage sql_digest sql_text
    do
        # 确保数值格式
        formatted_total_latency_s=$(printf "%.3f" "$total_latency_s")
        formatted_percentage=$(printf "%.2f" "$percentage")
        
        echo "  <tr>" >> "$OUTPUT_FILE"
        echo "    <td>$plan_digest_counts</td>" >> "$OUTPUT_FILE"
        echo "    <td>$formatted_total_latency_s</td>" >> "$OUTPUT_FILE"
        echo "    <td>$total_execs</td>" >> "$OUTPUT_FILE"
        echo "    <td>${plan_digest_for_min_latency//</&lt;}</td>" >> "$OUTPUT_FILE"
        echo "    <td>${plan_digest_for_max_latency//</&lt;}</td>" >> "$OUTPUT_FILE"
        echo "    <td>$avg_total_keys</td>" >> "$OUTPUT_FILE"
        echo "    <td>$avg_processed_keys</td>" >> "$OUTPUT_FILE"
        echo "    <td>${formatted_percentage}%</td>" >> "$OUTPUT_FILE"  # 添加了 '%' 符号
        echo "    <td>$sql_digest</td>" >> "$OUTPUT_FILE"
        echo "    <td>${sql_text//</&lt;}</td>" >> "$OUTPUT_FILE"
        echo "  </tr>" >> "$OUTPUT_FILE"
    done

    echo "</table>" >> "$OUTPUT_FILE"
    echo "<br>" >> "$OUTPUT_FILE"
}

#########################################
# 调用函数顺序和前台打印文字的逻辑
#########################################

# 确认在modules配置中为true(注意大小写、空格)
if [[ "${MODULES_CONF[check_hardware_info],,}" == "true" ]]; then
	echo "正在执行 3.1 硬件信息检查..."
    check_hardware_info
fi


if [[ "${MODULES_CONF[check_software_info],,}" == "true" ]]; then
    echo "正在执行 3.2 软件信息检查..."
    check_software_info
fi

if [[ "${MODULES_CONF[check_tidb_overview],,}" == "true" ]]; then
	echo "正在执行 3.3 数据库概览检查..."
    check_tidb_overview
fi

if [[ "${MODULES_CONF[check_dev_best_practices],,}" == "true" ]]; then
	echo "正在执行 3.4 开发最佳实践检查..."
    check_dev_best_practices
fi

if [[ "${MODULES_CONF[check_db_params],,}" == "true" ]]; then
	echo "正在执行 3.5 参数最佳实践检查..."
    check_db_params
fi

if [[ "${MODULES_CONF[check_stats_best_practices],,}" == "true" ]]; then
    echo "正在执行 3.6 统计信息最佳实践检查..."
    check_stats_best_practices
fi

if [[ "${MODULES_CONF[check_sys_config],,}" == "true" ]]; then
    echo "正在执行 3.7 系统配置最佳实践检查..."
    check_sys_config
fi

if [[ "${MODULES_CONF[check_crontab],,}" == "true" ]]; then
	echo "正在执行 3.8 crontab 信息检查..."
    check_crontab
fi

if [[ "${MODULES_CONF[check_dmesg_logs],,}" == "true" ]]; then
	echo "正在执行 3.9 dmesg 信息检查..."
    check_dmesg_logs
fi

if [[ "${MODULES_CONF[check_db_error_logs],,}" == "true" ]]; then
	echo "正在执行 3.10 错误日志检查..."
    check_db_error_logs
fi

if [[ "${MODULES_CONF[check_user_space],,}" == "true" ]]; then
	echo "正在执行 3.11 用户对象占空间分布检查..."
    check_user_space
fi

if [[ "${MODULES_CONF[check_pd_performance],,}" == "true" ]]; then
	echo "正在执行 4.1 Performance statistics by PD 的检查..."
    check_pd_performance
fi

if [[ "${MODULES_CONF[check_tidb_performance],,}" == "true" ]]; then
	echo "正在执行 4.2 Performance statistics by TiDB 的检查..."
    check_tidb_performance
fi

if [[ "${MODULES_CONF[check_tikv_performance],,}" == "true" ]]; then
	echo "正在执行 4.3 Performance statistics by TiKV 的检查..."
    check_tikv_performance
fi


if [[ "${MODULES_CONF[check_sql_order_by_tidb_cpu_time],,}" == "true" ]]; then
	echo "正在执行 5.1 SQL ordered by TiDB CPU Time 的检查..."
	pull_tidb_topsql
    check_sql_order_by_tidb_cpu_time
fi

if [[ "${MODULES_CONF[check_sql_order_by_tikv_cpu_time],,}" == "true" ]]; then
	echo "正在执行 5.2 SQL ordered by TiKV CPU Time 的检查..."
	pull_tikv_topsql
    check_sql_order_by_tikv_cpu_time
fi

if [[ "${MODULES_CONF[check_sql_order_by_elapsed_time],,}" == "true" ]]; then
	echo "正在执行 5.3 SQL ordered by Elapsed Time 的检查..."
    check_sql_order_by_elapsed_time
fi

if [[ "${MODULES_CONF[check_sql_order_by_executions],,}" == "true" ]]; then
	echo "正在执行 5.4 SQL ordered by Executions 的检查..."
    check_sql_order_by_executions
fi


if [[ "${MODULES_CONF[check_sql_order_by_plans],,}" == "true" ]]; then
	echo "正在执行 5.5 SQL ordered by Plans 的检查..."
    check_sql_order_by_plans
fi


#########################################
# 报告总结部分的逻辑
#########################################
function append_summary_item() {
    local anchor="$1"
    local title="$2"
    local status_class="$3"
    local status_label="$4"
    local detail_text="$5"

    SUMMARY_ITEMS+="<div class='summary-item summary-item-${status_class}'>"
    SUMMARY_ITEMS+="<div class='summary-meta'>"
    SUMMARY_ITEMS+="<h4><a href='#${anchor}'>${title}</a></h4>"
    SUMMARY_ITEMS+="<span class='status-badge status-${status_class}'>${status_label}</span>"
    SUMMARY_ITEMS+="</div>"
    SUMMARY_ITEMS+="<p>${detail_text}</p>"
    SUMMARY_ITEMS+="<div class='summary-link'><a href='#${anchor}'>跳转查看章节详情</a></div>"
    SUMMARY_ITEMS+="</div>"
}

function generate_summary() {
    local summary=""
    SUMMARY_ITEMS=""
    SUMMARY_OK_COUNT=0
    SUMMARY_WARN_COUNT=0
    SUMMARY_INFO_COUNT=0

    # ---- 健康评分 ----
    _finalize_issues
    local score_result
    score_result=$(calculate_health_score)
    local health_score=$(echo "$score_result" | cut -d'|' -f1)
    local health_grade=$(echo "$score_result" | cut -d'|' -f2)

    local low_count=0 medium_count=0 high_count=0 critical_count=0
    if [[ -f "$ISSUES_FILE" && -s "$ISSUES_FILE" ]]; then
        low_count=$(grep -c '^low|' "$ISSUES_FILE" 2>/dev/null) || low_count=0
        medium_count=$(grep -c '^medium|' "$ISSUES_FILE" 2>/dev/null) || medium_count=0
        high_count=$(grep -c '^high|' "$ISSUES_FILE" 2>/dev/null) || high_count=0
        critical_count=$(grep -c '^critical|' "$ISSUES_FILE" 2>/dev/null) || critical_count=0
    fi

    # 3.1 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT31}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check31" "3.1 硬件基本信息" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT31" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check31" "3.1 硬件基本信息" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check31" "3.1 硬件基本信息" "warn" "告警" "异常项：$ERROR_COUNT31"
    fi

    # 3.2 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT32}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check32" "3.2 软件基本信息" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT32" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check32" "3.2 软件基本信息" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check32" "3.2 软件基本信息" "warn" "告警" "异常项：$ERROR_COUNT32"
    fi

    # 3.3 检查结果
    if [[ "$ERROR_COUNT33" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check33" "3.3 TiDB 集群总览" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check33" "3.3 TiDB 集群总览" "warn" "告警" "异常项：$ERROR_COUNT33"
    fi

    # 3.4 检查结果
    if [[ "$ERROR_COUNT34" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check34" "3.4 开发规范最佳实践" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check34" "3.4 开发规范最佳实践" "warn" "告警" "异常项：$ERROR_COUNT34"
    fi

    # 3.5 检查结果
    if [[ "$ERROR_COUNT35" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check35" "3.5 数据库参数最佳实践" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check35" "3.5 数据库参数最佳实践" "warn" "告警" "异常项：$ERROR_COUNT35"
    fi

    # 3.6 检查结果
    if [[ "$ERROR_COUNT36" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check36" "3.6 统计信息最佳实践" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check36" "3.6 统计信息最佳实践" "warn" "告警" "异常项：$ERROR_COUNT36"
    fi

    # 3.7 检查结果
    if [[ "$ERROR_COUNT37" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check37" "3.7 系统配置最佳实践" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check37" "3.7 系统配置最佳实践" "warn" "告警" "异常项：$ERROR_COUNT37"
    fi

    # 3.8 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT38}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check38" "3.8 crontab 情况" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT38" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check38" "3.8 crontab 情况" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check38" "3.8 crontab 情况" "warn" "告警" "异常项：$ERROR_COUNT38"
    fi

    # 3.9 检查结果
    SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
    append_summary_item "check39" "3.9 dmesg 信息" "info" "信息" "信息详情请参阅报告"

    # 3.10 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT310}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check310" "3.10 数据库的错误日志统计" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT310" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check310" "3.10 数据库的错误日志统计" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check310" "3.10 数据库的错误日志统计" "warn" "告警" "异常项：$ERROR_COUNT310"
    fi

    # 3.11 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT311}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check311" "3.11 用户对象占用空间分布" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT311" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check311" "3.11 用户对象占用空间分布" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check311" "3.11 用户对象占用空间分布" "warn" "告警" "异常项：$ERROR_COUNT311"
    fi

    # 4.1 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT41}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check41" "4.1 Performance statistics by PD 检查" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT41" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check41" "4.1 Performance statistics by PD 检查" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check41" "4.1 Performance statistics by PD 检查" "warn" "告警" "异常项：$ERROR_COUNT41"
    fi

    # 4.2 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT42}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check42" "4.2 Performance statistics by TiDB 检查" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT42" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check42" "4.2 Performance statistics by TiDB 检查" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check42" "4.2 Performance statistics by TiDB 检查" "warn" "告警" "异常项：$ERROR_COUNT42"
    fi

    # 4.3 检查结果（保持原有判断逻辑）
    if [[ -z "${ERROR_COUNT43}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check43" "4.3 Performance statistics by TiKV 检查" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT41" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check43" "4.3 Performance statistics by TiKV 检查" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check43" "4.3 Performance statistics by TiKV 检查" "warn" "告警" "异常项：$ERROR_COUNT43"
    fi

    # 5.1 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT51}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check51" "5.1 SQL ordered by TiDB CPU Time 检查" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT51" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check51" "5.1 SQL ordered by TiDB CPU Time 检查" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check51" "5.1 SQL ordered by TiDB CPU Time 检查" "warn" "告警" "异常项：$ERROR_COUNT51"
    fi

    # 5.2 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT52}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check52" "5.2 SQL ordered by TiKV CPU Time 检查" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT52" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check52" "5.2 SQL ordered by TiKV CPU Time 检查" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check52" "5.2 SQL ordered by TiKV CPU Time 检查" "warn" "告警" "异常项：$ERROR_COUNT52"
    fi

    # 5.3 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT53}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check53" "5.3 SQL ordered by Elapsed Time 检查" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT53" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check53" "5.3 SQL ordered by Elapsed Time 检查" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check53" "5.3 SQL ordered by Elapsed Time 检查" "warn" "告警" "异常项：$ERROR_COUNT53"
    fi

    # 5.4 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT54}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check54" "5.4 SQL ordered by Executions 检查" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT54" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check54" "5.4 SQL ordered by Executions 检查" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check54" "5.4 SQL ordered by Executions 检查" "warn" "告警" "异常项：$ERROR_COUNT54"
    fi

    # 5.5 检查结果（支持无 ERROR_COUNT 变量的情况）
    if [[ -z "${ERROR_COUNT55}" ]]; then
        SUMMARY_INFO_COUNT=$((SUMMARY_INFO_COUNT + 1))
        append_summary_item "check55" "5.5 SQL ordered by Plans 检查" "info" "信息" "信息详情请参阅报告"
    elif [[ "$ERROR_COUNT55" -eq 0 ]]; then
        SUMMARY_OK_COUNT=$((SUMMARY_OK_COUNT + 1))
        append_summary_item "check55" "5.5 SQL ordered by Plans 检查" "ok" "正常" "未发现异常"
    else
        SUMMARY_WARN_COUNT=$((SUMMARY_WARN_COUNT + 1))
        append_summary_item "check55" "5.5 SQL ordered by Plans 检查" "warn" "告警" "异常项：$ERROR_COUNT55"
    fi

    # 评分颜色
    local score_color="#166534"
    local card_bg="" card_text_color="" card_border=""
    [[ $health_grade == *"良好"* ]] && score_color="#ca8a04"
    [[ $health_grade == *"一般"* ]] && score_color="#ea580c"
    [[ $health_grade == *"警告"* ]] && score_color="#dc2626"
    if [[ $health_grade == *"危险"* ]]; then
        card_bg="background:linear-gradient(135deg,#7f1d1d 0%,#dc2626 100%);"
        card_text_color="color:#fff;"
        card_border="border-color:#991b1b;"
    else
        card_border="border-color:${score_color};"
    fi

    summary+="<section class='summary-panel' id='summary'>"
    summary+="<h3>二、检查总结</h3>"

    # 健康评分卡片
    summary+="<div class='summary-overview'>"
    summary+="<div class='metric-card' style='${card_bg}${card_border}'>"
    summary+="<span class='metric-label' style='${card_text_color}'>健康评分</span>"
    # 处理建议
    local advice=""
    if [[ $health_grade == *"优秀"* ]]; then
        advice="集群健康，继续保持"
    elif [[ $health_grade == *"良好"* ]]; then
        advice="存在轻微问题，建议优化"
    elif [[ $health_grade == *"一般"* ]]; then
        advice="存在明显风险，需要安排处理"
    elif [[ $health_grade == *"警告"* ]]; then
        advice="存在严重问题，需立即处理"
    else
        advice="存在 Critical 级别问题或大量高危问题，必须紧急干预"
    fi
    # 分数 + 评分等级同行同字号(28px)，建议文案留在小字说明行
    if [[ $health_grade == *"危险"* ]]; then
        summary+="<span class='metric-value' style='color:#fff;'>${health_score}<span class='metric-grade'>${health_grade}</span></span>"
        summary+="<span class='metric-note' style='color:#fff;'>${advice}</span>"
    else
        summary+="<span class='metric-value' style='color:${score_color};'>${health_score}<span class='metric-grade'>${health_grade}</span></span>"
        summary+="<span class='metric-note' style='color:${score_color};'>${advice}</span>"
    fi
    summary+="</div>"
    summary+="<div class='metric-card'><span class='metric-label'>巡检章节</span><span class='metric-value'>$((SUMMARY_OK_COUNT + SUMMARY_WARN_COUNT + SUMMARY_INFO_COUNT))</span></div>"
    summary+="<button type='button' class='metric-card metric-card-action' id='warn-only-toggle'><span class='metric-label'>告警章节</span><span class='metric-value'>${SUMMARY_WARN_COUNT}</span><span class='metric-note'>点击只显示告警章节</span></button>"
    summary+="<div class='metric-card'><span class='metric-label'>信息章节</span><span class='metric-value'>${SUMMARY_INFO_COUNT}</span></div>"
    summary+="</div>"

    # 问题分布 - 根据数量动态应用样式
    summary+="<div class='summary-overview' style='margin-top:8px;'>"

    # 低危卡片
    if [[ $low_count -gt 0 ]]; then
        summary+="<button type='button' class='metric-card issue-filter-card issue-low' data-severity='low' onclick='filterIssuesBySeverity(\"low\")'><span class='metric-label'>低危</span><span class='metric-value'>${low_count}</span><span class='metric-note'>每项扣1分</span></button>"
    else
        summary+="<div class='metric-card'><span class='metric-label'>低危</span><span class='metric-value'>${low_count}</span><span class='metric-note'>每项扣1分</span></div>"
    fi

    # 中危卡片
    if [[ $medium_count -gt 0 ]]; then
        summary+="<button type='button' class='metric-card issue-filter-card issue-medium' data-severity='medium' onclick='filterIssuesBySeverity(\"medium\")'><span class='metric-label'>中危</span><span class='metric-value'>${medium_count}</span><span class='metric-note'>每项扣3分</span></button>"
    else
        summary+="<div class='metric-card'><span class='metric-label'>中危</span><span class='metric-value'>${medium_count}</span><span class='metric-note'>每项扣3分</span></div>"
    fi

    # 高危卡片
    if [[ $high_count -gt 0 ]]; then
        summary+="<button type='button' class='metric-card issue-filter-card issue-high' data-severity='high' onclick='filterIssuesBySeverity(\"high\")'><span class='metric-label'>高危</span><span class='metric-value'>${high_count}</span><span class='metric-note'>每项扣5分</span></button>"
    else
        summary+="<div class='metric-card'><span class='metric-label'>高危</span><span class='metric-value'>${high_count}</span><span class='metric-note'>每项扣5分</span></div>"
    fi

    # Critical卡片
    if [[ $critical_count -gt 0 ]]; then
        summary+="<button type='button' class='metric-card issue-filter-card issue-critical' data-severity='critical' onclick='filterIssuesBySeverity(\"critical\")'><span class='metric-label'>Critical</span><span class='metric-value'>${critical_count}</span><span class='metric-note'>每项扣10分</span></button>"
    else
        summary+="<div class='metric-card'><span class='metric-label'>Critical</span><span class='metric-value'>${critical_count}</span><span class='metric-note'>每项扣10分</span></div>"
    fi

    summary+="</div>"

    summary+="<div class='summary-grid'>${SUMMARY_ITEMS}</div>"

    # 问题详情表
    summary+="<h3 id='issues-detail' style='margin-top:24px;'>问题详情</h3>"
    summary+="$(generate_issues_html)"

    summary+="</section>"

    echo "$summary"
}


# 生成检查总结并替换占位符
summary_content=$(generate_summary)
# 用 awk 替代 sed，避免 $summary_content 中包含 @ / 换行 / & 等特殊字符导致 sed 命令被破坏
tmp_file=$(mktemp)
awk -v repl="$summary_content" '{
    if (index($0, "<!-- SUMMARY_PLACEHOLDER -->") > 0) {
        sub(/<!-- SUMMARY_PLACEHOLDER -->/, repl)
    }
    print
}' "$OUTPUT_FILE" > "$tmp_file" && mv "$tmp_file" "$OUTPUT_FILE"


cat <<EOF >> "$OUTPUT_FILE"
<script>
<!--

// 问题详情展开/收起
function toggleDesc(link, rowId) {
    var hidden = document.getElementById('hidden-' + rowId);
    if (!hidden) return;
    var cell = link.closest('.collapsible-cell');
    var isHidden = hidden.style.display === 'none';
    if (isHidden) {
        // 展开：先移除按钮和隐藏内容，再按 hidden → link 的顺序插回末尾，使“收起”位于最后一行
        cell.removeChild(link);
        cell.removeChild(hidden);
        cell.appendChild(hidden);
        cell.appendChild(link);
        hidden.style.display = 'block';
        link.textContent = '收起';
        link.classList.add('expanded');
    } else {
        // 收起：把按钮移回可见内容之后、隐藏内容之前
        cell.removeChild(link);
        cell.removeChild(hidden);
        hidden.style.display = 'none';
        // 插入到 cell 中所有 <br> 之后的第一个非<br元素之前（即隐藏div应该在的位置）
        cell.appendChild(link);
        cell.appendChild(hidden);
        // 更新按钮文字
        var total = parseInt(cell.getAttribute('data-total') || '0');
        var visible = parseInt(cell.getAttribute('data-visible') || '5');
        var remaining = total - visible;
        link.textContent = '… 还有 ' + remaining + ' 行，点击展开';
        link.classList.remove('expanded');
    }
}

document.addEventListener('DOMContentLoaded', function () {
    var summaryWarnIds = new Set(
        Array.prototype.map.call(document.querySelectorAll('.summary-item .status-warn'), function (badge) {
            var link = badge.closest('.summary-item').querySelector('h4 a');
            return link ? (link.getAttribute('href') || '').replace('#', '') : '';
        }).filter(Boolean)
    );

    Array.prototype.forEach.call(document.querySelectorAll('h4[id^="check"]'), function (heading) {
        if (!heading.querySelector('.back-to-summary')) {
            var backLink = document.createElement('a');
            backLink.className = 'back-to-summary';
            backLink.href = '#summary';
            backLink.textContent = '返回检查总结';
            heading.appendChild(backLink);
        }
    });

    Array.prototype.forEach.call(document.querySelectorAll('table'), function (table) {
        var headerTexts = Array.prototype.map.call(table.querySelectorAll('th'), function (th) {
            return (th.textContent || '').replace(/\s+/g, ' ').trim();
        });
        var scrollColumns = [];

        headerTexts.forEach(function (text, index) {
            if (/SQL Text|异常情况|异常描述/.test(text)) {
                scrollColumns.push(index);
            }
        });

        if (scrollColumns.length > 0) {
            table.classList.add('table-text-heavy');
        }

        Array.prototype.forEach.call(table.rows, function (row, rowIndex) {
            if (rowIndex === 0) {
                return;
            }

            scrollColumns.forEach(function (cellIndex) {
                var cell = row.cells[cellIndex];
                if (!cell || cell.querySelector('.cell-scroll-y')) {
                    return;
                }

                var scroller = document.createElement('div');
                scroller.className = 'cell-scroll-y';

                while (cell.firstChild) {
                    scroller.appendChild(cell.firstChild);
                }

                cell.dataset.longText = 'true';
                cell.appendChild(scroller);
            });
        });
    });

    var sectionHeadings = Array.prototype.slice.call(document.querySelectorAll('h4[id^="check"]'));
    sectionHeadings.forEach(function (heading) {
        var section = document.createElement('section');
        section.className = 'report-section';
        section.dataset.sectionId = heading.id;

        if (summaryWarnIds.has(heading.id)) {
            section.classList.add('is-warn');
        }

        heading.parentNode.insertBefore(section, heading);
        section.appendChild(heading);

        var next = section.nextSibling;
        while (next && !(next.nodeType === 1 && (next.matches('h4[id^="check"]') || next.matches('h3')))) {
            var current = next;
            next = next.nextSibling;
            section.appendChild(current);
        }
    });

    var sqlChapterHeading = Array.prototype.find.call(document.querySelectorAll('.report-shell > h3.filterable-chapter'), function (heading) {
        return /五、SQL Statistics/.test(heading.textContent || '');
    });
    if (sqlChapterHeading) {
        var sqlContainer = sqlChapterHeading.parentNode;
        var nextChapter = sqlChapterHeading.nextElementSibling;
        while (nextChapter && !nextChapter.matches('h3.filterable-chapter')) {
            nextChapter = nextChapter.nextElementSibling;
        }

        ['check51', 'check52', 'check53', 'check54', 'check55'].forEach(function (id) {
            var section = sqlContainer.querySelector('.report-section[data-section-id="' + id + '"]');
            if (section) {
                if (nextChapter) {
                    sqlContainer.insertBefore(section, nextChapter);
                } else {
                    sqlContainer.appendChild(section);
                }
            }
        });
    }

    var warnToggle = document.getElementById('warn-only-toggle');
    var sections = Array.prototype.slice.call(document.querySelectorAll('.report-section'));
    var summaryItems = Array.prototype.slice.call(document.querySelectorAll('.summary-item'));
    var chapterBlocks = Array.prototype.map.call(document.querySelectorAll('.report-shell > h3.filterable-chapter'), function (heading) {
        var nodes = [];
        var next = heading.nextElementSibling;

        while (next && !next.matches('h3.filterable-chapter')) {
            nodes.push(next);
            next = next.nextElementSibling;
        }

        return {
            heading: heading,
            nodes: nodes
        };
    });

    function updateChapterVisibility(showWarnOnly) {
        chapterBlocks.forEach(function (block) {
            if (!showWarnOnly) {
                block.heading.classList.remove('is-hidden');
                block.nodes.forEach(function (node) {
                    node.classList.remove('chapter-extra');
                    node.classList.remove('is-hidden');
                });
                return;
            }

            var hasVisibleSection = block.nodes.some(function (node) {
                return node.matches('.report-section') && !node.classList.contains('is-hidden');
            });

            block.heading.classList.toggle('is-hidden', !hasVisibleSection);

            block.nodes.forEach(function (node) {
                if (!node.matches('.report-section')) {
                    node.classList.toggle('chapter-extra', true);
                    node.classList.toggle('is-hidden', !hasVisibleSection);
                }
            });
        });
    }

    function applyWarnFilter(showWarnOnly) {
        sections.forEach(function (section) {
            section.classList.toggle('is-hidden', showWarnOnly && !section.classList.contains('is-warn'));
        });

        summaryItems.forEach(function (item) {
            item.classList.toggle('is-hidden', showWarnOnly && !item.classList.contains('summary-item-warn'));
        });

        if (warnToggle) {
            warnToggle.classList.toggle('active', showWarnOnly);
        }

        updateChapterVisibility(showWarnOnly);

        if (showWarnOnly) {
            location.hash = 'summary';
        }
    }

    if (warnToggle) {
        warnToggle.addEventListener('click', function () {
            applyWarnFilter(!warnToggle.classList.contains('active'));
        });
    }

    applyWarnFilter(false);
});

// 问题级别筛选功能 - 全局函数，移到DOMContentLoaded外面
window.filterIssuesBySeverity = function(severity) {
    var currentCard = document.querySelector('.issue-filter-card[data-severity="' + severity + '"]');
    var isCurrentlyActive = currentCard && currentCard.classList.contains('active');

    // 移除所有问题级别卡片的激活状态
    document.querySelectorAll('.issue-filter-card').forEach(function(card) {
        card.classList.remove('active');
    });

    // 如果当前卡片已经是激活状态，则取消筛选，显示所有问题
    if (isCurrentlyActive) {
        var issuesTable = document.querySelector('.issues-table');
        if (issuesTable) {
            var rows = issuesTable.querySelectorAll('tbody tr');
            rows.forEach(function(row) {
                row.style.display = '';
            });
        }
        return; // 取消筛选时不需要跳转
    }

    // 激活当前点击的卡片
    if (currentCard) {
        currentCard.classList.add('active');
    }

    // 筛选问题详情表中的行
    var issuesTable = document.querySelector('.issues-table');
    if (issuesTable) {
        var rows = issuesTable.querySelectorAll('tbody tr');
        rows.forEach(function(row) {
            var rowSeverity = row.getAttribute('data-severity');
            if (rowSeverity === severity) {
                row.style.display = '';
            } else {
                row.style.display = 'none';
            }
        });
    }

    // 跳转到问题详情
    setTimeout(function() {
        var issuesDetail = document.getElementById('issues-detail');
        if (issuesDetail) {
            issuesDetail.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }, 100);
};
// -->
</script>
</div>
</body>
</html>
EOF

echo "检查信息已保存到 $OUTPUT_FILE"
