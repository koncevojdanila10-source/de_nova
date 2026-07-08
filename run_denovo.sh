#!/bin/bash
###############################################################################
# run_denovo.sh — автоматический пайплайн de novo сборки бактериального генома
#
# Объект: Vibrio cholerae
#   data/    — Illumina paired-end (*_1.fastq.gz, *_2.fastq.gz)
#   data_n/  — Nanopore long reads   (*.fastq.gz)
#
# Этапы (день 4 + день 5 практикума):
#   1. QC          — fastqc / fastp (тримминг) / multiqc
#   2. Assembly    — SPAdes (Illumina-only, hybrid) + Flye (nanopore-only)
#   3. Scaffolding — LongStitch (Illumina-сборка + Nanopore)
#   4. Polishing   — Pilon (Flye-сборка + Illumina)
#   5. Compare     — seqtk фильтр + Sibelia + Circos
#   6. Evaluate    — BUSCO / QUAST / barrnap
#
# Запуск всего пайплайна:      ./run_denovo.sh
# Запуск отдельных этапов:     ./run_denovo.sh qc assembly
#   доступные метки: qc assembly scaffolding polishing compare evaluate
###############################################################################

set -euo pipefail

# ─────────────────────────────── КОНФИГ ─────────────────────────────────────
# Корень проекта = папка, где лежит этот скрипт
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Входные данные (автоопределение по маске; при желании впишите пути явно)
ILLUMINA_R1="$(ls "$PROJECT_DIR"/data/*_1.fastq.gz   | head -n1)"
ILLUMINA_R2="$(ls "$PROJECT_DIR"/data/*_2.fastq.gz   | head -n1)"
NANOPORE="$(ls   "$PROJECT_DIR"/data_n/*.fastq.gz    | head -n1)"

# Рабочий каталог для всех результатов
OUT="$PROJECT_DIR/results"

# Ресурсы
THREADS=6

# Параметры организма (Vibrio cholerae, ~4.0 Mb: 2 хромосомы ~2.96 + ~1.07 Mb)
GENOME_SIZE=4100000
BUSCO_LINEAGE="vibrio_odb12"
# BUSCO работает в ОНЛАЙН-режиме: линия vibrio_odb12 (~100 МБ) качается с
# busco-data.ezlab.org при первом запуске и кэшируется в этом каталоге,
# поэтому повторные запуски её не перекачивают.
BUSCO_DOWNLOAD_PATH="$OUT/busco_downloads"

# Conda-окружения (создаются скриптом 00_setup.sh — по одному на группу тулз,
# чтобы не конфликтовали зависимости)
ENV_QC="QC_fastq"            # fastqc, fastp, multiqc
ENV_ASM="assembly"          # spades, flye, seqtk, bwa, samtools, bedtools, barrnap
ENV_BUSCO="busco"           # busco
ENV_QUAST="quast"           # quast
ENV_SIBELIA="sibelia"       # sibelia, circos
ENV_LONGSTITCH="longstitch" # longstitch
ENV_PILON="pilon"           # pilon

# Какие этапы гнать: аргументы командной строки или все по умолчанию
STAGES="${*:-qc assembly scaffolding polishing compare evaluate}"

# ──────────────────────────── ВСПОМОГАТЕЛЬНОЕ ───────────────────────────────
# Подключаем conda в текущую сессию shell
eval "$(conda shell.bash hook)"

log()  { echo -e "\n\033[1;34m[$(date '+%H:%M:%S')] $*\033[0m"; }
have() { echo "$STAGES" | grep -qw "$1"; }

mkdir -p "$OUT"

log "Проект:      $PROJECT_DIR"
log "Illumina R1: $ILLUMINA_R1"
log "Illumina R2: $ILLUMINA_R2"
log "Nanopore:    $NANOPORE"
log "Этапы:       $STAGES"

# ──────────────────────────────── 1. QC ─────────────────────────────────────
# Тримминг Illumina через fastp + отчёты FastQC/MultiQC до и после.
# Триммингованные риды используем дальше во всех сборках.
TRIM_R1="$OUT/qc/illumina_1.trimmed.fastq.gz"
TRIM_R2="$OUT/qc/illumina_2.trimmed.fastq.gz"

if have qc; then
  log "=== ЭТАП 1: контроль качества (fastqc + fastp + multiqc) ==="
  conda activate "$ENV_QC"
  mkdir -p "$OUT/qc"

  # FastQC на сырых ридах
  fastqc -t "$THREADS" -o "$OUT/qc" "$ILLUMINA_R1" "$ILLUMINA_R2"

  # Тримминг/фильтрация парных ридов
  fastp \
    -i "$ILLUMINA_R1" -o "$TRIM_R1" \
    -I "$ILLUMINA_R2" -O "$TRIM_R2" \
    --thread "$THREADS" \
    --html "$OUT/qc/fastp.html" --json "$OUT/qc/fastp.json"

  # FastQC на триммингованных ридах
  fastqc -t "$THREADS" -o "$OUT/qc" "$TRIM_R1" "$TRIM_R2"

  # Сводный отчёт
  ( cd "$OUT/qc" && multiqc . )
  conda deactivate
fi

# ─────────────────────────────── 2. ASSEMBLY ────────────────────────────────
# Если QC пропущен, но триммингованных ридов нет — берём сырые.
[ -f "$TRIM_R1" ] || TRIM_R1="$ILLUMINA_R1"
[ -f "$TRIM_R2" ] || TRIM_R2="$ILLUMINA_R2"

ASM_ILLUMINA="$OUT/assembly_spades_i/scaffolds.fasta"
ASM_HYBRID="$OUT/assembly_spades_h/scaffolds.fasta"
ASM_FLYE="$OUT/assembly_flye/assembly.fasta"

if have assembly; then
  log "=== ЭТАП 2: сборки (SPAdes illumina / SPAdes hybrid / Flye) ==="
  conda activate "$ENV_ASM"

  # 2a. SPAdes только по Illumina
  # --phred-offset 33: у этих ридов равномерно высокое качество, и SPAdes не
  # может сам определить кодировку (Phred+33 vs +64) — задаём явно.
  log "SPAdes (Illumina-only) → assembly_spades_i"
  spades.py -1 "$TRIM_R1" -2 "$TRIM_R2" \
    -t "$THREADS" --phred-offset 33 --disable-gzip-output \
    -o "$OUT/assembly_spades_i"

  # 2b. SPAdes гибридная (Illumina + Nanopore)
  log "SPAdes (hybrid) → assembly_spades_h"
  spades.py -1 "$TRIM_R1" -2 "$TRIM_R2" --nanopore "$NANOPORE" \
    -t "$THREADS" --phred-offset 33 --disable-gzip-output \
    -o "$OUT/assembly_spades_h"

  # 2c. Flye по Nanopore (long-read сборка — вход для полировки Pilon).
  # Покрытие нанопором ~730x — слишком много, Flye не собирает дизъонтиги и
  # работает часами. Используем встроенный --asm-coverage 50: Flye сам берёт
  # самые ДЛИННЫЕ риды до 50x для сборки дизъонтигов (каноничный способ по
  # документации, требует --genome-size). --nano-hq: у ридов низкая ошибка
  # (дивергенция перекрытий ~7% => ~3.5% на рид).
  # Падение Flye не должно ронять весь пайплайн — ловим ошибку через "|| ...".
  log "Flye (nanopore-only, --asm-coverage 50, --nano-hq) → assembly_flye"
  flye --nano-hq "$NANOPORE" --genome-size "$GENOME_SIZE" --asm-coverage 50 \
    --threads "$THREADS" --out-dir "$OUT/assembly_flye" \
    || log "ВНИМАНИЕ: Flye не удался — пропускаю сборку Flye, пайплайн продолжается"

  conda deactivate
fi

# ────────────────────────────── 3. SCAFFOLDING ──────────────────────────────
# Улучшаем Illumina-сборку нанопоровыми ридами через LongStitch.
if have scaffolding; then
  log "=== ЭТАП 3: scaffolding Illumina-сборки нанопором (LongStitch) ==="
  conda activate "$ENV_LONGSTITCH"
  mkdir -p "$OUT/scaffolding"
  ( cd "$OUT/scaffolding"
    # LongStitch требует .fq и draft без расширения в имени параметра
    ln -sf "$NANOPORE" nanopore.fq.gz
    ln -sf "$ASM_ILLUMINA" scaffolds.fa
    longstitch run \
      draft=scaffolds reads=nanopore \
      G="$GENOME_SIZE" t="$THREADS" \
      gap_fill=True rounds=3 longmap=ont k_ntLink=24 w=400
  )
  conda deactivate
fi

# ─────────────────────────────── 4. POLISHING ───────────────────────────────
# Полируем Flye-сборку короткими Illumina-ридами (bwa → samtools → Pilon).
POLISHED="$OUT/polish_pilon/pilon.fasta"

if have polishing && [ ! -f "$ASM_FLYE" ]; then
  log "=== ЭТАП 4: полировка пропущена — нет сборки Flye ($ASM_FLYE) ==="
elif have polishing; then
  log "=== ЭТАП 4: полировка Flye-сборки Illumina-ридами (Pilon) ==="
  mkdir -p "$OUT/polish_pilon"
  ( cd "$OUT/polish_pilon"
    conda activate "$ENV_ASM"
    bwa index -p a_index "$ASM_FLYE"
    bwa mem -t "$THREADS" a_index "$TRIM_R1" "$TRIM_R2" \
      | samtools sort -@ "$THREADS" -o out.bam
    samtools index out.bam
    conda deactivate

    conda activate "$ENV_PILON"
    pilon --genome "$ASM_FLYE" --frags out.bam --output pilon
    conda deactivate
  )
fi

# ─────────────────────────────── 5. COMPARE ─────────────────────────────────
# Сравнение сборок синтенными блоками (Sibelia) и Circos-диаграммой.
if have compare; then
  log "=== ЭТАП 5: сравнение сборок (seqtk + Sibelia + Circos) ==="
  conda activate "$ENV_ASM"
  mkdir -p "$OUT/spades_vs_spades"

  # Оставляем только длинные scaffold'ы (>10 кб), чтобы не загромождать картинку
  seqtk seq -L 10000 "$ASM_HYBRID"   > "$OUT/spades_vs_spades/scaffolds.hybrid.fasta"
  seqtk seq -L 10000 "$ASM_ILLUMINA" > "$OUT/spades_vs_spades/scaffolds.illumina.fasta"
  conda deactivate

  conda activate "$ENV_SIBELIA"
  ( cd "$OUT/spades_vs_spades"
    Sibelia -s fine -o sibelia_out scaffolds.hybrid.fasta scaffolds.illumina.fasta
    # Circos может отсутствовать в headless-окружении — не роняем пайплайн
    circos --conf sibelia_out/circos/circos.conf || \
      log "Circos пропущен (нет графической среды/конфига)"
  )
  conda deactivate
fi

# ─────────────────────────────── 6. EVALUATE ────────────────────────────────
# Полнота (BUSCO), метрики (QUAST), поиск рРНК (barrnap) по всем сборкам.
if have evaluate; then
  log "=== ЭТАП 6: оценка сборок (BUSCO + QUAST + barrnap) ==="
  mkdir -p "$OUT/evaluation" "$BUSCO_DOWNLOAD_PATH"

  # Собираем список существующих сборок для оценки
  declare -A ASSEMBLIES=(
    [spades_illumina]="$ASM_ILLUMINA"
    [spades_hybrid]="$ASM_HYBRID"
    [flye]="$ASM_FLYE"
    [flye_pilon]="$POLISHED"
  )

  # Тулзы теперь в разных окружениях, поэтому прогоняем их по очереди:
  # для каждой тулзы активируем её env и проходим по всем сборкам.

  # 6a. BUSCO (online) — полнота по однокопийным ортологам
  conda activate "$ENV_BUSCO"
  ( cd "$OUT/evaluation"
    for name in "${!ASSEMBLIES[@]}"; do
      fa="${ASSEMBLIES[$name]}"
      [ -f "$fa" ] || { log "BUSCO: пропуск $name (нет $fa)"; continue; }
      log "BUSCO (online): $name"
      busco --opt-out-run-stats \
        -l "$BUSCO_LINEAGE" -m genome -c "$THREADS" \
        --download_path "$BUSCO_DOWNLOAD_PATH" \
        -f -o "busco_$name" -i "$fa"
    done
  )
  conda deactivate

  # 6b. QUAST — метрики сборки (N50 и пр.)
  conda activate "$ENV_QUAST"
  ( cd "$OUT/evaluation"
    for name in "${!ASSEMBLIES[@]}"; do
      fa="${ASSEMBLIES[$name]}"
      [ -f "$fa" ] || continue
      log "QUAST: $name"
      quast -t "$THREADS" -o "quast_$name" "$fa"
    done
  )
  conda deactivate

  # 6c. barrnap — поиск рРНК-генов
  conda activate "$ENV_ASM"
  ( cd "$OUT/evaluation"
    for name in "${!ASSEMBLIES[@]}"; do
      fa="${ASSEMBLIES[$name]}"
      [ -f "$fa" ] || continue
      log "barrnap (рРНК): $name"
      barrnap --threads "$THREADS" "$fa" > "barrnap_$name.gff" 2> /dev/null
    done
  )
  conda deactivate
fi

log "=== ГОТОВО. Все результаты в: $OUT ==="
