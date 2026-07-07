#!/bin/bash
###############################################################################
# 00_setup.sh — установка окружений и подготовка данных для пайплайна.
#
# Ставит ЧЕРЕЗ CONDA инструменты в отдельные окружения (по одному на группу
# конфликтующих тулз — так надёжнее, чем один общий env). Запускать ОДИН раз
# перед run_denovo.sh.
#
#   ./00_setup.sh            # создать окружения + поставить тулзы
#   ./00_setup.sh --fresh    # снести управляемые окружения и пересоздать с нуля
#   ./00_setup.sh --busco    # то же + предзагрузка линии vibrio_odb12
#
# Флаги можно совмещать: ./00_setup.sh --fresh --busco
#
# Отличие от run_denovo.sh: этот скрипт НИЧЕГО не собирает — он только
# доустанавливает недостающие тулзы и базы. Сам анализ — во втором скрипте.
###############################################################################

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# Разбор флагов
FRESH=0
BUSCO_PREFETCH=0
for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=1 ;;
    --busco) BUSCO_PREFETCH=1 ;;
    *) echo "Неизвестный флаг: $arg" >&2; exit 1 ;;
  esac
done

# Python, совместимый со всеми тулзами (quast, busco и пр. не любят 3.13+)
PY_VER="3.10"

# Окружения и их пакеты (имена окружений должны совпадать с run_denovo.sh)
ENV_QC="QC_fastq"
ENV_ASM="assembly"
ENV_BUSCO="busco"
ENV_QUAST="quast"
ENV_SIBELIA="sibelia"
ENV_LONGSTITCH="longstitch"
ENV_PILON="pilon"

BUSCO_LINEAGE="vibrio_odb12"
BUSCO_DOWNLOAD_PATH="$PROJECT_DIR/results/busco_downloads"

log() { echo -e "\n\033[1;32m[setup] $*\033[0m"; }

# ─────────────────────────── conda / mamba ──────────────────────────────────
eval "$(conda shell.bash hook)"

# Принудительно используем conda (по просьбе пользователя).
# Чтобы вернуть авто-выбор mamba (быстрее) — раскомментируйте блок ниже.
CONDA=conda
# if command -v mamba >/dev/null 2>&1; then CONDA=mamba; else CONDA=conda; fi
log "Пакетный менеджер: $CONDA | Python в окружениях: $PY_VER"

# Каналы bioconda (порядок важен)
CHANNELS="-c conda-forge -c bioconda -c defaults"

env_exists() { conda env list | awk '{print $1}' | grep -qx "$1"; }

# Создать окружение с нужным Python + пакетами за один solve (надёжнее, чем
# создавать пустое и потом доустанавливать). С --fresh сносит старое.
setup_env() {
  local env="$1"; shift
  local pkgs="$*"

  if [ "$FRESH" -eq 1 ] && env_exists "$env"; then
    log "Удаляю окружение '$env' (--fresh)"
    conda env remove -y -n "$env"
  fi

  if env_exists "$env"; then
    log "Окружение '$env' есть — доустанавливаю: $pkgs"
    $CONDA install -y -n "$env" $CHANNELS $pkgs
  else
    log "Создаю '$env' (python=$PY_VER): $pkgs"
    $CONDA create -y -n "$env" $CHANNELS "python=$PY_VER" $pkgs
  fi
}

# ─────────────────────────── Установка тулз ─────────────────────────────────
setup_env "$ENV_QC"        fastqc fastp multiqc
setup_env "$ENV_ASM"       spades flye seqtk bwa samtools bedtools barrnap
setup_env "$ENV_BUSCO"     busco
setup_env "$ENV_QUAST"     quast
setup_env "$ENV_SIBELIA"   sibelia circos
setup_env "$ENV_LONGSTITCH" longstitch
setup_env "$ENV_PILON"     pilon

# ──────────────────────── Проверка входных данных ───────────────────────────
log "Проверяю наличие входных данных"
missing=0
ls "$PROJECT_DIR"/data/*_1.fastq.gz  >/dev/null 2>&1 || { echo "  НЕТ: data/*_1.fastq.gz"; missing=1; }
ls "$PROJECT_DIR"/data/*_2.fastq.gz  >/dev/null 2>&1 || { echo "  НЕТ: data/*_2.fastq.gz"; missing=1; }
ls "$PROJECT_DIR"/data_n/*.fastq.gz  >/dev/null 2>&1 || { echo "  НЕТ: data_n/*.fastq.gz"; missing=1; }
[ "$missing" -eq 0 ] && log "Все входные файлы (Illumina + Nanopore) на месте."

# ─────────────────── (опц.) предзагрузка линии BUSCO ────────────────────────
if [ "$BUSCO_PREFETCH" -eq 1 ]; then
  log "Предзагрузка линии BUSCO '$BUSCO_LINEAGE' (онлайн, ~100 МБ)"
  conda activate "$ENV_BUSCO"
  mkdir -p "$BUSCO_DOWNLOAD_PATH"
  busco --download_path "$BUSCO_DOWNLOAD_PATH" --download "$BUSCO_LINEAGE"
  conda deactivate
fi

log "Готово. Теперь запускайте: ./run_denovo.sh"
