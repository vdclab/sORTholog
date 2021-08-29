import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle  
import sys

# It seems there is a bug if another backend is used
import matplotlib
matplotlib.use('Agg')

# Put error and out into the log file
sys.stderr = sys.stdout = open(snakemake.log[0], "w")

# Plot parameters
font = {'family': 'DejaVu Sans', 'weight': 'light'}
plt.rc('font',**font)
plt.rcParams['text.color'] = 'black'
plt.rcParams['svg.fonttype'] = 'none'  # Editable SVG text

# Name in PAtab genome_id, seed, PA, color, genome_name

# figsize = (width, height) plosBio ((7.5, 8.75))
fig, ax = plt.subplots(1,1)

label_format = {'fontweight': 'bold'}

patab = pd.read_table(snakemake.input.final_table, na_filter=False)
patab = .replace('.+', '1', regex=True).replace('', '0') 

# Dict position genomes and gene
num_genome = patab.shape[0]
list_genome = patab.index.tolist() 
dict_pos_genome = {list_genome[index]:num_genome-index-1 for index in range(num_genome)}

# here fist genome on top
num_seed = patab.shape[1]
list_seed = patab.columns.tolist()
dict_pos_seed = {list_seed[index]:index for index in range(num_seed)}


# Melt the table
patab = patab.reset_index().rename(columns={'index':'genome_id'})
patab = patab.melt(id_vars='genome_id', var_name='seed', value_name='PA')

# To update the size of the square
size_rec = 0.8

for _, row in patab.iterrows():
    ax.add_artist(Rectangle(xy=(dict_pos_seed[row.seed]-size_rec/2, 
                                dict_pos_genome[row.genome_id]-size_rec/2),
                            facecolor = snakemake.params.color,
                            width=size_rec, height=size_rec,
                            edgecolor = 'black',
                            lw=1))

plt.yticks(range(num_genome),list_genome[::-1],**label_format)
plt.xticks(range(num_seed),list_seed,**label_format)

ax.tick_params(axis='both',which='both',length=0)  # No tick markers
ax.set_ylabel('')  # No ylabel
ax.xaxis.tick_top()  # xticklabels on top
ax.xaxis.set_label_position('top')
plt.setp(ax.xaxis.get_majorticklabels(),rotation=90,ha='center')  # Rotate x labels

for pos in ['top', 'bottom', 'left', 'right']:
    ax.spines[pos].set_visible(False)  # Remove border

plt.xlim(-0.5, num_seed - 0.5)
plt.ylim(-0.5, num_genome - 0.5)

for plot_name in snakemake.output :
    plt.savefig(plot_name, bbox_inches="tight", dpi=300)