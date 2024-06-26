#!/bin/bash
# Download and process TF ChIP Seq peak data

# Function to check if a file exists
file_exists() {
    [[ -f "$1" ]]
}

# Function to download file
download_file() {
    local url=$1
    local filename=$(basename "$url")

    if file_exists "$filename"; then
        echo "File $filename already exists. Skipping download."
    else
        wget "$url" || { echo "Error downloading $url"; exit 1; }
    fi
}

# Function to process factorbookMotifCanonical.txt and add canonical column to bed file
add_canonical_term() {
    local canonical_file="$1"
    local bed_file="$2"
    local processed_factorbook_file="processed_factorbookMotifCanonical.txt"

    # Process factorbookMotifCanonical.txt file
    zcat "$canonical_file" | awk 'BEGIN {OFS="\t"} {if ($2 == "") $2 = $1; print $1, $2}' > "$processed_factorbook_file" &&
    
    # Add canonical column to bed file
    awk 'BEGIN {OFS="\t"} NR==FNR {canonical[$1]=$2; next} {if ($8 in canonical) print $0, canonical[$8]; else print $0, $8}' "$processed_factorbook_file" "$bed_file" > tmp_with_canonical_column.bed

    mv "tmp_with_canonical_column.bed" "$bed_file"
}

# Download experiment table 
download_file "http://hgdownload.soe.ucsc.edu/goldenPath/hg19/encodeDCC/wgEncodeRegTfbsClustered/wgEncodeRegTfbsClusteredInputsV3.tab.gz"

# Download TF cluster BED
download_file "http://hgdownload.soe.ucsc.edu/goldenPath/hg19/encodeDCC/wgEncodeRegTfbsClustered/wgEncodeRegTfbsClusteredV3.bed.gz"

# Download factorbookMotifCanonical.txt.gz file
download_file "http://hgdownload.soe.ucsc.edu/goldenPath/hg19/database/factorbookMotifCanonical.txt.gz"


# Define an array of folder names
folders=("tmp" "ByCellType" "peaks")

# Loop through each folder name
for folder in "${folders[@]}"; do
    # Check if the directory exists
    if [ ! -d "$folder" ]; then
        # Create the directory if it doesn't exist  
        mkdir "$folder"
    fi
done

# Numbering the experiments
zcat wgEncodeRegTfbsClusteredInputsV3.tab.gz | awk '{print $0 "\t" NR-1}' > numbered_wgEncodeRegTfbsClusteredInputsV3.tab

# Normalize comma-separated rowss in last 2 columns
zcat wgEncodeRegTfbsClusteredV3.bed.gz | awk 'BEGIN {OFS="\t"} {$1=$1;t=$0;} {while (index($0,",")){gsub(/,[[:alnum:],]*/,""); print; $0=t; gsub(OFS "[[:alnum:]]*,",OFS); t=$0;} print t}' > normalized.wgEncodeRegTfbsClusteredV3.bed 

# Map Experiment_number (column $7) in tmp.wgEncodeRegTfbsClusteredV3.bed to numbered_wgEncodeRegTfbsClusteredInputsV3.tab
awk -F"\t" 'NR==FNR{a[$8]=$0; next} ($7 in a){print a[$7]"\t"$1"\t"$2"\t"$3"\t"$7"\t"$8}' numbered_wgEncodeRegTfbsClusteredInputsV3.tab normalized.wgEncodeRegTfbsClusteredV3.bed | awk '{-OFS"\t"}{print $9, $10, $11, $12, $13, $1, $2, $3, $4, $5, $6, $7, $8}' > tmp.bed

# Add canonical factor column to FILER.wgEncodeRegTfbsClusteredV3.bed
add_canonical_term "factorbookMotifCanonical.txt.gz" "tmp.bed"

# Column re-arrangement
#awk 'BEGIN {OFS="\t"} {print $1,$2,$3,$8,$5,$6,$7,$9,$10,$11,$12,$4}' tmp.bed > FILER.wgEncodeRegTfbsClusteredV3.bed
awk 'BEGIN {OFS="\t"} {print $1,$2,$3,$8,$4,$5,$10,$14}' tmp.bed > FILER.wgEncodeRegTfbsClusteredV3.bed

# tmp files
mv numbered_wgEncodeRegTfbsClusteredInputsV3.tab normalized.wgEncodeRegTfbsClusteredV3.bed tmp.bed tmp/
mv processed_factorbookMotifCanonical.txt tmp/

# Split by cell types
awk '{file = "ByCellType/" $7 ".FILER.wgEncodeRegTfbsClusteredV3.bed"; print >> file; close(file)}' FILER.wgEncodeRegTfbsClusteredV3.bed

mv FILER.wgEncodeRegTfbsClusteredV3.bed peaks/
mv ByCellType/ peaks/

# Add header
for file in peaks/ByCellType/*.FILER.wgEncodeRegTfbsClusteredV3.bed; do
    sed -i '1i #chrom\tchromStart\tchromEnd\tTF\texpNum\texpScore\tcell-type\tcanonical-TF-term' "$file"
done

# Sorting and compression
for file in "peaks/ByCellType"/*.FILER.wgEncodeRegTfbsClusteredV3.bed; do
    if [ -f "$file" ]; then
        # Extract the filename without the directory path
        filename=$(basename "$file")

        # Perform sorting and compression
        if LC_ALL=C sort -k1,1 -k2,2n -k3,3n "$file" | bgzip "$file"; then
            echo "File '$filename' sorted and compressed successfully."
        else
            echo "Error: Failed to sort and compress '$filename'."
        fi
    fi
done
