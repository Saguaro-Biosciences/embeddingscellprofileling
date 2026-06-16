# Saguaro-Biosciences/lembeddingscellprofileling

[![GitHub Actions CI Status](https://github.com/Saguaro-Biosciences/lembeddingscellprofileling/actions/workflows/nf-test.yml/badge.svg)](https://github.com/Saguaro-Biosciences/lembeddingscellprofileling/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/Saguaro-Biosciences/lembeddingscellprofileling/actions/workflows/linting.yml/badge.svg)](https://github.com/Saguaro-Biosciences/lembeddingscellprofileling/actions/workflows/linting.yml)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A525.10.4-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-4.0.2-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/4.0.2)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

## Introduction

**Saguaro-Biosciences/lembeddingscellprofileling** is an image-based phenotypic profiling pipeline that turns high-content microscopy screens into quantitative, analysis-ready morphological data. Having both implementations in nextflow and WDL. Beginning from raw image sets organised by plate and timepoint, it standardises the imagery, screens it for quality, and derives compact numerical representations — _embeddings_ — that capture how cells respond to a given perturbation. The result is a consistent, comparable substrate for downstream analysis: identifying biological activity, grouping conditions by phenotype, and quantifying differences between treatments.

The pipeline is designed for scale. Each plate and timepoint is processed independently and in parallel, so the workflow grows naturally from a handful of samples to large screens without changes to how it is run. Stages are sequenced so that costly computation is only spent on data that has already passed quality control.

At a high level, the workflow proceeds through the following stages:

- **Image standardisation** — corrects systematic acquisition artefacts so that measurements are comparable across fields, wells, and plates.
- **Quality control** — computes image- and acquisition-level quality metrics and flags problematic data early.
- **Quality reporting** — produces human-readable reports that summarise the condition of each plate and timepoint for review.
- **Embedding extraction** — generates morphological feature representations at the population level, with an optional single-cell mode for finer-grained analysis.

These outputs are intended to feed directly into subsequent analysis steps such as normalisation, dimensionality reduction, and bioactivity assessment.

> [!IMPORTANT]
> **Proprietary software.** This pipeline and its associated code are the property of **Saguaro Biosciences** and are intended for internal use only. All rights reserved. It may not be copied, redistributed, published, or disclosed outside Saguaro Biosciences without prior written authorisation.

## Usage

> [!NOTE]
> If you are new to Nextflow and nf-core, please refer to [this page](https://nf-co.re/docs/get_started/environment_setup/overview) on how to set-up Nextflow. Make sure to [test your setup](https://nf-co.re/docs/get_started/run-your-first-pipeline) with `-profile test` before running the workflow on actual data.

First, prepare a samplesheet describing the data you want to process. Each **row** is one **plate at one timepoint**, and the pipeline processes every row independently and in parallel.

`samplesheet.csv`:

```csv
work_path,image_folder,plate,time,single_cell
IRIC/Phenotypic_screen_HY-L022-custom_U2OS/Subset3_1uM_Run01,Phenotypic_screen_HY-L022-custom_U2OS/Subset3_1uM_Run01/20250820T160354_6h_P15/Image,P15,6,TRUE
IRIC/Phenotypic_screen_HY-L022-custom_U2OS/Subset3_1uM_Run01,Phenotypic_screen_HY-L022-custom_U2OS/Subset3_1uM_Run01/20250820T220625_12h_P15/Image,P15,12,FALSE
```

| Column         | Required | Description                                                                                                                                      |
| -------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `work_path`    | Yes      | Working folder for this run in the results store. Determines where outputs are written (corrected images, QC tables/reports, and embeddings).     |
| `image_folder` | Yes      | Path to the raw image folder for this plate/timepoint on the shared image storage. Must match the directory holding the raw images exactly.       |
| `plate`        | Yes      | Plate identifier (e.g. `P15`). Used to route outputs and label reports.                                                                           |
| `time`         | Yes      | Acquisition timepoint in hours (e.g. `6`, `12`, `24`).                                                                                            |
| `single_cell`  | No       | `TRUE`/`1` to enable single-cell embedding extraction; otherwise `FALSE` (default).                                                              |

> [!NOTE]
> Paths are interpreted relative to the storage locations configured for the pipeline (the shared image store for `image_folder`, the results store for `work_path`). See [`assets/schema_input.json`](assets/schema_input.json) for the authoritative column definitions and [`assets/samplesheet.csv`](assets/samplesheet.csv) for a complete example.

Now, you can run the pipeline using:

<!-- TODO nf-core: update the following command to include all required parameters for a minimal example -->

```bash
nextflow run Saguaro-Biosciences/lembeddingscellprofileling \
   -profile <docker/singularity/.../institute> \
   --input samplesheet.csv \
   --outdir <OUTDIR>
```

> [!WARNING]
> Please provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration _**except for parameters**_; see [docs](https://nf-co.re/docs/running/run-pipelines#using-parameter-files).

## Credits

Saguaro-Biosciences/lembeddingscellprofileling was originally written by Diego Camacho.

We thank the following people for their extensive assistance in the development of this pipeline:

<!-- TODO nf-core: If applicable, make list of people who have also contributed -->

## Contributions and Support

If you would like to contribute to this pipeline, please see the [contributing guidelines](docs/CONTRIBUTING.md).

## Citations

<!-- TODO nf-core: Add bibliography of tools and data used in your pipeline -->

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.

This repository incorporates template code and infrastructure developed and maintained by the [nf-core](https://nf-co.re) community, reused here under the [MIT license](https://github.com/nf-core/tools/blob/main/LICENSE). That MIT license applies **only** to those nf-core framework components. The pipeline itself — including its workflow logic and associated code — is proprietary and remains the property of Saguaro Biosciences; see [`LICENSE`](LICENSE).

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).
