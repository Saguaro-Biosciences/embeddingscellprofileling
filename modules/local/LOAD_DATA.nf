process LOAD_DATA {
    tag "${work_path} - ${plate} - ${time}"
    container "${params.pipeline_container}"
    conda "${params.conda_env}"
    maxForks 8

    // Keep a copy of every load_data file this run wrote, next to the QC plots
    publishDir { "${params.outdir}/load_data/${work_path}" }, mode: params.publish_dir_mode, pattern: '*.csv'

    input:
    tuple val(work_path), val(image_folder), val(plate), val(time), val(single_cell), val(network), val(channels)

    output:
    // The row passes through unchanged so CELLPROFILER_ILLUM starts only once its load_data exists
    tuple val(work_path), val(image_folder), val(plate), val(time), val(single_cell), val(network), val(channels), emit: meta
    path "load_data_${plate}_${time}.csv", optional: true, emit: csv

    script:
    def channel_map = params.channel_map ? "--channel-map \"${params.channel_map}\"" : ''
    def overwrite   = params.overwrite_load_data ? '--overwrite' : ''
    def columns     = params.plate_columns ? "--plate-columns ${params.plate_columns}" : ''
    """
    make_load_data.py \\
        --image-dir "${params.NAS_folder}/${image_folder}" \\
        --path-prefix "/mnt/s3/${image_folder}" \\
        ${channel_map} \\
        --plate "${plate}" \\
        --time "${time}" \\
        --require-channels ${channels} \\
        ${columns} \\
        --local-copy "load_data_${plate}_${time}.csv" \\
        --output "s3://cellprofiler-resuts/${work_path}/load_data_${plate}_${time}.csv" ${overwrite}
    """
}
