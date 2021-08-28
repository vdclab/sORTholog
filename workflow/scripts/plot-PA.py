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

patab = pd.read_table(snakemake.input.final_table)

# Dict position genomes and gene
list_genome = patab.genome_id.unique().tolist() 

### Amelioration purposes : The genome name could be followed by the id in parenthesis
### or we could ask the user for id or name in the figure

# As some genome name could be the same I need to create a dict to convert the name
genomeId_2_genomeName = patab.set_index('genome_id').genome_name.to_dict()
list_genome_name = [f'{genomeId_2_genomeName[genome]} ({genome})' 
                       for genome in list_genome] 

num_genome = len(list_genome)
# here fist genome on top
dict_pos_genome = {list_genome[index]:num_genome-index-1 for index in range(num_genome)}

list_seed = patab.seed.unique().tolist()
num_seed = len(list_seed)
dict_pos_seed = {list_seed[index]:index for index in range(num_seed)}

size_rec = 0.8

for _, row in patab.iterrows():
    ax.add_artist(Rectangle(xy=(dict_pos_seed[row.seed]-size_rec/2, 
                                dict_pos_genome[row.genome_id]-size_rec/2),
                            facecolor = row.color,
                            width=size_rec, height=size_rec,
                            edgecolor = 'black',
                            lw=1))

    if row.PA > 1:
       ax.text(x = dict_pos_seed[row.seed],
               y = dict_pos_genome[row.genome_id],
               s = str(row.PA),
               color='white',ha='center',va='center',
               fontweight='heavy')

plt.yticks(range(num_genome),list_genome_name[::-1],**label_format)
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
