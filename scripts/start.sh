#!/bin/bash
set -euo pipefail

# ============================================
# Sensitive Data Masking 启动脚本
# ============================================

VERSION="1.0.0"

# 默认配置
VERBOSE=false
NO_BUILD=false
HEALTH_TIMEOUT=60
GRADIO_PORT=7860

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
${BOLD}Sensitive Data Masking 启动脚本${NC} v${VERSION}

${BOLD}用法:${NC}
    $0 [选项]

${BOLD}选项:${NC}
    -h, --help          显示帮助信息
    -v, --verbose       详细输出模式
    -n, --no-build      跳过镜像构建
    -t, --timeout NUM   健康检查超时时间（秒），默认 ${HEALTH_TIMEOUT}
    -p, --port NUM      Gradio 服务端口，默认 ${GRADIO_PORT}
    --version           显示版本信息

${BOLD}示例:${NC}
    $0                  # 标准启动
    $0 --verbose        # 详细输出
    $0 --no-build       # 跳过构建，仅启动
    $0 -p 8080          # 使用端口 8080

${BOLD}服务地址:${NC}
    Gradio Web UI:      http://localhost:${GRADIO_PORT}
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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--no-build)
                NO_BUILD=true
                shift
                ;;
            -t|--timeout)
                HEALTH_TIMEOUT="$2"
                shift 2
                ;;
            -p|--port)
                GRADIO_PORT="$2"
                shift 2
                ;;
            --version)
                echo "Sensitive Data Masking Starter v${VERSION}"
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
log_info() { echo -e "${BLUE}▸${NC} $1"; }
log_success() { echo -e "  ${GREEN}✓${NC} $1"; }
log_error() { echo -e "  ${RED}✗${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}!${NC} $1"; }
log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "  ${DIM}$1${NC}"
    fi
}

# 旋转加载动画
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

# 显示 Banner
show_banner() {
    if [[ "$USE_SPINNER" == true ]]; then
        clear
    fi

    echo -e "${CYAN}"
    if [[ -f "${SCRIPT_DIR}/project_name.txt" ]]; then
        cat "${SCRIPT_DIR}/project_name.txt"
    else
        echo "Sensitive Data Masking"
    fi
    echo -e "${NC}"

    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▸${NC} ${BOLD}System${NC}     $(uname -s) $(uname -m)"
    echo -e "${BLUE}▸${NC} ${BOLD}Time${NC}       $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${BLUE}▸${NC} ${BOLD}Docker${NC}     $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'N/A')"
    local mode_str="Gradio Web UI"
    [[ "$VERBOSE" == true ]] && mode_str="$mode_str, Verbose"
    [[ "$NO_BUILD" == true ]] && mode_str="$mode_str, No-Build"
    echo -e "${BLUE}▸${NC} ${BOLD}Mode${NC}       ${MAGENTA}${mode_str}${NC}"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

# 检查端口
check_port() {
    local port=$1
    if lsof -i :"$port" > /dev/null 2>&1; then
        local pid=$(lsof -t -i :"$port" 2>/dev/null | head -1)
        local process=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
        log_error "端口 $port 已被占用 (PID: $pid, 进程: $process)"
        return 1
    fi
    return 0
}

# 检查端口
check_ports() {
    echo -e "${YELLOW}[1/4]${NC} ${BOLD}Checking ports...${NC}"

    if ! check_port $GRADIO_PORT; then
        echo
        log_error "请先释放端口 $GRADIO_PORT 后重试"
        exit 1
    fi

    log_success "端口 $GRADIO_PORT 可用"
    echo
}

# 检查 Docker
check_docker() {
    echo -e "${YELLOW}[2/4]${NC} ${BOLD}Checking Docker daemon...${NC}"

    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi

    if ! docker info > /dev/null 2>&1; then
        log_error "Docker daemon 未运行"
        log_error "请启动 Docker Desktop 或 docker daemon"
        exit 1
    fi

    log_success "Docker daemon 正常运行"
    log_verbose "Docker version: $(docker info --format '{{.ServerVersion}}' 2>/dev/null)"
    echo
}

# 构建镜像
build_images() {
    if [[ "$NO_BUILD" == true ]]; then
        echo -e "${YELLOW}[3/4]${NC} ${BOLD}Skipping build (--no-build)${NC}"
        log_warn "跳过镜像构建"
        echo
        return 0
    fi

    echo -e "${YELLOW}[3/4]${NC} ${BOLD}Building images...${NC}"

    local build_log=$(mktemp)
    trap "rm -f $build_log" EXIT

    cd "$PROJECT_DIR"

    if [[ "$VERBOSE" == true ]]; then
        if ! docker compose build 2>&1 | tee "$build_log"; then
            log_error "镜像构建失败"
            exit 1
        fi
    else
        docker compose build > "$build_log" 2>&1 &
        local build_pid=$!
        spin $build_pid "Building Docker image..."

        if ! wait $build_pid; then
            echo
            log_error "镜像构建失败，详细错误："
            echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            tail -30 "$build_log" | while IFS= read -r line; do
                echo -e "  ${RED}│${NC} $line"
            done
            echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            exit 1
        fi
    fi

    log_success "镜像构建成功"
    echo
}

# 启动服务
start_services() {
    echo -e "${YELLOW}[4/4]${NC} ${BOLD}Starting services...${NC}"

    cd "$PROJECT_DIR"
    local up_log=$(mktemp)

    # 设置端口环境变量
    export GRADIO_PORT

    if [[ "$VERBOSE" == true ]]; then
        if ! docker compose up -d 2>&1 | tee "$up_log"; then
            log_error "服务启动失败"
            exit 1
        fi
    else
        docker compose up -d > "$up_log" 2>&1 &
        local up_pid=$!
        spin $up_pid "Starting container..."

        if ! wait $up_pid; then
            echo
            log_error "服务启动失败"
            cat "$up_log"
            rm -f "$up_log"
            exit 1
        fi
    fi

    rm -f "$up_log"
    log_success "容器已启动"

    # 等待服务就绪
    local start_time=$(date +%s)
    while true; do
        local elapsed=$(( $(date +%s) - start_time ))

        if [[ $elapsed -ge $HEALTH_TIMEOUT ]]; then
            echo
            log_error "健康检查超时（${HEALTH_TIMEOUT}s）"
            log_error "使用 'docker compose logs' 查看详细日志"
            exit 1
        fi

        # 检查 Gradio 服务
        if curl -sf "http://localhost:${GRADIO_PORT}/" > /dev/null 2>&1; then
            log_success "Gradio 服务就绪"
            break
        fi

        if [[ "$USE_SPINNER" == true ]]; then
            printf "\r  ${CYAN}⏳${NC} 等待服务就绪... ${DIM}(${elapsed}s/${HEALTH_TIMEOUT}s)${NC}  "
        fi

        sleep 2
    done

    if [[ "$USE_SPINNER" == true ]]; then
        printf "\r\033[K"
    fi
    echo
}

# 显示运行状态
show_status() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}▸${NC} ${BOLD}Running Containers${NC}"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    cd "$PROJECT_DIR"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        if [[ "$line" == *"Up"* ]] || [[ "$line" == *"running"* ]] || [[ "$line" == *"healthy"* ]]; then
            echo -e "  ${GREEN}●${NC} $line"
        else
            echo -e "  ${YELLOW}●${NC} $line"
        fi
    done
    echo
}

# 显示服务 URL
show_urls() {
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}▸${NC} ${BOLD}Service URL${NC}"
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}Gradio Web UI${NC}       http://localhost:${GRADIO_PORT}"
    echo
}

# 完成提示
show_complete() {
    echo -e "${GREEN}${BOLD}▶ Sensitive Data Masking is ready!${NC}"
    echo
    echo -e "${DIM}常用命令:${NC}"
    echo -e "  ${BOLD}docker compose logs -f${NC}           # 查看实时日志"
    echo -e "  ${BOLD}docker compose ps${NC}                # 查看服务状态"
    echo -e "  ${BOLD}./scripts/stop.sh${NC}                # 停止服务"
    echo
}

# ============================================
# 主流程
# ============================================
main() {
    setup_colors
    parse_args "$@"
    show_banner
    check_ports
    check_docker
    build_images
    start_services
    show_status
    show_urls
    show_complete
}

main "$@"
