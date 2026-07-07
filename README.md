# De novo сборка генома *Vibrio cholerae*

Автоматизированный пайплайн для *de novo* сборки бактериального генома из
данных Illumina (short reads) и Oxford Nanopore (long reads). Проект собирает,
улучшает, полирует и оценивает геном одним скриптом.

Организм: ***Vibrio cholerae*** (~4.0 Мб, две хромосомы).

---

## Что делает пайплайн

| Этап | Инструменты | Результат |
|------|-------------|-----------|
| 1. Контроль качества | FastQC, fastp, MultiQC | тримminг ридов + отчёты |
| 2. Сборка | SPAdes (Illumina + hybrid), Flye (Nanopore) | 3 черновые сборки |
| 3. Scaffolding | LongStitch | Illumina-сборка, удлинённая нанопором |
| 4. Полировка | BWA + samtools + Pilon | исправление ошибок короткими ридами |
| 5. Сравнение | seqtk, Sibelia, Circos | синтенные блоки, Circos-диаграмма |
| 6. Оценка | BUSCO (online), QUAST, barrnap | полнота, метрики, рРНК |

---

## Требования

- Linux + [conda](https://docs.conda.io/) (или mamba)
- ~30–50 ГБ свободного места под результаты
- Доступ в интернет (BUSCO качает линию `vibrio_odb12`, ~100 МБ)

---

## Установка

```bash
git clone https://github.com/<ваш-логин>/de_nova.git
cd de_nova
chmod +x 00_setup.sh run_denovo.sh
./00_setup.sh          # создаёт conda-окружения и ставит все инструменты
```

`00_setup.sh --busco` дополнительно скачает базу BUSCO заранее.

---

## Данные

Скрипты ждут данные в двух папках (в репозиторий **не** входят — см. `.gitignore`):

```
data/     SRR25745292_..._1.fastq.gz   # Illumina R1
          SRR25745292_..._2.fastq.gz   # Illumina R2
data_n/   SRR27991387_..._1.fastq.gz   # Nanopore
```

Скачать эти данные можно из SRA (NCBI) по идентификаторам
`SRR25745292` (Illumina) и `SRR27991387` (Nanopore).

---

## Запуск

```bash
./run_denovo.sh                    # весь пайплайн
./run_denovo.sh qc assembly        # только выбранные этапы
```

Доступные метки этапов: `qc assembly scaffolding polishing compare evaluate`.
Все результаты складываются в `results/`.

---

## Структура репозитория

```
.
├── 00_setup.sh       # установка окружений и инструментов (conda)
├── run_denovo.sh     # основной пайплайн сборки
├── .gitignore
├── LICENSE
└── README.md
```

---

## Основано на

Практикум по геномной сборке (день 4–5): контроль качества чтений,
графовые алгоритмы сборки, гибридные стратегии и постобработка.
