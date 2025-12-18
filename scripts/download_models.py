#!/usr/bin/env python3
"""
模型预下载脚本 - 预先下载 PaddleNLP NER 模型

用法:
    python scripts/download_models.py                    # 下载到默认目录
    python scripts/download_models.py --model-dir ./models  # 下载到指定目录
    python scripts/download_models.py --mode accurate    # 下载 accurate 模式模型

环境变量:
    PPNLP_HOME: PaddleNLP 模型缓存目录 (默认: ~/.paddlenlp)
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def setup_model_dir(model_dir: str | None) -> Path:
    """设置模型目录"""
    if model_dir:
        path = Path(model_dir).expanduser().resolve()
        path.mkdir(parents=True, exist_ok=True)
        # 设置 PaddleNLP 模型目录
        os.environ["PPNLP_HOME"] = str(path)
        return path
    # 使用默认目录
    default_dir = Path(os.environ.get("PPNLP_HOME", Path.home() / ".paddlenlp"))
    default_dir.mkdir(parents=True, exist_ok=True)
    return default_dir


def _create_lac_config(model_dir: Path) -> None:
    """
    创建 LAC 模型的 config.json 配置文件

    修复 PaddleNLP 2.8.x 版本兼容性问题：
    - 新版本代码需要从 config.json 读取 emb_dim, hidden_size 等参数
    - 但官方模型包未包含此文件，导致 KeyError: 'emb_dim'
    """
    import json

    config_path = model_dir / "taskflow" / "lac" / "config.json"
    if config_path.exists():
        return

    # 确保目录存在
    config_path.parent.mkdir(parents=True, exist_ok=True)

    # LAC 模型默认配置参数
    lac_config = {
        "model_type": "lac",
        "emb_dim": 128,
        "hidden_size": 128,
        "vocab_size": 668845,
    }

    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(lac_config, f, indent=2, ensure_ascii=False)

    print(f"  ✓ 已创建 LAC config.json: {config_path}")


def download_ner_model(mode: str = "fast") -> bool:
    """
    下载 NER 模型

    Args:
        mode: 模型模式 ('fast' 或 'accurate')

    Returns:
        是否下载成功
    """
    try:
        from rich.console import Console
        from rich.progress import Progress, SpinnerColumn, TextColumn

        console = Console()
    except ImportError:
        console = None

    def log_info(msg: str) -> None:
        if console:
            console.print(f"[blue]▸[/blue] {msg}")
        else:
            print(f"▸ {msg}")

    def log_success(msg: str) -> None:
        if console:
            console.print(f"  [green]✓[/green] {msg}")
        else:
            print(f"  ✓ {msg}")

    def log_error(msg: str) -> None:
        if console:
            console.print(f"  [red]✗[/red] {msg}")
        else:
            print(f"  ✗ {msg}")

    log_info(f"下载 NER 模型 (mode={mode})...")

    try:
        # 导入 PaddleNLP
        from paddlenlp import Taskflow

        # 初始化 Taskflow 会自动下载模型
        if console:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                console=console,
            ) as progress:
                progress.add_task("正在下载模型...", total=None)
                ner = Taskflow("ner", mode=mode)
        else:
            print("  正在下载模型...")
            ner = Taskflow("ner", mode=mode)

        # 创建 LAC config.json (修复 PaddleNLP 2.8.x 兼容性问题)
        model_dir = Path(os.environ.get("PPNLP_HOME", Path.home() / ".paddlenlp"))
        _create_lac_config(model_dir)

        # 测试模型
        test_result = ner("测试文本")
        if test_result is not None:
            log_success(f"NER 模型 ({mode}) 下载成功")
            return True
        log_error("模型测试失败")
        return False

    except ImportError as e:
        log_error(f"PaddleNLP 未安装: {e}")
        log_error("请先安装: pip install paddlepaddle paddlenlp")
        return False
    except Exception as e:
        log_error(f"下载失败: {e}")
        return False


def show_model_info(model_dir: Path) -> None:
    """显示模型信息"""
    try:
        from rich.console import Console
        from rich.table import Table

        console = Console()
    except ImportError:
        console = None

    def log_info(msg: str) -> None:
        if console:
            console.print(f"[blue]▸[/blue] {msg}")
        else:
            print(f"▸ {msg}")

    log_info(f"模型目录: {model_dir}")

    # 统计模型文件大小
    total_size = 0
    file_count = 0
    for f in model_dir.rglob("*"):
        if f.is_file():
            total_size += f.stat().st_size
            file_count += 1

    size_mb = total_size / (1024 * 1024)

    if console:
        table = Table(title="模型信息", show_header=True, header_style="bold cyan")
        table.add_column("项目", style="dim")
        table.add_column("值", style="green")
        table.add_row("模型目录", str(model_dir))
        table.add_row("文件数量", str(file_count))
        table.add_row("总大小", f"{size_mb:.1f} MB")
        console.print(table)
    else:
        print(f"  模型目录: {model_dir}")
        print(f"  文件数量: {file_count}")
        print(f"  总大小: {size_mb:.1f} MB")


def main() -> int:
    """主函数"""
    parser = argparse.ArgumentParser(
        description="PaddleNLP NER 模型预下载脚本",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s                           # 下载到默认目录
  %(prog)s --model-dir ./models      # 下载到 ./models
  %(prog)s --mode accurate           # 下载 accurate 模式
  %(prog)s --all                     # 下载所有模式
        """,
    )
    parser.add_argument(
        "--model-dir",
        "-d",
        type=str,
        default=None,
        help="模型存储目录 (默认: ~/.paddlenlp 或 $PPNLP_HOME)",
    )
    parser.add_argument(
        "--mode",
        "-m",
        type=str,
        choices=["fast", "accurate"],
        default="fast",
        help="NER 模型模式 (默认: fast)",
    )
    parser.add_argument(
        "--all",
        "-a",
        action="store_true",
        help="下载所有模式的模型",
    )
    parser.add_argument(
        "--info",
        "-i",
        action="store_true",
        help="仅显示模型信息，不下载",
    )

    args = parser.parse_args()

    # 设置模型目录
    model_dir = setup_model_dir(args.model_dir)

    print()
    print("=" * 50)
    print("  PaddleNLP NER 模型下载工具")
    print("=" * 50)
    print()

    # 仅显示信息
    if args.info:
        show_model_info(model_dir)
        return 0

    # 下载模型
    success = True
    if args.all:
        for mode in ["fast", "accurate"]:
            if not download_ner_model(mode):
                success = False
    else:
        if not download_ner_model(args.mode):
            success = False

    print()
    show_model_info(model_dir)
    print()

    if success:
        print("✅ 模型下载完成!")
        print()
        print("提示: 在 Docker 中使用时，设置以下环境变量:")
        print("  PPNLP_HOME=/app/models")
        print()
        return 0
    print("❌ 部分模型下载失败")
    return 1


if __name__ == "__main__":
    sys.exit(main())
