process QC_MULT {
    tag "${work_path} - ${plate} - ${time}"
    container "${params.pipeline_container}"
    conda "${params.conda_env}"
    cpus 20
    maxForks 1

    input:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell), val(network), val(channels)

    output:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell), val(network), val(channels)
    
    script:

    """
    ${params.restart_autofs ? 'sudo systemctl restart autofs' : ''}
    Illumination_QC_mult.py \\
        --load-data "${params.s3_results_mount}/${work_path}/load_data_${plate}_${time}.csv" \\
        --data-path "${params.NAS_folder}/${image_folder}" \\
        --channels ${channels} \\
        --illum-path "${params.s3_results_mount}/${work_path}/${plate}/${time}" \\
        --threads ${task.cpus} \\
        --output "s3://cellprofiler-resuts/${work_path}/${plate}/${time}/Image.csv"
    """
}
