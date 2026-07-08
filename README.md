# De novo genome assembly of *Vibrio cholerae*

An automated pipeline for *de novo* bacterial genome assembly from Illumina
(short reads) and Oxford Nanopore (long reads). It assembles, scaffolds,
polishes and evaluates the genome with a single script.

Organism: ***Vibrio cholerae*** (~4.0 Mb, two chromosomes).

---

## What the pipeline does

| Stage | Tools | Output |
|-------|-------|--------|
| 1. Quality control | FastQC, fastp, MultiQC | trimmed reads + reports |
| 2. Assembly | SPAdes (Illumina + hybrid), Flye (Nanopore) | 3 draft assemblies |
| 3. Scaffolding | LongStitch | Illumina assembly extended with long reads |
| 4. Polishing | BWA + samtools + Pilon | error correction with short reads |
| 5. Comparison | seqtk, Sibelia, Circos | synteny blocks, Circos plot |
| 6. Evaluation | BUSCO (online), QUAST, barrnap | completeness, metrics, rRNA |

---

## Results

Four assemblies were produced and compared on real data
(Illumina `SRR25745292` + Nanopore `SRR27991387`):

| Assembly | Contigs | N50 | Length (bp) | BUSCO completeness | rRNA |
|---|---:|---:|---:|---|---:|
| SPAdes Illumina-only | 131 | 146,822 | 4,108,876 | **99.0%** | 24 |
| SPAdes hybrid | 3 | 2,994,832 | 4,260,732 | 98.9% | 31 |
| Flye (Nanopore, raw) | 2 | 3,001,672 | 4,265,992 | 87.1% | 31 |
| **Flye + Pilon** | **2** | **3,002,574** | 4,267,271 | **98.7%** | 31 |

*BUSCO lineage `vibrio_odb12`, n = 1570 single-copy orthologs.*

**Key takeaways:**
- *V. cholerae* has **two chromosomes** (~2.96 Mb + ~1.07 Mb). Long-read
  assemblies (Flye, Flye + Pilon) produced exactly **2 contigs** —
  chromosome-level assembly.
- **Illumina-only**: highest per-base accuracy (99% BUSCO) but fragmented
  (131 contigs) — short reads cannot span repeats.
- **Hybrid**: the best trade-off — nearly complete (98.9%) *and* contiguous.
- **Flye (raw)**: maximally contiguous (2 contigs) but low completeness
  (87.1%) — nanopore indel errors break gene models.
- **Flye + Pilon**: short-read polishing raised completeness from
  **87.1% → 98.7%** while keeping 2 contigs — a clear demonstration of why
  polishing matters.

Detailed reports and the two final assemblies are in
[`results_showcase/`](results_showcase/RESULTS.md).

---

## Requirements

- Linux + [conda](https://docs.conda.io/) (or mamba)
- ~30–50 GB of free disk space for results
- Internet access (BUSCO downloads the `vibrio_odb12` lineage, ~100 MB)

---

## Installation

```bash
git clone https://github.com/koncevojdanila10-source/de_nova.git
cd de_nova
chmod +x 00_setup.sh run_denovo.sh
./00_setup.sh          # creates conda environments and installs all tools
```

`00_setup.sh --busco` additionally pre-downloads the BUSCO lineage.

---

## Data

The scripts expect input data in two folders (not included in the
repository — see `.gitignore`):

```
data/     SRR25745292_..._1.fastq.gz   # Illumina R1
          SRR25745292_..._2.fastq.gz   # Illumina R2
data_n/   SRR27991387_..._1.fastq.gz   # Nanopore
```

Download the raw reads from the NCBI SRA using the accessions
`SRR25745292` (Illumina) and `SRR27991387` (Nanopore).

---

## Usage

```bash
./run_denovo.sh                    # full pipeline
./run_denovo.sh qc assembly        # selected stages only
```

Available stage labels: `qc assembly scaffolding polishing compare evaluate`.
All output is written to `results/`.

---

## Repository structure

```
.
├── 00_setup.sh          # environment and tool installation (conda)
├── run_denovo.sh        # main assembly pipeline
├── results_showcase/    # key results: final assemblies + QUAST/BUSCO reports
├── .gitignore
├── LICENSE
└── README.md
```

---

## Based on

A genome-assembly practical: read quality control, graph-based assembly
algorithms, hybrid strategies and post-processing.
