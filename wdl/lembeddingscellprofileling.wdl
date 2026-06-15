version 1.0

## ---------------------------------------------------------------------------
## Saguaro-Biosciences/lembeddingscellprofileling  —  WDL 1.0 port (Cromwell)
##
## Lift-and-shift translation of the Nextflow pipeline. This is a faithful 1:1
## port: it assumes the SAME machine the Nextflow version runs on, i.e.
##   - NAS / s3fs mounts already present (/mnt/ugreen_nas_v1, /mnt/s3_results,
##     and /mnt/s3out inside the CellProfiler container)
##   - host conda env at /home/dcmacho/miniconda3/envs/cell_analysis
##   - host scripts at /home/dcmacho/cellpose-efficient-pipeline/...
##   - passwordless `sudo systemctl restart autofs`
##   - a GPU on the host for the embedding step
##
## Data flow is via SIDE EFFECTS to S3/NAS (not WDL File localization), exactly
## like the Nextflow processes. Tasks therefore pass plain Strings, and ordering
## between stages is enforced by threading a "barrier" array from one scatter to
## the next (the WDL equivalent of `.collect().flatten().collate(5)`).
##
## See wdl/README.md for how to run, plus the Cromwell backend config required
## for the CellProfiler container volume mounts and the maxForks limits.
## ---------------------------------------------------------------------------

workflow lembeddingscellprofileling {
    input {
        # --- core input ---
        File   samplesheet                                                       # CSV: work_path,image_folder,plate,time,single_cell

        # --- params (defaults mirror nextflow.config) ---
        String nas_folder      = "/mnt/ugreen_nas_v1/clientsdata"                 # params.NAS_folder
        String cppipe_path     = "IRIC/Image_Processing_Pipelines/2B.Illumination_Correction_CL2.0_IB.cppipe"  # params.cppipe_path
        String channels        = "DNA CL640 CL488R CL488Y"                        # params.channels (space-separated, passed unquoted)
        String? xgb_model_path                                                    # params.xgb_model_path (optional)

        # --- host environment (lift-and-shift; verify these on your machine) ---
        String conda_sh    = "/home/dcmacho/miniconda3/etc/profile.d/conda.sh"
        String conda_env   = "/home/dcmacho/miniconda3/envs/cell_analysis"
        String script_dir  = "/home/dcmacho/cellpose-efficient-pipeline/image-processing-suite"
        String cellprofiler_container = "docker.io/cellprofiler/cellprofiler:4.2.8"
    }

    # 0. Parse the samplesheet CSV -> clean 5-column TSV (header stripped).
    #    Equivalent of nf-schema's samplesheetToList(...).
    call ParseSamplesheet { input: samplesheet = samplesheet }
    Array[Array[String]] rows = read_tsv(ParseSamplesheet.tsv)

    # 1. Run CellProfiler  (Nextflow: CELLPROFILER_ILLUM, maxForks 4, container)
    scatter (row in rows) {
        call CELLPROFILER_ILLUM {
            input:
                work_path    = row[0],
                image_folder = row[1],
                plate        = row[2],
                time         = row[3],
                single_cell  = row[4],
                cppipe_path  = cppipe_path,
                container    = cellprofiler_container
        }
    }
    Array[String] cp_done = CELLPROFILER_ILLUM.done

    # 2. Run QC metrics  (Nextflow: QC_MULT, cpus 20, maxForks 1)
    #    BARRIER: depends on the whole cp_done array => waits for ALL CellProfiler
    #    jobs, reproducing `.collect().flatten().collate(5)`.
    scatter (row in rows) {
        call QC_MULT {
            input:
                work_path    = row[0],
                image_folder = row[1],
                plate        = row[2],
                time         = row[3],
                single_cell  = row[4],
                nas_folder   = nas_folder,
                channels     = channels,
                conda_sh     = conda_sh,
                conda_env    = conda_env,
                script_dir   = script_dir,
                upstream     = cp_done
        }
    }
    Array[String] qc_done = QC_MULT.done

    # 3. Image.csv annotation + QC report  (Nextflow: QC_REPORT_ANNOT, maxForks 20)
    #    BARRIER on all QC_MULT. Captures the published *.html files.
    scatter (row in rows) {
        call QC_REPORT_ANNOT {
            input:
                work_path    = row[0],
                image_folder = row[1],
                plate        = row[2],
                time         = row[3],
                single_cell  = row[4],
                conda_sh     = conda_sh,
                conda_env    = conda_env,
                script_dir   = script_dir,
                upstream     = qc_done
        }
    }
    Array[String] annot_done = QC_REPORT_ANNOT.done

    # 4. Embedding extraction  (Nextflow: EMBEDDINGS_EXTRACTION, GPU, maxForks 1)
    #    BARRIER on all QC_REPORT_ANNOT.
    scatter (row in rows) {
        call EMBEDDINGS_EXTRACTION {
            input:
                work_path      = row[0],
                image_folder   = row[1],
                plate          = row[2],
                time           = row[3],
                single_cell    = row[4],
                nas_folder     = nas_folder,
                channels       = channels,
                xgb_model_path = xgb_model_path,
                conda_sh       = conda_sh,
                conda_env      = conda_env,
                script_dir     = script_dir,
                upstream       = annot_done
        }
    }

    output {
        # The only real captured file output (Nextflow: QC_REPORT_ANNOT publishDir *.html).
        # Use Cromwell's `final_workflow_outputs_dir` to mimic publishDir copying.
        Array[File] qc_html = flatten(QC_REPORT_ANNOT.html)
    }
}

## ---------------------------------------------------------------------------
## TASKS
## ---------------------------------------------------------------------------

# Convert the input CSV into a clean, header-less, 5-column TSV so the workflow
# can read_tsv() it. Missing `single_cell` defaults to "false" (it is optional
# in assets/schema_input.json). NOTE: assumes no embedded commas in fields
# (same simplification as plain CSV splitting; nf-schema would handle quoting).
task ParseSamplesheet {
    input {
        File samplesheet
    }
    command <<<
        set -euo pipefail
        tail -n +2 "~{samplesheet}" \
            | tr -d '\r' \
            | awk -F',' 'NF>=4 { sc=($5==""?"false":$5); printf "%s\t%s\t%s\t%s\t%s\n",$1,$2,$3,$4,sc }' \
            > rows.tsv
    >>>
    output {
        File tsv = "rows.tsv"
    }
    runtime {
        # runs on host (bash only)
    }
}

# Nextflow: modules/local/CELLPROFILER_ILLUM.nf
#   container 'docker.io/cellprofiler/cellprofiler:4.2.8'  (entrypoint cleared)
#   maxForks 4  -> set concurrent-job-limit on the CellProfiler backend (see README)
# Requires the container to be started with the same volume mounts as the
# Nextflow `docker` profile: -v <NAS>:/mnt/s3 -v /mnt/s3_results:/mnt/s3out
# -v ~/.aws:/root/.aws  -> configured via Cromwell submit-docker (see README).
task CELLPROFILER_ILLUM {
    input {
        String work_path
        String image_folder
        String plate
        String time
        String single_cell
        String cppipe_path
        String container
    }
    command <<<
        set -euo pipefail

        cellprofiler -c -r \
            -p "/mnt/s3out/~{cppipe_path}" \
            -o "/mnt/s3out/~{work_path}/~{plate}/~{time}" \
            --data-file "/mnt/s3out/~{work_path}/load_data_~{plate}_~{time}.csv"
    >>>
    output {
        String done = "~{work_path}/~{plate}/~{time}"
    }
    runtime {
        docker: container
        cpu: 1
        memory: "6 GB"
    }
}

# Nextflow: modules/local/QC_MULT.nf  (host conda env, cpus 20, maxForks 1)
task QC_MULT {
    input {
        String work_path
        String image_folder
        String plate
        String time
        String single_cell
        String nas_folder
        String channels
        String conda_sh
        String conda_env
        String script_dir
        Array[String] upstream     # barrier: all CELLPROFILER_ILLUM must finish first
        Int cpus = 20
    }
    command <<<
        set -euo pipefail
        echo "Barrier: ~{length(upstream)} CellProfiler task(s) complete"

        sudo systemctl restart autofs
        source "~{conda_sh}"
        conda activate "~{conda_env}"

        python ~{script_dir}/Illumination_QC_mult.py \
            --load-data "/mnt/s3_results/~{work_path}/load_data_~{plate}_~{time}.csv" \
            --data-path "~{nas_folder}/~{image_folder}" \
            --channels ~{channels} \
            --illum-path "/mnt/s3_results/~{work_path}/~{plate}/~{time}" \
            --threads ~{cpus} \
            --output "s3://cellprofiler-resuts/~{work_path}/~{plate}/~{time}/Image.csv"
    >>>
    output {
        String done = "~{work_path}/~{plate}/~{time}"
    }
    runtime {
        # no docker: runs on host, using the host conda env
        cpu: cpus
        memory: "6 GB"
    }
}

# Nextflow: modules/local/QC_REPORT_ANNOT.nf  (host conda env, maxForks 20)
#   publishDir { "${params.outdir}/qc_plots/<image_folder[-2]>/${plate}/${time}" }
# The script is expected to write *.html into the working directory; we capture
# them with glob() and expose them via the workflow output.
task QC_REPORT_ANNOT {
    input {
        String work_path
        String image_folder
        String plate
        String time
        String single_cell
        String conda_sh
        String conda_env
        String script_dir
        Array[String] upstream     # barrier: all QC_MULT must finish first
    }
    command <<<
        set -euo pipefail
        echo "Barrier: ~{length(upstream)} QC_MULT task(s) complete"

        source "~{conda_sh}"
        conda activate "~{conda_env}"

        python ~{script_dir}/qc_report_annotation.py \
            --work_path "~{work_path}" \
            --plate "~{plate}" \
            --time "~{time}"
    >>>
    output {
        Array[File] html = glob("*.html")
        String done = "~{work_path}/~{plate}/~{time}"
    }
    runtime {
        # no docker: runs on host, using the host conda env
        cpu: 1
        memory: "6 GB"
    }
}

# Nextflow: modules/local/EMBEDDINGS_EXTRACTION.nf  (host conda env, GPU, maxForks 1)
# No declared file outputs in the original (writes a .parquet to S3 as a side effect).
task EMBEDDINGS_EXTRACTION {
    input {
        String work_path
        String image_folder
        String plate
        String time
        String single_cell
        String nas_folder
        String channels
        String? xgb_model_path
        String conda_sh
        String conda_env
        String script_dir
        Array[String] upstream     # barrier: all QC_REPORT_ANNOT must finish first
    }
    command <<<
        set -euo pipefail
        echo "Barrier: ~{length(upstream)} QC_REPORT_ANNOT task(s) complete"

        sudo systemctl restart autofs
        source "~{conda_sh}"
        conda activate "~{conda_env}"

        # single_cell flag: true / 1 (case-insensitive) -> --single-cell
        sc=$(printf '%s' "~{single_cell}" | tr '[:upper:]' '[:lower:]')
        sc_flag=""
        if [ "$sc" = "true" ] || [ "$sc" = "1" ]; then sc_flag="--single-cell"; fi

        python ~{script_dir}/Cellpose_GPU_s3fs.py \
            --bucket-input "cellprofiler-resuts" \
            --load-data-key "~{work_path}/load_data_~{plate}_~{time}.csv" \
            --data-base-path "~{nas_folder}/~{image_folder}" \
            --csv-image-key "/mnt/s3_results/~{work_path}/~{plate}/~{time}/" \
            --channels ~{channels} \
            --num-consumers 4 $sc_flag \
            --max-workers 16 ~{"--xgb-model-path " + xgb_model_path} \
            --save-coords \
            --out-data-path "s3://cellprofiler-resuts/~{work_path}/embeddings_~{plate}_~{time}.parquet"
    >>>
    output {
        String done = "~{work_path}/~{plate}/~{time}"
    }
    runtime {
        # no docker: runs on host (GPU). maxForks 1 -> serialize via backend
        # concurrent-job-limit = 1 (see README); GPUs can't share this job.
        cpu: 1
        memory: "6 GB"
    }
}
