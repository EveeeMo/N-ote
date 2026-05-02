================================================================================
在合规范围内准备「仅 A1–B2」西语词表 — 说明
================================================================================

一、目标
  生成 App 可用的 dele_a1 / dele_a2 / dele_b1 / dele_b2 词表源文件
  （Scripts/dele_*_words.txt，每行：西语|中文|词性[|动词原形]），再运行
  build_dele_vocab.py 生成 Resources/BuiltinBooks/dele_*.json。

二、合规要点
  1. 塞万提斯学院不提供「官方 DELE 全文词表」的开放下载；你们做的是
     「CEFR 难度导向的学习用词表」，需在关于页说明非官方考纲。
  2. 推荐使用明确标注许可的数据源，并在应用内保留署名（见各源 LICENSE）。
  3. 本仓库脚本中的「按词频排名切到 A1/B1/B2」是教学上常用的近似，
     不等同于任何机构的官方分级，可随教研调整 YAML 中的阈值。

三、推荐数据源（使用前请自行打开仓库核对最新 LICENSE）
  • doozan/spanish_data 的 frequency.csv
    — README 注明基于 hermitdave/FrequencyWords 等，CC-BY-SA 相关；
      同时需遵守 Wiktionary / Tatoeba 等原始数据条款。
    https://github.com/doozan/spanish_data
  • 或自行使用 OpenSLR SLR21 等（以该站声明的许可为准）。

四、操作步骤
  1. 从 doozan/spanish_data 下载 frequency.csv（体积较大），放到：
       Scripts/input/frequency.csv
     表头应为：
       count,spanish,pos,flags,usage
     行顺序即词频从高到低；脚本用「第几行数据」作为排名，与 count 数值无关。

  2. 编辑 cefr_rank_bands.yaml，设定各等级最大「排名」阈值（默认约 A1≤800，
     A2≤2500，B1≤6000，B2≤15000，可按教研调整）。

  3. 运行：
       python3 build_cefr_dele_words.py
     或：
       python3 build_cefr_dele_words.py /绝对路径/frequency.csv
     将覆盖生成 dele_a1_words.txt … dele_b2_words.txt。
     第二列多为「（待译）…」：需批量或人工改为中文后再生成 JSON。

  3b. 可用仓库内小样本测格式（不写正式词表）：
       python3 build_cefr_dele_words.py input/frequency_doozan_sample.csv
     然后请从 Resources 里 dele_*.json 再导出恢复 dele_*_words.txt（若误覆盖）。
  4. 人工抽检敏感词、专名、词性错误。
  5. 对每个等级执行：
       python3 build_dele_vocab.py dele_a1 A1 dele_a1
       （其余等级类推）
  6. 在 App「关于」或「DELE 词库」页加入致谢与许可说明（见 attribution_template.txt）。

五、中文释义
  开放词频表多为英义；合规做法包括：自译、采购有授权的汉化词典数据、或
  使用你们已有翻译管线批量生成后人工抽检（注意第三方翻译服务条款）。

================================================================================
