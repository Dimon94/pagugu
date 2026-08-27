# Pagugu Logo 探索稿

Status: selected and archived

本批次验证寄居蟹 IP 的三个造型方向。最终选定 C1-T4「探壳」米白背景版；本目录保留探索证据，正式资产见 `../brand/`。

## 生成记录

- 生成通道：Codex 内置 `image_gen`
- 模型：Unknown（工具未公开模型名）
- 约束传递：main-prompt constraints
- 生成方式：六张独立调用，无参考图、拼图、后处理或重采样
- 原生尺寸：全部为 `1254 × 1254` PNG
- 共同语义：Pagugu/帕咕咕来自寄居蟹属 `Pagurus`；外壳对应不同 Agent Host；角色表达友好、可靠、克制和可解释
- 共同约束原文：`Use no text or watermark. Add no borders, frames, cards, presentation masks, tools, props, ornaments, extra subjects, or scenery. Use no thin antennae, fragile lines, sharp tips, narrow gaps, unnecessary outlines, tiny details, textures, or decorative marks. Add no photorealistic material, dramatic bevel, glossy hotspot, deep occlusion, extrusion, strong three-dimensional rendering, or external cast shadow. Keep the background solid and uniform, with no texture, gradient, vignette, halo, or lighting variation.`

## 候选

| 候选 | 方向与构图 | 颜色映射 | 实际偏差 |
| --- | --- | --- | --- |
| A1 | 换壳；壳优先；从左下探出 | 珊瑚橙身体和双钳；深青绿壳和眼睛；柔和浅黄背景 | 背景有轻微明暗变化；壳更像层叠圆丘，螺旋感较弱。 |
| A2 | 换壳；略正面；从右下探出 | 暖杏色身体和双钳；钴蓝壳和眼睛；柔和薄荷绿背景 | 背景有轻微明暗变化；壳呈层叠结构；内部塑形偏强。 |
| B1 | 护壳；正面圆盾壳；双钳收拢；从左下探出 | 海沫绿身体和双钳；深靛蓝壳和眼睛；柔和桃色背景 | 背景和角色有明显明暗变化；内部塑形偏强。 |
| B2 | 护壳；正面螺旋圆盾；从右下探出 | 向日葵黄身体和双钳；深李子紫壳和眼睛；柔和天蓝背景 | 背景有轻微渐变；塑形偏强；双钳内侧凹口偏尖。 |
| C1 | 探壳；低重心宽轮廓；双钳前探；指定左下 | 珊瑚粉身体和双钳；深海军蓝壳和眼睛；柔和薰衣草紫背景 | 实际更接近底部居中；壳左缘被裁；背景与角色塑形偏强。 |
| C2 | 探壳；宽身体；双钳向左前探；从右下探出 | 明亮水蓝身体和双钳；暖砖橙壳和眼睛；柔和柠檬黄背景 | 背景偏鲜亮且有明暗变化；角色体积感和底部投影明显；壳偏鲜橙。 |

## 文件

- `A1.png`
- `A2.png`
- `B1.png`
- `B2.png`
- `C1.png`
- `C2.png`

## C1 主题配色

四张均以 `C1.png` 为编辑目标。提示词只允许更换颜色，并要求保留原轮廓、螺旋壳、双钳、眼睛、表情、比例、位置和裁切。生成通道仍为 Codex 内置 `image_gen`，模型 Unknown，约束通过 main prompt 传递。

| 候选 | 主题 | 身体与双钳 | 壳与眼睛 | 背景 |
| --- | --- | --- | --- | --- |
| C1-T1 | 潮汐青柠 | 明亮水青 `#23C6C8` | 深钴蓝 `#2447A6` | 柔和黄绿 `#D8E58A` |
| C1-T2 | 森林莓果 | 开心果绿 `#79C98B` | 深莓红 `#84264A` | 暖燕麦 `#E9C98F` |
| C1-T3 | 奶油陶土 | 奶油黄 `#F2C84B` | 陶土红 `#B64B35` | 灰调天蓝 `#A8CADB` |
| C1-T4 | 夜航紫金 | 暖金黄 `#EFB63E` | 午夜靛紫 `#29245C` | 柔和青绿 `#72B6AE` |

- `C1-T1-tidal-lime.png`
- `C1-T2-forest-berry.png`
- `C1-T3-butter-terracotta.png`
- `C1-T4-night-voyage.png`

### C1-T4 米白背景版

以 `C1-T4-night-voyage.png` 为编辑目标，只把柔和青绿背景替换为暖米白 `#F4EBDD`。保留暖金黄身体与双钳、午夜靛紫壳与眼睛，以及原有轮廓、比例、位置和裁切。

- `C1-T4-off-white.png`

## 最终选择

- 造型：C1「探壳」。
- 配色：C1-T4「夜航紫金」。
- 背景与产品主题色：暖米白 `#F4EBDD`。
- 正式资产：`../brand/pagugu-logo-square.png`、`../brand/pagugu-logo-rounded.png`、`../brand/pagugu-logo-circle.png`。
- 正式资产将生成稿的轻微背景渐变校正为精确纯色 `#F4EBDD`，不重绘角色。
