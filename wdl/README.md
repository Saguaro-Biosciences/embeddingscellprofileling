# WDL port (Cromwell) — lift-and-shift

A WDL 1.0 translation of the Nextflow pipeline `Saguaro-Biosciences/lembeddingscellprofileling`.

This is a **lift-and-shift** port: it assumes the **same host** the Nextflow
version runs on, with the same mounts, conda env, host scripts, and GPU. It is
not portable to a clean cloud worker without further work (see *Caveats*).

## Files

| File | Purpose |
|------|---------|
| `lembeddingscellprofileling.wdl` | The workflow + 4 tasks |
| `inputs.json` | Example inputs (params + host paths) |
| `cromwell.local.conf` | Cromwell backend config (docker mounts, maxForks, publishDir) |

## What maps to what

| Nextflow | WDL |
|----------|-----|
| `workflow LEMBEDDINGSCELLPROFILELING` | `workflow lembeddingscellprofileling` |
| `process` × 4 | `task` × 4 (same names) |
| samplesheet channel via `samplesheetToList` | `ParseSamplesheet` task + `read_tsv` |
| scatter over samplesheet rows | `scatter (row in rows)` |
| `.collect().flatten().collate(5)` barrier | `Array[String]` "barrier token" threaded into the next scatter |
| `params.*` | workflow `input {}` declarations |
| `conda` directive | `source conda.sh && conda activate` in the command |
| `container` + docker profile mounts | `runtime { docker }` + `submit-docker` in `cromwell.local.conf` |
| `maxForks` | per-backend `concurrent-job-limit` |
| `publishDir` (`*.html`) | `glob("*.html")` output + `final_workflow_outputs_dir` |

## Run it

```bash
# from the repo root, with cromwell.jar available
java -Dconfig.file=wdl/cromwell.local.conf -jar cromwell.jar \
    run wdl/lembeddingscellprofileling.wdl \
    -i wdl/inputs.json
```

Validate first (no Cromwell needed):

```bash
womtool validate wdl/lembeddingscellprofileling.wdl
# or:  pip install miniwdl && miniwdl check wdl/lembeddingscellprofileling.wdl
```

## Before you run — verify on your host

The lift-and-shift assumes these exist on the machine Cromwell runs on, exactly
as in the Nextflow version. Check `inputs.json`:

- `conda_sh` / `conda_env` — the conda env at `/home/dcmacho/miniconda3/...`.
  (`conda_sh` is inferred as `<miniconda3>/etc/profile.d/conda.sh`; confirm it.)
- `script_dir` — the host scripts (`Illumination_QC_mult.py`,
  `qc_report_annotation.py`, `Cellpose_GPU_s3fs.py`).
- The mounts: `/mnt/ugreen_nas_v1/clientsdata` (NAS), `/mnt/s3_results`, and
  `/mnt/s3out` inside the CellProfiler container.
- Passwordless `sudo systemctl restart autofs` (QC_MULT and EMBEDDINGS run it).
- A GPU for `EMBEDDINGS_EXTRACTION`.
- AWS creds at `~/.aws` (mounted into the CellProfiler container, used for S3).
- Edit the NAS path / `${HOME}` in `cromwell.local.conf`'s `submit-docker` block
  to match your host.