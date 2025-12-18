"""
数据脱敏 Web 应用 - 基于 NLP 的中文敏感信息识别与脱敏

功能：
- 支持文本输入和文件上传
- 多种脱敏策略（部分脱敏、完全脱敏、占位符、哈希）
- 实时预览脱敏结果
- 敏感实体高亮显示
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import gradio as gr

from demo import (
    CompositeDesensitizer,
    Entity,
    EntityType,
    MaskStrategy,
    NLPDesensitizer,
    RegexDesensitizer,
)

# =========================
# Config
# =========================
GOOGLE_FONTS_URL = (
    "<link href='https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;500;700&display=swap' rel='stylesheet'>"
)

# 脱敏策略映射
STRATEGY_MAP = {
    "部分脱敏 (张*三)": MaskStrategy.PARTIAL,
    "完全脱敏 (***)": MaskStrategy.FULL,
    "占位符 ([人名])": MaskStrategy.PLACEHOLDER,
    "哈希脱敏 ([a1b2c3])": MaskStrategy.HASH,
}

# 实体类型映射（用于 UI 显示）
ENTITY_TYPE_MAP = {
    "人名": EntityType.PERSON,
    "地名": EntityType.LOCATION,
    "组织机构": EntityType.ORGANIZATION,
    "时间": EntityType.TIME,
    "电话": EntityType.PHONE,
    "邮箱": EntityType.EMAIL,
    "身份证": EntityType.ID_CARD,
    "银行卡": EntityType.BANK_CARD,
}

# 按来源分组的实体类型（用于 UI 分类显示）
NLP_ENTITY_TYPES = ["人名", "地名", "组织机构", "时间"]  # PaddleNLP 识别
REGEX_ENTITY_TYPES = ["电话", "邮箱", "身份证", "银行卡"]  # 正则识别

# 实体类型颜色映射
ENTITY_COLORS = {
    EntityType.PERSON: "#ef4444",  # 红色
    EntityType.LOCATION: "#22c55e",  # 绿色
    EntityType.ORGANIZATION: "#3b82f6",  # 蓝色
    EntityType.TIME: "#f59e0b",  # 橙色
    EntityType.PHONE: "#8b5cf6",  # 紫色
    EntityType.EMAIL: "#06b6d4",  # 青色
    EntityType.ID_CARD: "#ec4899",  # 粉色
    EntityType.BANK_CARD: "#14b8a6",  # 青绿色
    EntityType.OTHER: "#6b7280",  # 灰色
}


# =========================
# CSS 样式
# =========================
custom_css = """
/* 全局字体 */
body, .gradio-container {
    font-family: "Noto Sans SC", "Microsoft YaHei", "PingFang SC", sans-serif;
}

/* 头部样式 */
.app-header {
    text-align: center;
    max-width: 900px;
    margin: 0 auto 16px !important;
    padding: 20px 0;
}

.app-header h1 {
    font-size: 2rem;
    font-weight: 700;
    color: #1f2937;
    margin-bottom: 8px;
}

.app-header p {
    color: #6b7280;
    font-size: 1rem;
}

/* 容器 */
.gradio-container {
    padding: 8px 16px !important;
}

/* 快捷链接 */
.quick-links {
    text-align: center;
    padding: 12px 0;
    border: 1px solid #e5e7eb;
    border-radius: 12px;
    margin: 12px auto;
    max-width: 900px;
    background: linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%);
}

.quick-links a {
    margin: 0 16px;
    font-size: 14px;
    font-weight: 600;
    color: #3b82f6;
    text-decoration: none;
}

.quick-links a:hover {
    text-decoration: underline;
}

/* 功能说明 */
.notice {
    margin: 12px auto;
    max-width: 900px;
    padding: 16px;
    border: 1px solid #e5e7eb;
    border-radius: 12px;
    background: #f8fafc;
    font-size: 14px;
    line-height: 1.7;
}

.notice strong {
    font-weight: 700;
    color: #1f2937;
}

/* 结果展示区域 */
#result_text {
    min-height: 200px;
    font-size: 16px;
    line-height: 1.8;
}

#entity_html {
    min-height: 150px;
    max-height: 400px;
    overflow-y: auto;
}

/* 实体标签样式 */
.entity-tag {
    display: inline-block;
    padding: 2px 8px;
    margin: 2px;
    border-radius: 4px;
    font-size: 13px;
    font-weight: 500;
}

/* 统计卡片 */
.stat-card {
    background: white;
    border: 1px solid #e5e7eb;
    border-radius: 12px;
    padding: 16px;
    text-align: center;
}

.stat-card h3 {
    font-size: 2rem;
    font-weight: 700;
    color: #3b82f6;
    margin: 0;
}

.stat-card p {
    color: #6b7280;
    margin: 4px 0 0;
    font-size: 14px;
}

/* 高亮文本 */
.highlight {
    padding: 2px 4px;
    border-radius: 4px;
    font-weight: 500;
}

/* 按钮样式 */
.primary-btn {
    background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%) !important;
    border: none !important;
    font-weight: 600 !important;
}

/* 示例区域 */
.examples-section {
    margin-top: 16px;
    padding: 16px;
    background: #f8fafc;
    border-radius: 12px;
}
"""


# =========================
# 核心处理函数
# =========================
def process_text(
    text: str,
    strategy: str,
    use_paddle: bool,
    use_regex: bool,
    selected_types: list[str],
) -> tuple[str, str, str, str]:
    """
    处理文本脱敏

    Args:
        text: 输入文本
        strategy: 脱敏策略
        use_paddle: 是否使用 PaddleNLP
        use_regex: 是否使用正则匹配
        selected_types: 选中的实体类型列表

    Returns:
        tuple: (脱敏后文本, 实体HTML, 统计信息, 原文高亮HTML)
    """
    if not text or not text.strip():
        return "", "<p style='color:#6b7280;'>请输入需要脱敏的文本</p>", "", ""

    if not selected_types:
        return text, "<p style='color:#f59e0b;'>请至少选择一种实体类型</p>", "", ""

    # 获取脱敏策略
    mask_strategy = STRATEGY_MAP.get(strategy, MaskStrategy.PARTIAL)

    # 转换选中的实体类型
    entity_types = [ENTITY_TYPE_MAP[t] for t in selected_types if t in ENTITY_TYPE_MAP]

    # 选择脱敏器并处理
    if use_paddle and use_regex:
        result = CompositeDesensitizer(strategy=mask_strategy, entity_types=entity_types).desensitize(text)
    elif use_paddle:
        result = NLPDesensitizer(strategy=mask_strategy, entity_types=entity_types).desensitize(text)
    elif use_regex:
        result = RegexDesensitizer(strategy=mask_strategy, entity_types=entity_types).desensitize(text)
    else:
        return text, "<p style='color:#f59e0b;'>请至少选择一种识别方式</p>", "", ""

    entities = result.entities
    masked_text = result.masked_text

    # 生成实体HTML
    entity_html = _generate_entity_html(entities)

    # 生成统计信息
    stats_html = _generate_stats_html(entities)

    # 生成高亮原文
    highlight_html = _generate_highlight_html(text, entities)

    return masked_text, entity_html, stats_html, highlight_html


def _generate_entity_html(entities: list[Entity]) -> str:
    """生成实体列表HTML"""
    if not entities:
        return "<p style='color:#6b7280;text-align:center;'>未识别到敏感实体</p>"

    # 按类型分组
    by_type: dict[EntityType, list[Entity]] = {}
    for e in entities:
        if e.entity_type not in by_type:
            by_type[e.entity_type] = []
        by_type[e.entity_type].append(e)

    html_parts = []
    for etype, elist in sorted(by_type.items(), key=lambda x: len(x[1]), reverse=True):
        color = ENTITY_COLORS.get(etype, "#6b7280")
        unique_texts = list({e.text for e in elist})

        tags = "".join(
            f'<span class="entity-tag" style="background:{color}20;color:{color};border:1px solid {color}40;">{t}</span>'
            for t in unique_texts[:10]  # 限制显示数量
        )

        html_parts.append(f"""
        <div style="margin-bottom:12px;">
            <div style="font-weight:600;color:#374151;margin-bottom:6px;">
                {etype.value} <span style="color:#9ca3af;font-weight:400;">({len(elist)}个)</span>
            </div>
            <div>{tags}</div>
        </div>
        """)

    return "".join(html_parts)


def _generate_stats_html(entities: list[Entity]) -> str:
    """生成统计信息HTML"""
    total = len(entities)
    types = len({e.entity_type for e in entities})

    return f"""
    <div style="display:flex;gap:16px;justify-content:center;">
        <div class="stat-card">
            <h3>{total}</h3>
            <p>敏感实体</p>
        </div>
        <div class="stat-card">
            <h3>{types}</h3>
            <p>实体类型</p>
        </div>
    </div>
    """


def _generate_highlight_html(text: str, entities: list[Entity]) -> str:
    """生成高亮原文HTML"""
    if not entities:
        return f"<p>{text}</p>"

    # 按位置排序
    sorted_entities = sorted(entities, key=lambda e: e.start)

    # 构建高亮文本
    result = []
    last_end = 0

    for entity in sorted_entities:
        # 添加实体前的普通文本
        if entity.start > last_end:
            result.append(text[last_end : entity.start])

        # 添加高亮实体
        color = ENTITY_COLORS.get(entity.entity_type, "#6b7280")
        result.append(
            f'<span class="highlight" style="background:{color}20;color:{color};border-bottom:2px solid {color};" '
            f'title="{entity.entity_type.value}">{entity.text}</span>'
        )

        last_end = entity.end

    # 添加最后的普通文本
    if last_end < len(text):
        result.append(text[last_end:])

    return f"<p style='line-height:2;font-size:15px;'>{''.join(result)}</p>"


def process_file(
    file: Any,
    strategy: str,
    use_paddle: bool,
    use_regex: bool,
    selected_types: list[str],
) -> tuple[str, str, str, str]:
    """处理文件上传"""
    if file is None:
        return "", "<p style='color:#6b7280;'>请上传文件</p>", "", ""

    try:
        content = Path(file).read_text(encoding="utf-8")
        return process_text(content, strategy, use_paddle, use_regex, selected_types)
    except Exception as e:
        return "", f"<p style='color:#ef4444;'>文件读取错误: {e}</p>", "", ""


# =========================
# Gradio 界面
# =========================
with gr.Blocks() as app:
    # 头部
    gr.HTML("""
    <div class="app-header">
        <h1>🔒 数据脱敏工具</h1>
        <p>基于 NLP 的中文敏感信息识别与脱敏</p>
    </div>
    """)

    with gr.Tabs():
        # ===================== 文本脱敏 Tab =====================
        with gr.Tab("📝 文本脱敏"):
            with gr.Row():
                # 左侧：输入区域
                with gr.Column(scale=5):
                    input_text = gr.Textbox(
                        label="输入文本",
                        placeholder="请输入需要脱敏的文本...\n\n示例：张三的手机号是13812345678，身份证号110101199001011234，邮箱zhangsan@example.com",
                        lines=8,
                        max_lines=20,
                    )

                    with gr.Row():
                        strategy_dropdown = gr.Dropdown(
                            choices=list(STRATEGY_MAP.keys()),
                            value="部分脱敏 (张*三)",
                            label="脱敏策略",
                            scale=2,
                        )

                    with gr.Row():
                        use_paddle = gr.Checkbox(label="脱敏模型 (人名/地名/时间)", value=True)
                        use_regex = gr.Checkbox(label="正则匹配 (手机号/身份证/邮箱)", value=True)

                    # 实体类型选择
                    with gr.Accordion("🎯 选择识别类型", open=True):
                        with gr.Row():
                            with gr.Column(scale=1):
                                nlp_types = gr.CheckboxGroup(
                                    choices=NLP_ENTITY_TYPES,
                                    value=NLP_ENTITY_TYPES,  # 默认全选
                                    label="NLP 识别类型",
                                )
                            with gr.Column(scale=1):
                                regex_types = gr.CheckboxGroup(
                                    choices=REGEX_ENTITY_TYPES,
                                    value=REGEX_ENTITY_TYPES,  # 默认全选
                                    label="正则识别类型",
                                )

                    process_btn = gr.Button("🚀 开始脱敏", variant="primary", elem_classes=["primary-btn"])

                    # 示例
                    gr.Examples(
                        examples=[
                            ["李白是唐朝伟大的诗人，他的手机号是13812345678，邮箱是libai@tang.com"],
                            ["2024年1月，张三在北京市朝阳区购买了一套房产，银行卡号为6222021234567890123"],
                            ["中国科学院的王教授在北京发表了一篇论文，联系方式：wangprof@cas.cn"],
                        ],
                        inputs=input_text,
                        label="示例文本",
                    )

                # 右侧：结果区域
                with gr.Column(scale=7):
                    with gr.Tabs():
                        with gr.Tab("脱敏结果"):
                            result_text = gr.Textbox(
                                label="脱敏后文本",
                                lines=8,
                                max_lines=20,
                                elem_id="result_text",
                                interactive=False,
                            )

                        with gr.Tab("实体识别"):
                            stats_html = gr.HTML(elem_id="stats_html")
                            entity_html = gr.HTML(elem_id="entity_html")

                        with gr.Tab("原文高亮"):
                            highlight_html = gr.HTML(elem_id="highlight_html")

            # 辅助函数：合并两组类型并调用处理函数
            def process_with_types(
                text: str,
                strategy: str,
                use_paddle: bool,
                use_regex: bool,
                nlp_selected: list[str],
                regex_selected: list[str],
            ) -> tuple[str, str, str, str]:
                selected_types = nlp_selected + regex_selected
                return process_text(text, strategy, use_paddle, use_regex, selected_types)

            # 绑定事件
            process_btn.click(
                fn=process_with_types,
                inputs=[input_text, strategy_dropdown, use_paddle, use_regex, nlp_types, regex_types],
                outputs=[result_text, entity_html, stats_html, highlight_html],
            )

        # ===================== 文件脱敏 Tab =====================
        with gr.Tab("📁 文件脱敏"):
            with gr.Row():
                with gr.Column(scale=5):
                    file_input = gr.File(
                        label="上传文本文件",
                        file_types=[".txt", ".md", ".csv"],
                        type="filepath",
                    )

                    with gr.Row():
                        file_strategy = gr.Dropdown(
                            choices=list(STRATEGY_MAP.keys()),
                            value="部分脱敏 (张*三)",
                            label="脱敏策略",
                        )

                    with gr.Row():
                        file_use_paddle = gr.Checkbox(label="PaddleNLP", value=True)
                        file_use_regex = gr.Checkbox(label="正则匹配", value=True)

                    # 文件脱敏的实体类型选择
                    with gr.Accordion("🎯 选择识别类型", open=True):
                        with gr.Row():
                            with gr.Column(scale=1):
                                file_nlp_types = gr.CheckboxGroup(
                                    choices=NLP_ENTITY_TYPES,
                                    value=NLP_ENTITY_TYPES,
                                    label="NLP 识别类型",
                                )
                            with gr.Column(scale=1):
                                file_regex_types = gr.CheckboxGroup(
                                    choices=REGEX_ENTITY_TYPES,
                                    value=REGEX_ENTITY_TYPES,
                                    label="正则识别类型",
                                )

                    file_process_btn = gr.Button("🚀 处理文件", variant="primary")

                with gr.Column(scale=7):
                    with gr.Tabs():
                        with gr.Tab("脱敏结果"):
                            file_result = gr.Textbox(
                                label="脱敏后内容",
                                lines=12,
                                interactive=False,
                            )

                        with gr.Tab("实体识别"):
                            file_stats = gr.HTML()
                            file_entities = gr.HTML()

            # 文件脱敏辅助函数
            def process_file_with_types(
                file: Any,
                strategy: str,
                use_paddle: bool,
                use_regex: bool,
                nlp_selected: list[str],
                regex_selected: list[str],
            ) -> tuple[str, str, str, str]:
                selected_types = nlp_selected + regex_selected
                return process_file(file, strategy, use_paddle, use_regex, selected_types)

            file_process_btn.click(
                fn=process_file_with_types,
                inputs=[file_input, file_strategy, file_use_paddle, file_use_regex, file_nlp_types, file_regex_types],
                outputs=[file_result, file_entities, file_stats, gr.HTML()],
            )

    # 底部说明
    gr.HTML("""
    <div class="notice">
        <strong>📌 功能说明：</strong>
        <ul style="margin:8px 0 0 20px;padding:0;">
            <li><strong>NLP 脱敏模型</strong>：基于深度学习的命名实体识别，可识别人名、地名、组织、时间等</li>
            <li><strong>正则匹配</strong>：精确匹配结构化敏感信息，如手机号、身份证、邮箱、银行卡等</li>
            <li><strong>脱敏策略</strong>：支持部分脱敏、完全脱敏、占位符替换、哈希脱敏四种方式</li>
        </ul>
    </div>
    """)


if __name__ == "__main__":
    app.queue(max_size=32).launch(
        server_name="0.0.0.0",
        server_port=7860,
        share=True,
        head=GOOGLE_FONTS_URL,
        css=custom_css,
    )
