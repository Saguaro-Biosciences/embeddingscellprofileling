process QC_MULT {
    tag "${work_path} - ${plate} - ${time}"
    conda "/home/dcmacho/miniconda3/envs/cell_analysis" 
    cpus 20

    input:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell)

    output:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell)
    
    script:

    """
    python /home/dcmacho/cellpose-efficient-pipeline/image-processing-suite/Illumination_QC_mult.py \\
        --load-data "/mnt/s3_results/${work_path}/load_data_${plate}_${time}.csv" \\
        --data-path "${params.NAS_folder}/${image_folder}" \\
        --channels "${params.channels}" \\
        --illum-path "/mnt/s3_results/${work_path}/${plate}/${time}" \\
        --threads ${task.cpus} \\
        --output "s3://cellprofiler-resuts/${work_path}/${plate}/${time}/Image.csv"
    """
}