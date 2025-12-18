"""
数据脱敏 Demo - 基于 NLP 的中文敏感信息识别与脱敏

支持两种实现方式:
1. NLP: 专业的中文 NER (推荐)
2. 正则表达式: 用于识别结构化敏感信息

安装: uv sync --group paddle
环境变量: PPNLP_HOME 或 MODEL_DIR 设置模型缓存目录
"""

from __future__ import annotations

import hashlib
import os
import re
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.table import Table

NER_MODE = os.environ.get("NER_MODE", "fast")


def _setup_model_dir() -> None:
    """配置模型目录环境变量"""
    model_dir = os.environ.get("MODEL_DIR") or os.environ.get("PPNLP_HOME")
    if model_dir:
        path = Path(model_dir).expanduser().resolve()
        path.mkdir(parents=True, exist_ok=True)
        os.environ["PPNLP_HOME"] = str(path)


_setup_model_dir()


class EntityType(Enum):
    """实体类型枚举"""

    PERSON = "人名"
    LOCATION = "地名"
    ORGANIZATION = "组织机构"
    TIME = "时间"
    PHONE = "电话"
    EMAIL = "邮箱"
    ID_CARD = "身份证"
    BANK_CARD = "银行卡"
    ADDRESS = "地址"
    MONEY = "金额"
    OTHER = "其他"


class MaskStrategy(Enum):
    """脱敏策略枚举"""

    FULL = "full"
    PARTIAL = "partial"
    HASH = "hash"
    PLACEHOLDER = "placeholder"


@dataclass
class Entity:
    """识别出的实体"""

    text: str
    entity_type: EntityType
    start: int
    end: int
    confidence: float = 1.0


@dataclass
class MaskResult:
    """脱敏结果"""

    original_text: str
    masked_text: str
    entities: list[Entity] = field(default_factory=list)


class BaseDesensitizer(ABC):
    """脱敏器基类"""

    def __init__(
        self,
        strategy: MaskStrategy = MaskStrategy.PARTIAL,
        entity_types: list[EntityType] | None = None,
    ) -> None:
        self.strategy = strategy
        self.entity_types = entity_types
        self._console = Console()

    @abstractmethod
    def recognize_entities(self, text: str) -> list[Entity]:
        """识别文本中的敏感实体"""
        ...

    def mask_text(self, text: str, entity: Entity) -> str:
        """根据策略对实体进行脱敏"""
        entity_text = entity.text

        if self.strategy == MaskStrategy.FULL:
            return "*" * len(entity_text)

        if self.strategy == MaskStrategy.PARTIAL:
            if len(entity_text) <= 2:
                return entity_text[0] + "*" * (len(entity_text) - 1)
            return entity_text[0] + "*" * (len(entity_text) - 2) + entity_text[-1]

        if self.strategy == MaskStrategy.HASH:
            hash_val = hashlib.md5(entity_text.encode()).hexdigest()[:8]  # noqa: S324
            return f"[{hash_val}]"

        if self.strategy == MaskStrategy.PLACEHOLDER:
            return f"[{entity.entity_type.value}]"

        return entity_text

    def desensitize(self, text: str) -> MaskResult:
        """对文本进行脱敏处理"""
        entities = self.recognize_entities(text)
        entities_sorted = sorted(entities, key=lambda e: e.start, reverse=True)

        masked_text = text
        for entity in entities_sorted:
            masked_value = self.mask_text(text, entity)
            masked_text = masked_text[: entity.start] + masked_value + masked_text[entity.end :]

        return MaskResult(original_text=text, masked_text=masked_text, entities=entities)

    def display_result(self, result: MaskResult) -> None:
        """使用 rich 展示脱敏结果"""
        table = Table(title="数据脱敏结果", show_header=True, header_style="bold magenta")
        table.add_column("原始文本", style="dim", width=50)
        table.add_column("脱敏文本", style="green", width=50)
        table.add_row(result.original_text, result.masked_text)
        self._console.print(table)

        if result.entities:
            entity_table = Table(title="识别实体", show_header=True, header_style="bold cyan")
            entity_table.add_column("实体", style="yellow")
            entity_table.add_column("类型", style="blue")
            entity_table.add_column("置信度", style="green")
            for entity in result.entities:
                entity_table.add_row(entity.text, entity.entity_type.value, f"{entity.confidence:.2%}")
            self._console.print(entity_table)


class RegexDesensitizer(BaseDesensitizer):
    """基于正则表达式的脱敏器"""

    PATTERNS: dict[EntityType, str] = {
        EntityType.PHONE: r"1[3-9]\d{9}",
        EntityType.EMAIL: r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}",
        EntityType.ID_CARD: r"\d{17}[\dXx]",
        EntityType.BANK_CARD: r"\d{16,19}",
    }

    def recognize_entities(self, text: str) -> list[Entity]:
        """使用正则表达式识别结构化敏感信息"""
        entities: list[Entity] = []

        for entity_type, pattern in self.PATTERNS.items():
            if self.entity_types is not None and entity_type not in self.entity_types:
                continue

            for match in re.finditer(pattern, text):
                entities.append(
                    Entity(
                        text=match.group(),
                        entity_type=entity_type,
                        start=match.start(),
                        end=match.end(),
                        confidence=1.0,
                    )
                )

        return entities


class NLPDesensitizer(BaseDesensitizer):
    """基于 PaddleNLP Taskflow 的脱敏器"""

    TAG_MAPPING: dict[str, EntityType] = {
        "PER": EntityType.PERSON,
        "LOC": EntityType.LOCATION,
        "ORG": EntityType.ORGANIZATION,
        "TIME": EntityType.TIME,
        "人物类_实体": EntityType.PERSON,
        "地点类_实体": EntityType.LOCATION,
        "组织机构类_实体": EntityType.ORGANIZATION,
        "时间类_实体": EntityType.TIME,
    }

    def __init__(
        self,
        strategy: MaskStrategy = MaskStrategy.PARTIAL,
        entity_types: list[EntityType] | None = None,
        mode: str | None = None,
    ) -> None:
        super().__init__(strategy, entity_types)
        self._mode = mode or NER_MODE
        self._ner = self._init_ner()

    def _init_ner(self) -> Any:
        """初始化 NER 模型，失败时抛出详细异常"""
        try:
            from paddlenlp import Taskflow
        except ImportError as e:
            msg = "请先安装 paddlepaddle 和 paddlenlp: uv sync --group paddle"
            raise ImportError(msg) from e

        try:
            return Taskflow("ner", mode=self._mode)
        except (FileNotFoundError, RuntimeError) as e:
            msg = f"模型文件未找到，请运行 scripts/download_models.sh 下载模型: {e}"
            raise RuntimeError(msg) from e
        except OSError as e:
            msg = f"模型加载失败，请检查 PPNLP_HOME 目录或网络连接: {e}"
            raise RuntimeError(msg) from e

    def recognize_entities(self, text: str) -> list[Entity]:
        """使用 PaddleNLP Taskflow 识别命名实体"""
        results = self._ner(text)
        entities: list[Entity] = []
        current_pos = 0

        for entity_text, tag in results:
            start = text.find(entity_text, current_pos)
            if start == -1:
                continue

            end = start + len(entity_text)
            current_pos = end

            entity_type = self.TAG_MAPPING.get(tag)
            if entity_type is None:
                continue

            if self.entity_types is not None and entity_type not in self.entity_types:
                continue

            entities.append(
                Entity(
                    text=entity_text,
                    entity_type=entity_type,
                    start=start,
                    end=end,
                    confidence=0.95,
                )
            )

        return entities


class CompositeDesensitizer(BaseDesensitizer):
    """组合脱敏器 - 结合正则表达式和 NLP 的能力"""

    def __init__(
        self,
        strategy: MaskStrategy = MaskStrategy.PARTIAL,
        entity_types: list[EntityType] | None = None,
        mode: str = "fast",
    ) -> None:
        super().__init__(strategy, entity_types)
        self._regex_desensitizer = RegexDesensitizer(strategy, entity_types)
        self._paddle_desensitizer = NLPDesensitizer(strategy, entity_types, mode=mode)

    def recognize_entities(self, text: str) -> list[Entity]:
        """组合多种方式识别实体"""
        regex_entities = self._regex_desensitizer.recognize_entities(text)
        paddle_entities = self._paddle_desensitizer.recognize_entities(text)

        all_entities = regex_entities + paddle_entities
        unique_entities: list[Entity] = []

        for entity in all_entities:
            is_duplicate = any(
                e.start <= entity.start < e.end or e.start < entity.end <= e.end for e in unique_entities
            )
            if not is_duplicate:
                unique_entities.append(entity)

        return unique_entities


def demo_paddle() -> None:
    """PaddleNLP 脱敏示例"""
    console = Console()
    console.print("\n[bold blue]===== PaddleNLP 数据脱敏 Demo =====[/bold blue]\n")

    test_texts = [
        "李白是唐朝伟大的诗人，他的手机号是13812345678，邮箱是libai@tang.com",
        "2024年1月，张三在北京市朝阳区购买了一套房产，银行卡号为6222021234567890123",
        "中国科学院的王教授发表了一篇关于人工智能的论文，联系方式：010-12345678",
    ]

    try:
        desensitizer = CompositeDesensitizer(strategy=MaskStrategy.PARTIAL)
        for text in test_texts:
            console.print(f"[dim]处理文本:[/dim] {text}")
            result = desensitizer.desensitize(text)
            desensitizer.display_result(result)
            console.print()
    except (ImportError, RuntimeError) as e:
        console.print(f"[red]错误: {e}[/red]")


def demo_regex() -> None:
    """正则表达式脱敏示例"""
    console = Console()
    console.print("\n[bold yellow]===== 正则表达式脱敏 Demo =====[/bold yellow]\n")

    test_texts = [
        "手机号: 13812345678，身份证: 110101199001011234",
        "邮箱: test@example.com，银行卡: 6222021234567890123",
    ]

    desensitizer = RegexDesensitizer(strategy=MaskStrategy.PARTIAL)

    for text in test_texts:
        console.print(f"[dim]处理文本:[/dim] {text}")
        result = desensitizer.desensitize(text)
        desensitizer.display_result(result)
        console.print()


def main() -> None:
    """主函数"""
    console = Console()
    console.print("[bold]数据脱敏工具 Demo[/bold]")
    console.print("=" * 50)

    demo_regex()
    demo_paddle()


if __name__ == "__main__":
    main()
