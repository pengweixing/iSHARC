#################################################
## prepare library files for cellrancer_arc_count
## starting from the FASTQ files
#################################################
rule prep_library_file:
    input:
        samples_list
    output:
        "arc_count/{sample}_library.csv"
    params:
        id = get_sample_seq_id,
        gex_path = get_gex_seq_path,
        atac_path = get_atac_seq_path,
        out_dir = config["work_dir"]
    shell:
        ## generate library.csv per sample
        "mkdir -p {params.out_dir}/arc_count/{wildcards.sample}_fastq && "
        "ln -sfn {params.gex_path} {params.out_dir}/arc_count/{wildcards.sample}_fastq/gex && "
        "ln -sfn {params.atac_path} {params.out_dir}/arc_count/{wildcards.sample}_fastq/atac && "
        "echo 'fastqs,sample,library_type' > arc_count/{wildcards.sample}_library.csv && "
        "echo '{params.out_dir}/arc_count/{wildcards.sample}_fastq/gex,{params.id},Gene Expression' >>  arc_count/{wildcards.sample}_library.csv && "
        "echo '{params.out_dir}/arc_count/{wildcards.sample}_fastq/atac,{params.id},Chromatin Accessibility' >>  arc_count/{wildcards.sample}_library.csv "


##########################################################
## cellranger_arc_count
## starting from either FASTQ files or cell ranger outputs
##########################################################
rule cellranger_arc_count:
    input:
        library="arc_count/{sample}_library.csv"
    output:
        "arc_count/{sample}/outs/filtered_feature_bc_matrix.h5",
        "arc_count/{sample}/outs/atac_fragments.tsv.gz",
        "arc_count/{sample}/outs/per_barcode_metrics.csv"
    container:
        CELLRANGER_ARC_CONTAINER
    params:
        out_dir = config["work_dir"],
        arc_outs_path = get_arc_outs_path,
        arc_ref = config["arc_ref"],
        localcores = config.get("cellranger_localcores", config["threads"]),
        localmem = config.get("cellranger_localmem", 32),
        create_bam = str(config.get("cellranger_create_bam", True)).lower()
    threads: config["threads"]
    log:
        "logs/{sample}_cellranger_arc_count.log"
    run:
        if(config["arc_perf"]):
            shell("(cd {params.out_dir}/arc_count && "
                  "mkdir -p ./{wildcards.sample}/outs && "
                  "ln -sfn {params.arc_outs_path}/* ./{wildcards.sample}/outs) 2> {log}")
        else:
            shell("(cd {params.out_dir}/arc_count && "
                  "cellranger-arc count --id {wildcards.sample}_res --reference={params.arc_ref} "
                  "--libraries={params.out_dir}/{input.library} "
                  "--create-bam={params.create_bam} --localcores={params.localcores} --localmem={params.localmem} && "
                  "rm -r {wildcards.sample} && "
                  "mv {wildcards.sample}_res {wildcards.sample}) 2> {log}")
