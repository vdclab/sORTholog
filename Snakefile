# snakemake/5.17.0
# pipeline to test the presence of some proteins (aka seeds) in genome (given in taxid)
# usage: snakemake --cluster-config cluster.json --cluster "sbatch -c {cluster.c} --qos={cluster.qos} --time={cluster.time} --account={cluster.account} --mail-type={cluster.mail-type} --mail-user={cluster.mail-user} --mem_per_cpu={cluster.mem_per_cpu}"  -j 5 -d "/blue/lagard/ghutinet/modifications/trial_second" -C project_name='deazaguanine' e_val=0.01 id=0.1 cov=0.7
# -j : number of max core to use
# -d : directory of the files
# -C : configuration of values bellow:

# Taxid necessary to work
txid = config['taxid']

# Seed file input, default is seeds.txt
seed_file = config['seed'] if 'seed' in config else 'seeds.txt'

# Name your project, take the name of seed by default
project_name = config['project_name'] if 'project_name' in config else seed_file[:-4]

# Blast e-value thershold, 0.000001 by default but can be changed in -C
e_val = config['e_val'] if 'e_val' in config else 0.000001

# Software versions
blast_version = config['blast'] if 'blast' in config else '2.10.1'
silix_version = config['silix'] if 'silix' in config else '1.2.11'

# imports
from Bio import Entrez
from urllib.error import HTTPError
from http.client import IncompleteRead
import os
import shutil
import pandas as pd

Entrez.tool = 'draw presence/abscence v2'

# Create folders to work in
new_dir = f"{project_name}_eval{e_val}"

if not os.path.exists(new_dir):
    os.mkdir(new_dir)
    os.mkdir(f'{new_dir}/results')
    os.mkdir(f'{new_dir}/processing_files')

# Creating the wildcard necessary for latter use
def fetch_splitter(file):
    """
    open the taxid file and count the number of lines, then split it into 3 lists (1 or 2 if less than 3 taxids)

    return a list of file to create (list_to_return), and a number of line per file (per)

    Parameters
    ----------
    file : str
        the taxid file input.
        list in column of the taxids
    """
    with open(file, 'r') as file_to_count:
        file_len = len(file_to_count.read().split('\n'))

    if file_len == 1 or file_len == 2:
        divider = file_len
    else:
        divider = 3

    list_to_return = []
    count = 0
    per = round(file_len/divider)

    for _ in range(0, file_len, per):
        to_add = str(count)
        len_to_add = len(to_add)

        if len_to_add < 6:
            zeros = 'x'
            for _ in range(0, 6 - len_to_add, 1):
                zeros += '0'
            to_add = zeros + to_add

        list_to_return += [to_add]
        count += 1

    return list_to_return, per


def check(table, list_taxid):
    """
    Check each taxid of the taxid table o make sure they are the lowest level.
    If not remove the taxid and add the lower taxid(s)

    return the verified table of taxids

    Parameters
    ----------
    table : pandas DataFrame
        the taxid file input
        list in column of the taxids, column name is 'taxid'
    list_taxid : list of taxids
        taxid to be looked up.
    """
    for tx_id in list_taxid:
        try:
            esearch_result = Entrez.read(Entrez.esearch(db='taxonomy',term=f'txid{tx_id}[Orgn]'))

        except RuntimeError:
            esearch_result = Entrez.read(Entrez.esearch(db='taxonomy',term=f'txid{tx_id}[Orgn]'))

        except HTTPError:
            esearch_result = Entrez.read(Entrez.esearch(db='taxonomy',term=f'txid{tx_id}[Orgn]'))

        except IncompleteRead:
            esearch_result = Entrez.read(Entrez.esearch(db='taxonomy',term=f'txid{tx_id}[Orgn]'))

        new_tx_id_list = esearch_result['IdList']
        new_tx_id_list.remove(tx_id)

        if len(esearch_result['IdList']) > 1:
            # if not the minimum level of taxid, loop this rule on the lower taxids.
            table = check(table, new_tx_id_list)
            table.drop_duplicates(inplace=True)
            table.drop(table.index[table['taxid'] == tx_id].to_list(),inplace=True)

        elif tx_id not in table['taxid'].to_list():
            table = table.append({'taxid':tx_id}, ignore_index=True)

    return table


# Check the taxids
if not os.path.exists(f'{txid[:-4]}_verified.txt'):
    taxid_table = pd.read_csv(txid, header=None, names=['taxid'] ,dtype={'taxid': str})
    taxid_table = check(taxid_table, taxid_table.taxid.tolist())
    taxid_table.to_csv(f'{txid[:-4]}_verified.txt', index=False, header=False)

# Definition of the taxid splitter
splitter, nb_per_file = fetch_splitter(f'{txid[:-4]}_verified.txt')

# Definition of the list of seed
seed_table = pd.read_csv(seed_file, sep='\t', header=None,
            names=['name', 'protein_id', 'evalue', 'pident', 'cov',  'color'])
gene = seed_table.name.tolist()

# Definition of the requirements for each seed
seed_table.set_index('name', inplace=True)
gene_constrains = [ '{seed}_evalue{eval}_cov{cov}_pid{pid}'.format(
                seed=seed, eval=seed_table.at[seed,"evalue"], cov=seed_table.at[seed,"cov"],
                pid=seed_table.at[seed,"pident"]) for seed in gene ]
seed_table.reset_index(inplace=True)

# Comparing to previous results, deleting obsolete files
if os.path.exists(f'{new_dir}/results/copied_seed_{project_name}_psiblast_evalue{e_val}.csv'):
    copied_seed = pd.read_csv(f'{new_dir}/results/copied_seed_{project_name}_psiblast_evalue{e_val}.csv',
        sep='\t', header=None, names=['name', 'protein_id', 'evalue', 'pident', 'cov',  'color'])
    if not copied_seed.equals(seed_table):
        if os.path.exists(f'{new_dir}/results/plots'):
            shutil.rmtree(f'{new_dir}/results/plots')

shutil.copyfile(seed_file, f'{new_dir}/results/copied_seed_{project_name}_psiblast_evalue{e_val}.csv')

###########
## Rules ##
###########

rule all:
    """
    start the pipeline by checking the presence abscence table and the plots in pdf and png exist.
    """
    input:
        final_table = f'{new_dir}/results/patab_{project_name}_psiblast_evalue{e_val}.csv',
        pdf = expand('{new_dir}/results/plots/gene_table_{project_name}_{gene}.pdf',
                new_dir=new_dir, project_name=project_name, gene=gene),
        png = expand('{new_dir}/results/plots/gene_table_{project_name}_{gene}.png',
                new_dir=new_dir, project_name=project_name, gene=gene)


rule fetch_fasta_from_seed:
    """
    from the seed table and fetch the fasta of the seed. Then they are writen in the output file.

    Input : str
    -----
        the seed file input.
        table without header in the format : 
            name | protein id | e-value | percentage of identity | coverage | color
        
    Outputs : str
    -------   
        multifasta output of the seed sequences
    """
    output:
        f'seeds_{project_name}.fasta'
    run:
        from Bio import Entrez
        from Bio import SeqIO
        import pandas as pd

        Entrez.tool = 'draw presence/abscence v2'

        # getting seed sequences and writing the fasta file
        with Entrez.efetch(db='protein', id=seed_table.protein_id.to_list(), rettype='fasta', retmode='text') as handle:
            with open(str(output), 'w') as out_file:
                out_file.write(handle.read())


rule psiblast:
    """
    Use the sequences of the seeds to make a psiBLAST against all the taxid
    
    Inputs
    ------
    seed : str
        the seed multifasta file input from rule fetch_fasta_from_seed
    taxid : str
        list of taxid in columns, no header
        
    Output
    ------
    blast out : str
        blast out format in tabulation, no header
        format : query accession | query length | query sequence | query start position | querry end position |
                subject accession | subject length | subject sequence| subject start position | subject end position | 
                length of alignment | percentage of identity | e-value | bitscore | querry coverage
                
    Params
    ------
    e_val : int
        e-value threshold for psi-blast chosen by user
    blast_version : str
        blast version to use
    """
    input:
        seed = f'seeds_{project_name}.fasta',
        taxid = f'{txid[:-4]}_verified.txt'
    output:
        f'{new_dir}/processing_files/psiblast_{project_name}_eval{e_val}_raw.out'
    params:
        e_val = e_val,
        blast_version = blast_version
    threads:
        5
    shell:
        '''
        module load ncbi_blast/{params.blast_version}
        psiblast -query {input.seed} -db nr -taxidlist {input.taxid} -evalue {e_val}\
         -outfmt '6 qacc qlen qseq qstart qend sacc slen sseq sstart send length pident evalue bitscore qcovs'\
           -num_threads 5 -num_iterations 3 -out {output}
        '''


rule read_psiblast:
    """
    Read the psiBLAST, remove unwanted lines ane extract the list of matches
    
    Inputs
    ------
    psiblast : str
        blast out format in tabulation, no header, from the psiblast rule
        format : query accession | query length | query sequence | query start position | querry end position |
                subject accession | subject length | subject sequence| subject start position | subject end position | 
                length of alignment | percentage of identity | e-value | bitscore | querry coverage
            
    Outputs
    -------
    clean_blast : str
        cleaned blast out format in tabulation, no header
        format : query accession | query length | query sequence | query start position | querry end position |
                subject accession | subject length | subject sequence| subject start position | subject end position | 
                length of alignment | percentage of identity | e-value | bitscore | querry coverage
    list_all_prot : str
        list of all potein identifications gathered in the psiBLAST in column
    """
    input:
        psiblast = f'{new_dir}/processing_files/psiblast_{project_name}_eval{e_val}_raw.out'
    output:
        clean_blast = f'{new_dir}/processing_files/psiblast_{project_name}_eval{e_val}_cleaned.out',
        list_all_prot = f'{new_dir}/processing_files/list_all_protein_{project_name}_eval{e_val}.csv'
    run:
        import pandas as pd

        # Opening blastout
        blast_names = ['qacc', 'qlen', 'qseq','qstart', 'qend', 'sacc', 'slen', 'sseq', 'sstart', 'send','length',
                       'pident', 'evalue', 'bitscore', 'qcovs','qcovhsp', 'ssciname', 'sblastname', 'stitle']
        psiblast_result = pd.read_csv(str(input.psiblast),
                                      sep='\t',
                                      header=None,
                                      names=blast_names
                                      )

        # Cleaning blastout
        psiblast_result = psiblast_result[psiblast_result.qacc != 'Search has CONVERGED!']
        psiblast_result.to_csv(str(output.clean_blast), sep='\t', index=False)

        # Getting the list of protein matches
        pd.Series(psiblast_result.sacc.unique()).to_csv(str(output.list_all_prot), index=False, header=False)


rule split_taxid_file:
    """
    Split the taxid file into 3
    
    Input : str
    -----
        verified taxid file, list of taxid in column, no header
        
    Output : list of str
    ------
        three files of list of taxid in column, no header, determined by the fetch_splitter function.
        
    Params
    ------
    nb_per_file : int
        number of taxid per file, detrmined by the fetch_splitter function.
    """
    input:
        f'{txid[:-4]}_verified.txt'
    output:
        expand('taxid_files/{splitter}.txt', txid=txid, splitter=splitter)
    params:
        nb_per_file = nb_per_file
    shell:
        '''
        mkdir -p taxid_files
        cd taxid_files
        split -l {params.nb_per_file} --numeric-suffixes --suffix-length=6 --additional-suffix=.txt ../{input}
        cd ..
        '''


rule fetch_proteins_info:
    """
    Fetch the information for each protein of each genome in the taxid list. 
    That includes: the protein ncbi id, sequence, length and annotation, as well as in which genome is found.
    Information for the genome include genome ncbi id, name, taxid and if complete or partial.
    
    Input : str
    -----
        list of taxid in column, no header, from the rule plit_taxid_file
        
    Output : str
    ------
        table of the information collected on the proteins, without header.
        format: protein id | protein name | genome name | genome status | genome id | taxid | length | sequence
    """
    input:
        'taxid_files/{splitter}.txt'
    output:
        'taxid_files/prot_info_taxid_{splitter}.csv'
    run:
        from Bio import Entrez
        from Bio import SeqIO
        from urllib.error import HTTPError
        from http.client import IncompleteRead
        import pandas as pd

        Entrez.tool = 'draw presence/abscence v2'

        # Opening taxid list
        taxid_table = pd.read_csv(str(input), header=None, names=['taxid'], dtype={'taxid': str})

        # Creating the result table of information
        result_taxid_table = pd.DataFrame(columns=['protein_id',
                                                'protein_name',
                                                'genome_name',
                                                'genome_status',
                                                'genome_id',
                                                'taxid',
                                                'length',
                                                'sequence'])

        ### FUNCTIONS ###

        def entrez_esearch(db, term):
            """
            Use the esearch function of Entrez, but catch usual errors (Runtime and HTTP) to re-itterate the search

            :param db: str, database to search
            :param term: str, what term to search

            :return: dict, result of esearch on the term search in the database
            """
            try:
                esearch_to_return = Entrez.read(Entrez.esearch(db=db,term=term))

            except RuntimeError:
                esearch_to_return = entrez_esearch(db, term)

            except HTTPError:
                esearch_to_return = entrez_esearch(db,term)

            return esearch_to_return


        def entrez_efetch(db, id, rettype='gb', retmode='text', seqio_type='genbank'):
            """
            Use the efetch function of Entrez, but catch usual errors (Runtime, HTTP and incomplete file) to
            re-itterate the fetch

            :param db: str, on what database to fetch
            :param id: str or int, what id to fetch
            :param rettype: str, return type of efetch, default is genbank
            :param retmode: str, return mode of efetch, default is text
            :param seqio_type: str, tell the type of fetch made for SeqIO to read, default is genbank

            :return: dict, result of efetch
            """
            try:
                efetch_to_return = SeqIO.read(Entrez.efetch(db=db, id=id,
                    rettype=rettype, retmode=retmode), seqio_type)

            except RuntimeError:
                efetch_to_return = entrez_efetch(db, id, rettype=rettype, retmode=retmode, seqio_type=seqio_type)

            except HTTPError:
                efetch_to_return = entrez_efetch(db, id, rettype=rettype, retmode=retmode, seqio_type=seqio_type)

            except IncompleteRead:
                efetch_to_return = entrez_efetch(db,id,rettype=rettype,retmode=retmode,seqio_type=seqio_type)

            return efetch_to_return


        ### MAIN ###

        for tx_id in taxid_table['taxid'].to_list():
            genome_search = entrez_esearch(db='nucleotide', term=f'txid{tx_id}[Orgn]')

            for id in genome_search['IdList']:
                genome_fetch = entrez_efetch(db='nucleotide', id=id)

                for feature in genome_fetch.features:
                    if feature.type == 'CDS':
                        if 'products' in feature.qualifiers:
                            prot_name = feature.qualifiers['product'][0]

                        elif 'locus_tag' in feature.qualifiers:
                            prot_name = feature.qualifiers['locus_tag'][0]

                        else:
                            prot_name = ''

                        if 'protein_id' in feature.qualifiers and 'translation' in feature.qualifiers:
                            # Creating the new line of table
                            this_protein = pd.Series({'protein_id': feature.qualifiers['protein_id'][0],
                                                      'protein_name': prot_name,
                                                      'genome_name': genome_fetch.description.split(',')[0],
                                                      'genome_status': genome_fetch.description.split(',')[-1],
                                                      'genome_id': genome_fetch.id,
                                                      'taxid': tx_id,
                                                      'length': len(feature.qualifiers['translation'][0]),
                                                      'sequence': feature.qualifiers['translation'][0]})
                            result_taxid_table = result_taxid_table.append(this_protein, ignore_index=True)

        # Writing the table
        result_taxid_table.to_csv(str(output), sep='\t', index=False, header=False)


rule cat_proteins_info:
    """
    Concatenate the different table of protein info created in the rule fetch_proteins_info
    Then remove all file created in the rules split_taxid_file and fetch_proteins_info
    
    Input : list of str
    -----
        list of tables of the information collected on the proteins, without header.
        format: protein id | protein name | genome name | genome status | genome id | taxid | length | sequence
        
    Output : str
    ------
        final table of protein information, without header.
        format: protein id | protein name | genome name | genome status | genome id | taxid | length | sequence
    """
    input:
        expand('taxid_files/prot_info_taxid_{splitter}.csv', splitter=splitter)
    output:
        f'{new_dir}/processing_files/list_protein_{project_name}_id_table.csv'
    shell:
        '''
        for prot_info_taxid_file in {input}
        do
            cat $prot_info_taxid_file  >> {output}
        done
        
        '''# rm -r taxid_files

rule make_fasta:
    """
    Create a fasta file from the psiblast results and the result of the protein information in the rule cat_proteins_info
    
    Inputs
    ------
    protein_table : str
        final table of protein information from the rule cat_proteins_info, without header.
        format: protein id | protein name | genome name | genome status | genome id | taxid | length | sequence
    list_all_prot : str
        list of all protein identifications gathered in the psiBLAST in column
        
    Outputs 
    -------
    fasta : str
        multifasta file of all the unique protein ids.
    reduced_protein_table : str
        final table of protein information with removed duplicates, without header.
        format: protein id | protein name | genome name | genome status | genome id | taxid | length | sequence
    """
    input:
        protein_table = f'{new_dir}/processing_files/list_protein_{project_name}_id_table.csv',
        list_protein = f'{new_dir}/processing_files/list_all_protein_{project_name}_eval{e_val}.csv'
    output:
        fasta = f'{new_dir}/results/all_protein_{project_name}_eval{e_val}.fasta',
        reduced_protein_table = f'{new_dir}/results/list_protein_{project_name}_id_table.csv'
    run:
        import pandas as pd

        # Opening the protein information table
        all_protein_list = pd.read_csv(str(input.protein_table), sep='\t', header=None,
            names=['protein_id',
                   'protein_name',
                   'genome_name',
                   'genome_status',
                   'genome_id',
                   'taxid',
                   'length',
                   'sequence'])

        # Removing duplicates and updating the table file
        all_protein_list.drop_duplicates()
        all_protein_list.to_csv(str(input.protein_table), sep='\t', header=False, index=False)
        all_protein_list['protein_id'] = all_protein_list.protein_id.apply(lambda x: x.split('.')[0])
        print(all_protein_list.head())

        # Opening the list of protein of interests
        protein_of_interest = pd.read_csv(str(input.list_protein), sep='\t', header=None, names=['protein_id'])

        # Filtering protein table and saving
        protein_list = pd.merge(protein_of_interest, all_protein_list, how='left', on='protein_id')
        print(protein_list.head())
        protein_list.to_csv(str(output.reduced_protein_table), sep='\t', header=False, index=False)

        # Making the fasta file
        protein_list.drop(columns=['protein_name', 'genome_name','genome_status', 'genome_id', 'taxid', 'length'],
                        inplace=True)
        protein_list['protein_id'] = protein_list.protein_id.apply(lambda x: '>{the_id}'.format(the_id=x.split('.')[0]))
        print(protein_list.head())
        protein_list.to_csv(str(output.fasta), sep='\n', header=False, index=False)


rule blast:
    """
    blast all versus all of the fasta of all protein generated in the rule make_fasta
    
    Inputs
    ------
    prot_sequence : str
        multifasta file of all the unique protein ids from the rule make_fasta
    seed_fasta : str
        multifasta file of all the seeds from the rule fetch_fasta_from_seed
        
    Outputs
    -------
    blast_out : str
        output format of blast
        format: query id | subject id | percentage of identity | length of match  | mismatch | gapopen |
                query start position | query end position | subject start position | subject end position |
                e-value | bitscore
    fasta_for_blast : str
        concatenation of the 2 input multifasta files
        
    Params
    ------
    blast_version : str
        version of blast
    """
    input:
         prot_sequence = f'{new_dir}/results/all_protein_{project_name}_eval{e_val}.fasta',
         seed_fasta = f'seeds_{project_name}.fasta'
    output:
        blast_out = f'{new_dir}/processing_files/blastp_{project_name}_psiblast_evalue{e_val}.out',
        fasta_for_blast = f'{new_dir}/processing_files/all_protein_with_seeds_{project_name}_eval{e_val}.fasta'
    params:
        blast_version = blast_version
    threads:
        5
    shell:
         """
         module load ncbi_blast/{params.blast_version}
         cat {input.prot_sequence} {input.seed_fasta} > {output.fasta_for_blast}
         makeblastdb -dbtype prot -in {output.fasta_for_blast}
         blastp -query {output.fasta_for_blast} -db {output.fasta_for_blast} -evalue 0.01\
            -outfmt 6 -out {output.blast_out} -num_threads 5 -num_alignments 25000
         """

rule prepare_for_silix:
    """
    Filter the blast results from the rule blast with the threshold specified for each seed in the seed file.
    Filters include the identity score, coverage and e-value.
    Create one new filtered blast result for each seed.
    
    Inputs
    ------
    fasta : str
        multifasta of proteins with seed from the rule blast
    blast_out : str
        blast output from the rule blast
        format: query id | subject id | percentage of identity | length of match  | mismatch | gapopen |
                query start position | query end position | subject start position | subject end position |
                e-value | bitscore
        
    Output : list of str
    ------
        list of blast output filtered for each seed.
        format: query id | subject id | percentage of identity | length of match  | mismatch | gapopen |
                query start position | query end position | subject start position | subject end position |
                e-value | bitscore
    
    Params
    ------
    new_dir : str
        work directory
    project_name : str
        project name determined by the user
    """
    input:
        fasta = f'{new_dir}/processing_files/all_protein_with_seeds_{project_name}_eval{e_val}.fasta',
        blast_out = f'{new_dir}/processing_files/blastp_{project_name}_psiblast_evalue{e_val}.out',
    output:
        expand('{new_dir}/processing_files/blast_out_per_gene/filtered_blast_{project_name}_{gene_constrains}.out',
            new_dir=new_dir, project_name=project_name, gene_constrains=gene_constrains)
    params:
        new_dir = f'{new_dir}/processing_files',
        project_name = project_name
    run:
        from Bio import SeqIO
        import pandas as pd
        import numpy as np

        # Preparing seeds
        seed_list = seed_table.protein_id.to_list()
        seed_table.set_index('protein_id', inplace=True)

        # Opening fasta
        fasta = {}
        for seq_record in SeqIO.parse(str(input.fasta), 'fasta'):
            fasta[seq_record.id.split('.')[0]] = len(seq_record.seq)

        # Opening blast_out and preparation
        blast_names = ['qseqid', 'sseqid', 'pident', 'length', 'mismatch', 'gapopen', 'qstart', 'qend',
                       'sstart', 'send', 'evalue', 'bitscore']
        blast_out = pd.read_csv(str(input.blast_out), sep='\t', header=None, names=blast_names)
        blast_out['qseqid'] = blast_out.qseqid.apply(lambda x: x.split('.')[0])
        blast_out['sseqid'] = blast_out.sseqid.apply(lambda x: x.split('.')[0])
        blast_out.drop_duplicates(inplace=True)
        blast_out['cov'] = blast_out.apply(lambda x: x.length/fasta[x.qseqid], axis=1)

        # Make dir to collect blast_out info
        if not os.path.exists(f'{params.new_dir}/blast_out_per_gene'):
            os.mkdir(f'{params.new_dir}/blast_out_per_gene')
        
        # start filtering blast out on e-value, coverage and percent identity
        for seed in seed_list:
            filtered_blast_out = blast_out.copy()
            filtered_blast_out['evalue'] = filtered_blast_out.evalue.apply(lambda x: \
                x if x <= seed_table.at[seed,'evalue'] else np.nan)
            filtered_blast_out['pident'] = filtered_blast_out.pident.apply(lambda x: \
                x if x >= seed_table.at[seed,'pident'] else np.nan)
            filtered_blast_out['cov'] = filtered_blast_out['cov'].apply(lambda x: \
                x if x >= seed_table.at[seed,'cov'] else np.nan)
            filtered_blast_out.dropna(inplace=True)

            # write new blast_out
            filtered_blast_out.drop(columns='cov', inplace=True)
            print(seed, filtered_blast_out)
            seed_constrains = '{seed}_evalue{eval}_cov{cov}_pid{pid}'.format(seed=seed_table.at[seed, "name"],
                                                                            eval=seed_table.at[seed, "evalue"],
                                                                            cov=seed_table.at[seed, "cov"],
                                                                            pid=seed_table.at[seed, "pident"])
            filtered_blast_out.to_csv(
                f'{params.new_dir}/blast_out_per_gene/filtered_blast_{params.project_name}_{seed_constrains}.out',
                sep='\t', index=False, header=False)

rule silix:
    """
    Uses Silix to create a network of protein and give a file of the protein segregated in groups.
    If the blast output file is empty, just create an empty file
    
    Inputs
    ------
    blast_out : str
        blast output filtered for a specific seed from the rule prepare_for_silix.
        format: query id | subject id | percentage of identity | length of match  | mismatch | gapopen |
                query start position | query end position | subject start position | subject end position |
                e-value | bitscore
    fasta : str
        multifasta of proteins with seed from the rule blast
        
    Output : str
    ------
        fnodes file, table of protein id and family number, without headers.
        format: family | protein id
        
    Params
    ------
    silix_version : str
        version of silix to use
    """
    input:
        blast_out = '{new_dir}/processing_files/blast_out_per_gene/filtered_blast_{project_name}_{gene_constrains}.out',
        fasta = f'{new_dir}/processing_files/all_protein_with_seeds_{project_name}_eval{e_val}.fasta'
    output:
        '{new_dir}/processing_files/blast_out_per_gene/filtered_blast_{project_name}_{gene_constrains}.fnodes'
    wildcard_constraints:
        new_dir = new_dir,
        project_name = project_name
    params:
        silix_version = silix_version
    shell:
        """
        module load silix/{params.silix_version}
        
        if [ -s {input.blast_out} ];then   
            sh -c 'silix {input.fasta} {input.blast_out} -f {wildcards.gene_constrains} -i 0.05 -r 0.05 > {output}'
        else
            touch {output}
        fi
        """

rule find_family:
    """
    Find the group of each seed in each individual seed and record it
    
    Input
    -----
    fnodes : str
        fnodes file, table of protein id and family number, without headers from the rule silix.
        format: family | protein id
        
    Output : str
    ------
        updated fnodes with only the family of the seed.
        format: family | protein id | seed
    """
    input:
        fnodes = '{new_dir}/processing_files/blast_out_per_gene/filtered_blast_{project_name}_{gene_constrains}.fnodes'
    output:
        '{new_dir}/processing_files/blast_out_per_gene/filtered_blast_{project_name}_{gene_constrains}_flushed.fnodes'
    wildcard_constraints:
        new_dir = new_dir,
        project_name = project_name,
    run:
        # Open fnodes
        fnodes = pd.read_table(str(input.fnodes),names=['family', 'protein_id'])

        # Detection of the seed
        for gene in seed_table.name.to_list():
            if gene in wildcards.gene_constrains:
                seed = gene

        # Detection families
        seed_fnodes = pd.merge(seed_table,
            fnodes,
            how='left',
            on='protein_id'
        ).drop_duplicates()
        seed_fnodes.set_index('name', inplace=True)
        gene_family = seed_fnodes.at[seed, 'family']

        # writing file with only family
        fnodes = fnodes[fnodes.family == gene_family]
        fnodes['seed'] = fnodes.family.apply(lambda x: seed)
        fnodes.to_csv(str(output), sep='\t', header=False, index=False)

rule make_table:
    """
    Check the presence of protein similar to the seed in each taxid and create a table of presence abscence
    This table is then plotted in a colored table.
    
    Inputs
    ------
    protein_table : str
        final table of protein information from the rule cat_proteins_info, without header.
        format: protein id | protein name | genome name | genome status | genome id | taxid | length | sequence
    fnode : str
        concatenated fnodes with each seed family from 
        format: family | protein id | seed
            
    Outputs
    -------
    final_table : str
        presence/abscence table, with header. Each line is a genome, each column is a seed.
        format: genome id | genome name | seed 1 | seed 2 .. seed x
    pdf : list of str
        plots in pdf of the final table centered on one seed
    png : list of str
        plots in png of the final table centered on one seed
    """
    input:
        protein_table = f'{new_dir}/results/list_protein_{project_name}_id_table.csv',
        fnodes = expand(
            '{new_dir}/processing_files/blast_out_per_gene/filtered_blast_{project_name}_{gene_constrains}_flushed.fnodes',
            new_dir=new_dir, project_name=project_name, gene_constrains=gene_constrains)
    output:
        final_table = f'{new_dir}/results/patab_{project_name}_psiblast_evalue{e_val}.csv',
        pdf = expand('{new_dir}/results/plots/gene_table_{project_name}_{gene}.pdf',
            new_dir=new_dir, project_name=project_name, gene=gene),
        png = expand('{new_dir}/results/plots/gene_table_{project_name}_{gene}.png',
                new_dir=new_dir, project_name=project_name, gene=gene)
    run:
        import pandas as pd
        import numpy as np
        import matplotlib.pyplot as plt
        from Bio import SeqIO

        def plot(patab, seed_table, gene):
            """
            plot in pdf and png the table of presence/abscence, each column would be a seed
            and colored accordingly to the input file.

            :param patab: pandas DataFrame object
                format: genome id | genome name | seed 1 | seed 2 .. seed x
            :param seed_table: pandas DataFrame object
                format: name | protein id | e-value | percentage of identity | coverage | color
            :param gene: str, seed analyzed

            :return: nothing
            """
            font = {'family': 'DejaVu Sans', 'weight': 'light', 'size': 10, }
            plt.rc('font',**font)
            plt.rcParams['text.color'] = 'black'
            plt.rcParams['svg.fonttype'] = 'none'  # Editable SVG text
            patab = patab.fillna('None').set_index('genome_id')[::-1]
            tab_to_draw = patab.reset_index().drop(labels='genome_name',axis=1) \
                .melt(id_vars='genome_id').rename(columns={'variable': 'gene', 'value': 'PA'})
            dict_color = seed_table.set_index("name").color.to_dict()

            print(tab_to_draw)
            tab_to_draw['color'] = tab_to_draw.apply(lambda x: dict_color[x.gene] if x.PA != 'None' else 'white', axis=1)
            tab_to_draw['number'] = tab_to_draw.PA.apply(lambda x: len(x.split(',')) if x != 'None' else 0)
            tab_to_draw['x_pos'] = tab_to_draw.gene.apply(lambda x: patab.columns.tolist().index(x) - 1)
            tab_to_draw['y_pos'] = tab_to_draw.genome_id.apply(lambda x: patab.index.tolist().index(x))
            tab_to_draw.to_csv(f'test_tab_to_draw_{gene}.csv')

            fig, ax = plt.subplots(1,1,figsize=((patab.shape[1]) / 3,
                                                patab.shape[0] / 3),
                gridspec_kw={'width_ratios': [patab.shape[1]]})

            label_format = {'color': 'black', 'fontweight': 'bold',
                            'fontsize': 12}

            for _, row in tab_to_draw.iterrows():
                ax.plot(row.x_pos,row.y_pos,linestyle="None",marker="s",
                    markersize=15,mfc=row.color,mec='black',markeredgewidth=1)

                if row.number > 1:
                    ax.text(row.x_pos,row.y_pos,str(row.number),fontsize=11,color='white',ha='center',va='center',
                        fontweight='heavy')

            plt.yticks(range(patab.shape[0]),patab.genome_name.tolist(),**label_format)
            plt.xticks(range(patab.shape[1] - 1),tab_to_draw.gene.unique().tolist(),**label_format)

            ax.tick_params(axis='both',which='both',length=0)  # No tick markers
            ax.set_ylabel('')  # No ylabel
            ax.xaxis.tick_top()  # xticklabels on top
            ax.xaxis.set_label_position('top')
            plt.setp(ax.xaxis.get_majorticklabels(),rotation=90,ha='center')  # Rotate x labels

            for pos in ['top', 'bottom', 'left', 'right']:
                ax.spines[pos].set_visible(False)  # Remove border

            plt.xlim(-0.5,patab.shape[1] - 0.5)
            plt.ylim(-0.5,patab.shape[0] - 0.5)

            if not os.path.exists(f'{new_dir}/results/plots'):
                os.mkdir(f'{new_dir}/results/plots')

            name = f"{new_dir}/results/plots/gene_table_{project_name}_{gene}"

            plt.savefig(name + '.png', bbox_inches="tight",dpi=300)
            plt.savefig(name + '.pdf', bbox_inches="tight",dpi=300)

            return


        def is_my_seed_here(my_genome_id, my_seed, fam_table):
            filter_fam_table = fam_table[fam_table['seed'] == my_seed]
            value_to_return = np.nan

            if filter_fam_table.shape[0] > 0:
                filter_fam_table = filter_fam_table[filter_fam_table['genome_id'] == my_genome_id]
                if filter_fam_table.protein_id.shape[0] > 0:
                    value_to_return = ','.join(filter_fam_table.protein_id.tolist())

            return value_to_return


        # Seed preparing
        seed_list = seed_table.name.to_list()

        # list of all proteins
        all_proteins = pd.read_csv(str(input.protein_table), sep='\t',
            header = None,
            names=['protein_id',
                   'protein_name',
                   'genome_name',
                   'genome_status',
                   'genome_id',
                   'taxid',
                   'length',
                   'sequence'])
        all_proteins['protein_id'] = all_proteins.protein_id.apply(lambda x: x.split('.')[0])

        # fnodes opening
        fnodes_files = [ pd.read_table(fnodes_file, names=['family', 'protein_id', 'seed'])
                        for fnodes_file in input.fnodes ]
        fam_id_table = pd.merge(pd.concat(fnodes_files), all_proteins, how='left', on='protein_id')

        # create final table
        patab = pd.DataFrame(columns=["genome_id", 'genome_name'] + seed_list)
        patab['genome_id'] = all_proteins.genome_id
        patab['genome_name'] = all_proteins.genome_name
        patab.drop_duplicates(inplace=True)
        sorted_patab = patab.copy()

        # fill pa_tab
        for seed in seed_list:
            patab[seed] = patab.genome_id.apply(is_my_seed_here, my_seed=seed, fam_table=fam_id_table)
            sorted_patab[seed] = patab[seed].apply(lambda x: 0 if x==np.nan else 1)
        print(patab)
        sorted_patab.sort_values(by=['genome_name'], inplace=True)
        sorted_patab.sort_values(by=patab.columns.tolist()[2:], ascending=False, inplace=True)
        patab = patab.reindex(sorted_patab.index.to_list())
        print(patab)
        patab.dropna(subset=seed_list, how='all', inplace=True)
        print(patab)

        # plot the table per gene
        for column in seed_list:
            patab_to_draw = patab.dropna(subset=[column])

            if patab_to_draw.shape[0] > 0:
                plot(patab_to_draw, seed_table, column)

            else:
                name = f"{new_dir}/results/plots/gene_table_{project_name}_{column}"

                with open(name+'.pdf', 'w'):
                    pass

                with open(name+'.png', 'w'):
                    pass

        # print the table
        patab.to_csv(str(output.final_table), sep='\t', index=False)
