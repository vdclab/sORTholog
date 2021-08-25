# Rule for formating tables

##########################################################################
##########################################################################


rule read_psiblast:
    input:
        psiblast=os.path.join(
            OUTPUT_FOLDER,
            "processing_files",
            "psiblast",
            f"psiblast--eval_{e_val_psiblast:.0e}_raw.out",
        ),
    output:
        clean_blast=os.path.join(
            OUTPUT_FOLDER,
            "processing_files",
            "psiblast",
            f"psiblast--eval_{e_val_psiblast:.0e}_cleaned.out",
        ),
        list_all_prot=os.path.join(
            OUTPUT_FOLDER,
            "processing_files",
            "psiblast",
            f"list_all_protein--eval_{e_val_psiblast:.0e}.tsv",
        ),
    log:
        os.path.join(OUTPUT_FOLDER, "logs", "format_table", "read_psiblast.log"),
    conda:
        "../envs/pandas.yaml"
    script:
        "../scripts/format_psiblast.py"


##########################################################################
##########################################################################


rule prepare_for_silix:
    input:
        seed_file=os.path.join(OUTPUT_FOLDER, "databases", "seeds", "new_seeds.tsv"),
        protein_file=os.path.join(
            OUTPUT_FOLDER, "databases", "all_taxid", "protein_table.tsv"
        ),
        blast_out=os.path.join(
            OUTPUT_FOLDER, "processing_files", "blast", "blastp--blast_evalue_1e-2.out"
        ),
    output:
        os.path.join(
            OUTPUT_FOLDER,
            "processing_files",
            "blast",
            "split_blast_out",
            "filtered_blast--{seed}_evalue_{eval}_cov_{coverage}_pid_{pid}.out",
        ),
    log:
        os.path.join(
            OUTPUT_FOLDER,
            "logs",
            "prepare_for_silix",
            "{seed}_evalue_{eval}_cov_{coverage}_pid_{pid}.prepare_for_silix.log",
        ),
    group:
        "independent_seed"
    conda:
        "../envs/pandas.yaml"
    script:
        "../scripts/prepare_silix.py"


##########################################################################
##########################################################################


rule find_family:
    input:
        fnodes=os.path.join(
            OUTPUT_FOLDER,
            "processing_files",
            "silix",
            "fnodes_files",
            "filtered_blast--{seed}_evalue_{eval}_cov_{coverage}_pid_{pid}.fnodes",
        ),
        seed_file=os.path.join(OUTPUT_FOLDER, "databases", "seeds", "new_seeds.tsv"),
    output:
        os.path.join(
            OUTPUT_FOLDER,
            "processing_files",
            "silix",
            "modif",
            "filtered_blast--{seed}_evalue_{eval}_cov_{coverage}_pid_{pid}.fnodes.flushed",
        ),
    log:
        os.path.join(
            OUTPUT_FOLDER,
            "logs",
            "find_family",
            "{seed}_evalue_{eval}_cov_{coverage}_pid_{pid}.find_family.log",
        ),
    group:
        "independent_seed"
    conda:
        "../envs/pandas.yaml"
    script:
        "../scripts/find_family.py"


##########################################################################
##########################################################################


rule make_table:
    input:
        seed_file=os.path.join(OUTPUT_FOLDER, "databases", "seeds", "new_seeds.tsv"),
        protein_table=os.path.join(
            OUTPUT_FOLDER, "databases", "all_taxid", "protein_table.tsv"
        ),
        assembly_table=os.path.join(
            OUTPUT_FOLDER, "databases", "all_taxid", "summary_assembly_taxid.tsv"
        ),
        fnodes=expand(
            os.path.join(
                OUTPUT_FOLDER,
                "processing_files",
                "silix",
                "modif",
                "filtered_blast--{gene_constrains}.fnodes.flushed",
            ),
            gene_constrains=gene_constrains,
        ),
    output:
        final_table=report(
            os.path.join(OUTPUT_FOLDER, "results", "patab_melt.tsv"),
            caption="../report/PA_melt.rst",
            category="Tables",
        ),
        final_table_2=report(
            os.path.join(OUTPUT_FOLDER, "results", "patab_table.tsv"),
            caption="../report/PA_table.rst",
            category="Tables",
        ),
    log:
        os.path.join(OUTPUT_FOLDER, "logs", "format_table", "make_table.log"),
    conda:
        "../envs/pandas.yaml"
    script:
        "../scripts/PA-table.py"


##########################################################################
##########################################################################