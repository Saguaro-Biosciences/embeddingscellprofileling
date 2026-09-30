// Neuron-specific variant of EMBEDDINGS_EXTRACTION: adds soma-subtracted axon-network
// metrics and embeddings. Selected per row with network_analysis=true in the samplesheet.
process EMBEDDINGS_EXTRACTION_NETWORK {
    tag "${work_path} - ${plate} - ${time}"
    container "${params.pipeline_container}"
    conda "${params.conda_env}"
    containerOptions { params.use_gpu ? (workflow.containerEngine in ['singularity', 'apptainer'] ? '--nv' : '--gpus all') : '' }
    maxForks 1 

    input:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell), val(network), val(channels)

    output:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell), val(network), val(channels)
    
    script:

    def single_cell_flag = (single_cell.toString().toLowerCase() == 'true' || single_cell.toString() == '1') ? '--single-cell' : ''

    def xgb_flag = params.xgb_model_path ? "--xgb-model-path ${params.xgb_model_path}" : ''

    def min_size_flag = params.min_size_filter ? "--min-size-filter ${params.min_size_filter}" : ''

    """
    ${params.restart_autofs ? 'sudo systemctl restart autofs' : ''}
    Cellpose_GPU_s3fs_soma_netork.py \\
        --bucket-input "cellprofiler-resuts"\\
        --load-data-key "${work_path}/load_data_${plate}_${time}.csv"\\
        --data-base-path "${params.NAS_folder}/${image_folder}"\\
        --csv-image-key "${params.s3_results_mount}/${work_path}/${plate}/${time}/"\\
        --channels ${channels}\\
        --num-consumers 4 ${single_cell_flag}\\
        --max-workers 16 ${xgb_flag} ${min_size_flag}\\
        --save-coords\\
        --network-metrics \\
        --network-embeddings \\
        --network-metric-set ${params.network_metric_set} \\
        --network-channels ${params.network_channels} \\
        --out-data-path "s3://cellprofiler-resuts/${work_path}/embeddings_${plate}_${time}.parquet"
    """
}
