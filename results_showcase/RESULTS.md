# Assembly results — *Vibrio cholerae*

The pipeline was run on real data (Illumina `SRR25745292` + Nanopore
`SRR27991387`). **Four assemblies** were produced and evaluated to compare
approaches.

## Assembly comparison

| Assembly | Contigs | N50 | Length (bp) | GC % | BUSCO completeness | rRNA |
|---|---:|---:|---:|---:|---|---:|
| SPAdes Illumina-only | 131 | 146,822 | 4,108,876 | 47.38 | **C:99.0%** F:0.3% M:0.7% | 24 |
| SPAdes hybrid | 3 | 2,994,832 | 4,260,732 | 47.35 | C:98.9% F:0.3% M:0.8% | 31 |
| Flye (Nanopore, raw) | 2 | 3,001,672 | 4,265,992 | 47.38 | C:87.1% F:6.9% M:5.9% | 31 |
| **Flye + Pilon** | **2** | **3,002,574** | 4,267,271 | 47.37 | **C:98.7%** F:0.6% M:0.8% | 31 |

BUSCO against the `vibrio_odb12` lineage (n = 1570 single-copy orthologs).
C = complete, F = fragmented, M = missing.

## Conclusions

- The *V. cholerae* genome consists of **two chromosomes** (~2.96 Mb +
  ~1.07 Mb). Long-read assemblies (Flye, Flye + Pilon) produced exactly
  **2 contigs** — a **chromosome-level** assembly.
- **Illumina-only**: high per-base accuracy (99% BUSCO) but fragmented
  (131 contigs) — short reads cannot resolve repeats.
- **Hybrid**: a good compromise — nearly complete (98.9%) and contiguous
  (3 contigs) at the same time.
- **Flye (raw)**: maximal contiguity (2 contigs) but low completeness
  (87.1%) — nanopore indel errors break gene models.
- **Flye + Pilon**: short-read polishing raised completeness from
  **87.1% → 98.7%** while keeping 2 contigs — a clear demonstration of why
  polishing is needed.

## Contents of this folder

```
assemblies/   final assemblies (FASTA): spades_hybrid, flye_pilon
quast/        QUAST reports for all 4 assemblies (N50, length, # contigs)
busco/        BUSCO summaries for all 4 assemblies (completeness)
```

The full results (all assemblies, intermediate files, HTML reports) are
reproducible by running the pipeline — see the [README](../README.md). Raw
reads are not stored in the repository; download them from the SRA using the
accessions `SRR25745292` and `SRR27991387`.
