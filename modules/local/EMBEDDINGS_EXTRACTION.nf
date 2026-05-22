process EMBEDDINGS_EXTRACTION {
    tag "${work_path} - ${plate} - ${time}"
    conda "/home/dcmacho/miniconda3/envs/cell_analysis" 
    maxForks 1 

    // to do: docker based codna container usage of docker pass --gpus all

    input:
    tuple val(work_path),val(image_folder), val(plate), val(time),val(single_cell)
    
    script:

    def single_cell_flag = (single_cell.toString().toLowerCase() == 'true' || single_cell.toString() == '1') ? '--single_cell' : ''

    def xgb_flag = params.xgb_model_path ? "--xgb-model-path ${params.xgb_model_path}" : ''

    """
    python /home/dcmacho/cellpose-efficient-pipeline/image-processing-suite/Cellpose_GPU_s3fs.py \\
        --bucket-input "cellprofiler-resuts"\\
        --load-data-key "${work_path}/load_data_${plate}_${time}.csv"\\
        --data-base-path "${params.NAS_folder}/${image_folder}"\\
        --csv-image-key "/mnt/s3_results/${work_path}/${plate}/${time}/Image.csv"\\
        --channels ${params.channels}\\
        --num-consumers 4 ${single_cell_flag}\\
        --max-workers 16 ${xgb_flag}\\
        --save-coords\\
        --xgb-model-path ${params.xgb_model_path}\\
        --out-data-path "s3://cellprofiler-resuts/${work_path}/embeddings_${plate}_${time}.parquet"
    """
}