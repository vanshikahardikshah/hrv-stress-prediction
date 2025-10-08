#!/usr/bin/env bash
# usage: ./proj_3.sh
INPUT_TSV="/mnt/scratch/CS131_jelenag/projects/team05_sec3/heart_rate_non_linear_features_train.csv"
EDGES_TSV="/mnt/scratch/CS131_jelenag/projects/team05_sec3/edges.tsv"
OUT=out
mkdir -p $OUT


#Step 1 - Define relationships (edges)
#edges.tsv created using pandas

#Step 2 - Filter significant clusters
echo "Script is running ... please wait" 
awk -F'\t' 'NR>1 {print $1}' $EDGES_TSV | sort | uniq -c | sort -nr > $OUT/entity_counts.tsv

awk 'NR==FNR && $1>=10 {keep[$2]; next} (FNR==1) || ($1 in keep)' $OUT/entity_counts.tsv $EDGES_TSV > $OUT/edges_thresholded.tsv

#Step 3 - Histogram of cluster sizes

awk -F'\t' '{c[$1]++} END{for (k in c) print c[k] "\t" k}' $OUT/edges_thresholded.tsv \
  | sort -nr > $OUT/cluster_sizes.tsv
cut -f1 $OUT/cluster_sizes.tsv | sort -n | uniq -c \
  | awk '{print $2 "\t" $1}' > $OUT/cluster_histogram.tsv
#Step 4 - Top-30 tokens inside clusters

cut -f2 $OUT/edges_thresholded.tsv \
 | tr '[:upper:]' '[:lower:]' \
 | tr -cs 'a-z0-9_+' '\n' \
 | grep -v '^$' \
 | sort | uniq -c | sort -nr \
 | awk '{print $1 "\t" $2}' | head -30 > $OUT/top30_clusters.txt

cut -f2 $EDGES_TSV \
 | tr '[:upper:]' '[:lower:]' \
 | tr -cs 'a-z0-9_+' '\n' \
 | grep -v '^$' \
 | sort | uniq -c | sort -nr \
 | awk '{print $1 "\t" $2}' | head -30 > $OUT/top30_overall.txt

awk '{print $2}' $OUT/top30_overall.txt | sort > $OUT/overall.sorted
awk '{print $2}' $OUT/top30_clusters.txt | sort > $OUT/clusters.sorted
comm -3 $OUT/overall.sorted $OUT/clusters.sorted > $OUT/diff_top30.txt


#Step 5 - Network Visualization

head -1 $EDGES_TSV | sed -E 's/Entity_A/Target/g; s/Entity_B/Source/g' > $OUT/clustertemp.tsv
grep "SD1_low" $EDGES_TSV | head -30 >> $OUT/clustertemp.tsv
grep "SD1_midlow" $EDGES_TSV | head -30 >> $OUT/clustertemp.tsv
grep "SD1_midhigh" $EDGES_TSV | head -30 >> $OUT/clustertemp.tsv
grep "SD1_high" $EDGES_TSV | head -30 >> $OUT/clustertemp.tsv

# Creating this temporary file with the cluster sets allowed me to put it into the Gephi tool and make the visualization by exporting it from the tool itself. 

#Step 6 - Summary Statistics ab$OUT clusters; used cut and paste to create the file, with temporary files that eventually were used in datamash

sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' $EDGES_TSV  > $OUT/tempedges.tsv

cut -d' ' -f1 $OUT/tempedges.tsv > $OUT/col1temp.tsv

cut -d',' -f4 $INPUT_TSV > $OUT/col2.tsv
paste $OUT/col1temp.tsv $OUT/col2.tsv > $OUT/2colfile.tsv
source ~/.bashrc
datamash --header-in -g 1 count 2 mean 2 median 2 < $OUT/2colfile.tsv > $OUT/cluster_outcomes.tsv

echo "Script is done running"
echo "If datamash command did not work, please reload bashrc before running the script. Ignore if no error was displayed."

