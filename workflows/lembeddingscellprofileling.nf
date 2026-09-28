/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_lembeddingscellprofileling_pipeline'
include { CELLPROFILER_ILLUM } from '../modules/local/CELLPROFILER_ILLUM.nf'
include { QC_MULT } from '../modules/local/QC_MULT.nf'
include { EMBEDDINGS_EXTRACTION } from '../modules/local/EMBEDDINGS_EXTRACTION.nf'
include { EMBEDDINGS_EXTRACTION_NETWORK } from '../modules/local/EMBEDDINGS_EXTRACTION_NETWORK.nf'
include { QC_REPORT_ANNOT } from '../modules/local/QC_REPORT_ANNOT.nf'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow LEMBEDDINGSCELLPROFILELING {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    outdir

    main:

    def ch_versions = channel.empty()

    // 0. TO DO: Create load data file module

    // 1. Run CellProfiler

    CELLPROFILER_ILLUM( ch_samplesheet )

    // 2. Run QC metrics

    // collect(flat: false) keeps each row intact (flatten would drop empty optional columns)
    QC_MULT(CELLPROFILER_ILLUM.out.collect(flat: false).flatMap { it })
    
    // 3. Run Image.csv annotation
    // collection then flatting to force all QC_MULT to finish first

    QC_REPORT_ANNOT(QC_MULT.out)

    // 4. Run embedding extraction

    // Rows flagged network_analysis (neurons) go to the soma/network extractor

    def ch_embed = QC_REPORT_ANNOT.out.meta
        .collect(flat: false)
        .flatMap { it }
        .branch { row ->
            network: row[5]
            standard: true
        }

    EMBEDDINGS_EXTRACTION(ch_embed.standard)

    // Both extractors share the GPUs, so network rows start only once the standard ones finish.
    // toList() still emits (an empty list) when there were no standard rows.

    def ch_standard_done = EMBEDDINGS_EXTRACTION.out.toList().map { 'done' }

    EMBEDDINGS_EXTRACTION_NETWORK(ch_embed.network.combine(ch_standard_done).map { row -> row[0..-2] })

    // 5. DMSO outlier detection, Embedding Normalization, PCA and bioactivity. 


    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'lembeddingscellprofileling_software_'  + 'versions.yml',
            sort: true,
            newLine: true
        )
    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
