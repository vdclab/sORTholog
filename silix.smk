# Rule for silix

##########################################################################
##########################################################################


rule silix:
    input:
        fasta=os.path.join(
            OUTPUT_FOLDER, "databases", "merge_fasta", "all_protein_with_seeds.fasta"
        ),
        blast_out=os.path.join(
            OUTPUT_FOLDER,
            "processing_files",
            "blast",
            "split_blast_out",
            "filtered_blast--{seed}_evalue_{eval}_cov_{coverage}_pid_{pid}.out",
        ),
    output:
        os.path.join(
            OUTPUT_FOLDER,
            "processing_files",
            "silix",
            "fnodes_files",
            "filtered_blast--{seed}_evalue_{eval}_cov_{coverage}_pid_{pid}.fnodes",
        ),
    params:
        minimum_overlap=silix_dict[cov_min],
        minimum_percId=silix_dict[pid_min],
        minimum_length=length_min,
    log:
        os.path.join(
            OUTPUT_FOLDER,
            "logs",
            "silix",
            "{seed}_evalue_{eval}_cov_{coverage}_pid_{pid}.silix.log",
        ),

    shell:
        """
        # Check if silix is available
        if ! command -v silix >/dev/null 2>&1; then
            echo "ERROR: silix command not found." >&2
            echo "On macOS, install SILIX with:" >&2
            echo "  brew install boost" >&2
            echo "  cd /tmp && curl -L https://pbil.univ-lyon1.fr/software/download/silix/silix-1.3.0.tar.gz | tar xz" >&2
            echo "  cd silix-1.3.0 && CPPFLAGS=\"-I/opt/homebrew/include\" LDFLAGS=\"-L/opt/homebrew/lib\" ./configure" >&2
            echo "  make && cp src/silix ~/bin/ && chmod +x ~/bin/silix" >&2
            echo "  echo 'export PATH=\"$HOME/bin:$PATH\"' >> ~/.zshrc && source ~/.zshrc" >&2
            exit 1
        fi
        
        if [ -s {input.blast_out} ]
        then   
            silix "{input.fasta}" "{input.blast_out}" -f "{wildcards.seed}"\
               -i "{wildcards.pid}" -r "{wildcards.coverage}" -q "{params.minimum_overlap}"\
               -s "{params.minimum_percId}" -l "{params.minimum_length}" > "{output}" 2> {log}
        else
            touch '{output}'
        fi
        """


##########################################################################
##########################################################################
