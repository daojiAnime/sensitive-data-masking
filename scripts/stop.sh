#!/bin/bash
set -euo pipefail

# ============================================
# Sensitive Data Masking 停止脚本
# ============================================

VERSION="1.0.0"

# 默认配置
REMOVE_VOLUMES=false
FORCE=false
TIMEOUT=30

# 颜色定义
setup_colors() {
    if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
        CYAN='\033[0;36m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        RED='\033[0;31m'
        BLUE='\033[0;34m'
        MAGENTA='\033[0;35m'
        BOLD='\033[1m'
        DIM='\033[2m'
        NC='\033[0m'
        USE_SPINNER=true
    else
        CYAN='' GREEN='' YELLOW='' RED='' BLUE=''
        MAGENTA='' BOLD='' DIM='' NC=''
        USE_SPINNER=false
    fi
}

# 帮助信息
show_help() {
    cat << EOF
${BOLD}Sensitive Data Masking 停止脚本${NC} v${VERSION}

${BOLD}用法:${NC}
    $0 [选项]

${BOLD}选项:${NC}
    -h, --help          显示帮助信息
    -f, --force         跳过确认，直接停止
    -v, --volumes       同时删除数据卷
    -t, --timeout NUM   停止超时时间（秒），默认 ${TIMEOUT}
    --version           显示版本信息

${BOLD}示例:${NC}
    $0                  # 交互式停止
    $0 -f               # 强制停止（无确认）
    $0 -f -v            # 强制停止并删除数据卷
EOF
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--volumes)
                REMOVE_VOLUMES=true
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --version)
                echo "Sensitive Data Masking Stopper v${VERSION}"
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知参数 $1${NC}"
                echo "使用 --help 查看帮助"
                exit 1
                ;;
        esac
    done
}

# 日志函数
log_success() { echo -e "  ${GREEN}✓${NC} $1"; }
log_error() { echo -e "  ${RED}✗${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}!${NC} $1"; }

# 旋转动画
spin() {
    local pid=$1
    local message=$2

    if [[ "$USE_SPINNER" != true ]]; then
        echo -e "  ... $message"
        wait "$pid" 2>/dev/null
        return
    fi

    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while ps -p "$pid" > /dev/null 2>&1; do
        for i in $(seq 0 9); do
            printf "\r${CYAN}  ${spinstr:$i:1}${NC} %s" "$message"
            sleep $delay
        done
    done
    printf "\r\033[K"
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Banner
show_banner() {
    if [[ "$USE_SPINNER" == true ]]; then
        clear
    fi

    echo -e "${RED}"
    if [[ -f "${SCRIPT_DIR}/project_name.txt" ]]; then
        cat "${SCRIPT_DIR}/project_name.txt"
        echo "                                              ■ STOP ■"
    else
        echo "Sensitive Data Masking  ■ STOP ■"
    fi
    echo -e "${NC}"

    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▸${NC} ${BOLD}Time${NC}       $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${BLUE}▸${NC} ${BOLD}Action${NC}     Stop Services$([ "$REMOVE_VOLUMES" == true ] && echo " ${RED}+ Remove Volumes${NC}" || echo "")"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# 显示当前运行状态
show_current_status() {
    echo -e "${YELLOW}[1/3]${NC} ${BOLD}Current status...${NC}"

    cd "$PROJECT_DIR"
    local running=$(docker compose ps -q 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$running" -eq 0 ]]; then
        log_warn "没有运行中的容器"
        echo
        exit 0
    fi

    echo -e "  ${DIM}运行中的容器:${NC}"
    docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        if [[ "$line" == *"Up"* ]] || [[ "$line" == *"running"* ]] || [[ "$line" == *"healthy"* ]]; then
            echo -e "    ${GREEN}●${NC} $line"
        else
            echo -e "    ${YELLOW}●${NC} $line"
        fi
    done
    echo
}

# 确认操作
confirm_stop() {
    if [[ "$FORCE" == true ]]; then
        return 0
    fi

    echo -e "${YELLOW}[2/3]${NC} ${BOLD}Confirm...${NC}"

    if [[ "$REMOVE_VOLUMES" == true ]]; then
        echo -e "  ${RED}${BOLD}警告: 将删除所有数据卷！${NC}"
        echo
        read -p "  确认删除数据卷? (输入 'yes' 确认): " confirm
        if [[ "$confirm" != "yes" ]]; then
            echo
            log_error "操作已取消"
            exit 1
        fi
    else
        read -p "  确认停止服务? [Y/n]: " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            echo
            log_error "操作已取消"
            exit 1
        fi
    fi
    echo
}

# 停止服务
stop_services() {
    echo -e "${YELLOW}[3/3]${NC} ${BOLD}Stopping services...${NC}"

    cd "$PROJECT_DIR"
    local down_args="-t $TIMEOUT"
    if [[ "$REMOVE_VOLUMES" == true ]]; then
        down_args="$down_args -v"
    fi

    docker compose down $down_args > /dev/null 2>&1 &
    local down_pid=$!
    spin $down_pid "Stopping containers..."

    if ! wait $down_pid; then
        log_error "停止服务失败"
        exit 1
    fi

    log_success "所有容器已停止"

    if [[ "$REMOVE_VOLUMES" == true ]]; then
        log_success "数据卷已删除"
    fi
    echo
}

# 完成
show_complete() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}■ Sensitive Data Masking stopped${NC}"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${DIM}重新启动:${NC}"
    echo -e "  ${BOLD}./scripts/start.sh${NC}               # 完整启动"
    echo -e "  ${BOLD}./scripts/start.sh --no-build${NC}    # 快速启动（跳过构建）"
    echo
}

# ============================================
# 主流程
# ============================================
main() {
    setup_colors
    parse_args "$@"
    show_banner
    show_current_status
    confirm_stop
    stop_services
    show_complete
}

main "$@"
