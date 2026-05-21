process CELLPROFILER_ILLUM {
    tag "${work_path} - ${plate} - ${time}"
    container 'cellprofiler/cellprofiler:4.2.8'
    maxForks 4

    input:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell)

    output:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell)

    script:
    """
    cellprofiler -c -r \\
        -p /mnt/s3out/${params.cppipe_path} \\
        -o /mnt/s3out/${work_path}/${plate}/${time} \\
        --data-file /mnt/s3out/${work_path}/load_data_${plate}_${time}.csv
    """
}