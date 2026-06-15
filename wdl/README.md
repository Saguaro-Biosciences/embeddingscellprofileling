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

## Behavioural notes & caveats (read these)

1. **maxForks is per-backend in Cromwell, not per-task.** `cromwell.local.conf`
   caps the host backend at `concurrent-job-limit = 1` — the safe choice because
   QC_MULT (`cpus 20`) and EMBEDDINGS (GPU) both use `maxForks 1` in Nextflow and
   cannot share the host. The trade-off: CELLPROFILER (`maxForks 4`) and
   QC_REPORT_ANNOT (`maxForks 20`) also run serially. To restore their
   parallelism, define extra backends with higher limits and route tasks with a
   `backend:` runtime attribute. CellProfiler runs in Docker, so you can give it
   its own backend with `concurrent-job-limit = 4` independently of the GPU work.

2. **The barrier is preserved.** Each stage receives the *full* array of the
   previous stage's `done` tokens, so Cromwell waits for **all** of stage N
   before **any** of stage N+1 — matching your `.collect()` comments. If you'd
   rather pipeline per-sample (faster, no global barrier), pass only the matching
   element instead of the whole array.

3. **Data flow is via side effects**, exactly like the Nextflow version: tasks
   read/write S3, NAS, and s3fs mounts directly and pass plain `String`s. Cromwell
   does **not** localize/delocalize this data. The only WDL-managed file output is
   `QC_REPORT_ANNOT`'s `*.html` (captured with `glob`).

4. **publishDir subfolders aren't reproduced exactly.** Nextflow published HTML to
   `qc_plots/<image_folder[-2]>/<plate>/<time>/`. Cromwell's
   `final_workflow_outputs_dir` copies declared outputs but not into that nested
   layout. If you need the exact tree, have `qc_report_annotation.py` write the
   subpath, or add a small post-processing task.

5. **`sudo`, `systemctl`, host conda, and host scripts make this non-portable.**
   That's inherent to the original pipeline, not the port. Moving to a clean
   Cromwell worker / cloud / Terra would require the *Containerize* approach
   (bake scripts + conda into images, localize data as `File`s) — ask and I can
   produce that variant.

6. **`set -euo pipefail`** mirrors the Nextflow `process.shell` settings. If
   `conda activate` trips on `set -u` in your conda version, relax to `set -eo
   pipefail` in the affected tasks.

7. **`channels`** is passed unquoted (`--channels DNA CL640 ...`) so the four
   values become separate argv, exactly as Nextflow interpolated them.

8. **CSV parsing** assumes no embedded commas in fields (plain comma split).
   nf-schema handled quoted commas; if your samplesheet needs that, pre-quote
   handling can be added to `ParseSamplesheet`.
