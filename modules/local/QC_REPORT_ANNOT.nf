process QC_REPORT_ANNOT {
    tag  "${work_path} - ${plate} - ${time}"
    conda "/home/dcmacho/miniconda3/envs/cell_analysis" 
    
    // Publishes the HTML files to a folder in your pipeline's output directory
    publishDir { "${params.outdir}/qc_plots/${image_folder.tokenize('/')[-2]}/${plate}/${time}" } , mode: 'copy'

    input:
    // Receives the tuple from the previous step
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell)

    output:
    // Pass the tuple along in case you add more steps, AND capture the HTML file
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell)
    path "*.html", emit: html

    script:
    """
    python /home/dcmacho/cellpose-efficient-pipeline/image-processing-suite/qc_report_annotation.py \\
        --path "${work_path}" \\
        --plate "${plate}" \\
        --time "${time}"
    """
}