#!/bin/bash
# Usage: bash run_pa4.sh <input_file>
set -uo pipefail
INPUT_FILE=${1:-"/mnt/scratch/CS131_jelenag/projects/team05_sec3/heart_rate_non_linear_features_train.csv"}
if [ -s $INPUT_FILE ] ;
then 
	echo "File is accepted!"
else 
	echo "The file is empty and it is not present, exiting the script"; exit 1;
fi
OUT=output
mkdir -p $OUT
chmod -R g+rX "$INPUT_FILE"
#Task 1
echo "Starting Task 1"
echo "Our data is already normalized, it has all white space removed, numbers are less than 1000's and there is no punctuation"
echo "So I have the first one just how we WOULD take away the white space" 

#white space :
sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]*,[[:space:]]*/,/g; s/[[:space:]]+/ /g' $INPUT_FILE > $OUT/normalized_Sample.csv

#However, our data is already clean we can double check with this

#this will check for whitespace around delimiters and should return 0
echo "Checking all white space around delimiters are removed : should return 0"
grep -E '[[:space:]],[[:space:]]' $INPUT_FILE | wc -l || true

#this will check for null values and should return 0
echo "Checking for no null/na values: should return 0"
grep -iE '(NA|null|N/A|#N/A)' $INPUT_FILE | wc -l || true

#this will check for empty fields and should return 0
echo "Checking for empty fields: should return 0" || true

grep ',,' $INPUT_FILE | wc -l

#this will check for leading/trailing white space
echo "Checking for leading/trailing white spaces: should return 0"

grep -E '(^[[:space:]]|[[:space:]]$)' $INPUT_FILE | wc -l || true

#this will check that all the rows have 7 sections
echo "Checking all rows have 7 fields and filled: should return amount of line number and how many fields "

awk -F',' '{print NF}' $INPUT_FILE | sort | uniq -c

#Task 2
# skinny table
echo “Begin Task 2”
echo “Skinny Table found at out/skinnyTable.tsv”
awk -F',' 'BEGIN{OFS="\t"} NR==1 {print $1,$6,$7} NR>1 {print $1,$6,$7 | "sort -k1,1"}' $INPUT_FILE > $OUT/skinnyTable.tsv

echo “Frequency Table 1 based on Condition found at out/freqTableOne.tsv”
#frequency table 1 Condition

awk -F',' 'BEGIN{print "count\tcondition"} NR>1 {print $7}' $INPUT_FILE | (head -1; tail -n +2 | sort | uniq -c | sort -rn) > $OUT/freqTableOne.tsv

echo “Frequency Table 2 based on SD1 and binned in low, med and high found at out/freqTableTwo.tsv”

#frequency table 2
{ echo -e "count\tsampen_bin"; awk -F',' 'NR>1 {if($4<1.5) print "low"; else if($4<2.0) print "med"; else print "high"}' $INPUT_FILE | sort | uniq -c | sort -rn; } > $OUT/freqTableTwo.tsv

#top n list
echo “Top 20 SD1 values with condition found at out/topN.tsv”
awk -F',' 'NR>1 {print $2,$7}' $INPUT_FILE  | sort -rn | head -20 > $OUT/topN.tsv

#Task 3
mkdir -p "$OUT/logs" "$OUT/scripts"
if [[ ! -f "$OUT/scripts/filters.awk" ]]; then
  if [[ -f "scripts/filters.awk" ]]; then
    cp scripts/filters.awk "$OUT/scripts/"
  else
    echo "Error: filters.awk not found in scripts/. Please add it before running."
    exit 1
  fi
fi
INPUT="$OUT/normalized_Sample.csv"
if [[ ! -s "$INPUT" ]]; then
  echo "The cleaned file ($INPUT) is missing. Run Tasks 1 and 2 first."
  exit 1
fi
{
  head -1 "$INPUT" | tr ',' '\t'
  tail -n +2 "$INPUT" | tr ',' '\t' \
    | awk -v drop_re='^(test|dummy)$' \
          -v drop_log="$OUT/logs/rejects.tsv" \
          -v col_key=1 \
          -v col_attempts=2 \
          -v col_success=3 \
          -v col_rating=4 \
          -v col_test=6 \
          -f "$OUT/scripts/filters.awk" -
} | { read -r H; echo "$H"; sort -t$'\t' -k1,1 -k2,2; } \
  > "$OUT/filtered.tsv"

echo "Filtered data saved in: $OUT/filtered.tsv"
echo "Dropped rows listed in: $OUT/logs/rejects.tsv"

#Task 4
INPUT="$OUT/filtered.tsv"
if [[ ! -s "$INPUT" ]]; then
  echo "The filtered file ($OUT/filtered.tsv) is missing. Run Task 3 first."
  exit 1
fi
mkdir -p "$OUT/scripts"
if [[ ! -s "$OUT/scripts/ratios.awk" ]]; then
  cat > "$OUT/scripts/ratios.awk" <<'AWK'
BEGIN {
  FS = OFS = "\t"
  if (hi == "")  hi  = 0.80
  if (mid == "") mid = 0.50
  if (out_summary == "") out_summary = "output/summary_by_key.tsv"
  if (out_buckets == "") out_buckets = "output/bucket_counts.tsv"
}
function col(name){ return h[tolower(name)]+0 }

NR==1{
  for(i=1;i<=NF;i++) h[tolower($i)]=i
  keyCol      = (col_key?col_key+0:(h["uuid"]?h["uuid"]:0))
  attemptsCol = (col_attempts?col_attempts+0:(h["sd1"]?h["sd1"]:0))
  successCol  = (col_success?col_success+0:(h["sd2"]?h["sd2"]:0))
  print $0, "success_rate", "bucket"
  next
}
{
  key      = (keyCol?$(keyCol):"")
  attempts = (attemptsCol?$(attemptsCol):0)
  success  = (successCol?$(successCol):0)

  rate = (attempts+0 > 0 ? success/attempts : 0)

  bucket = "ZERO"
  if (rate >= hi+0)       bucket = "HI"
  else if (rate >= mid+0) bucket = "MID"
  else if (rate > 0)      bucket = "LO"

  # row-wise output
  printf "%s\t%.4f\t%s\n", $0, rate, bucket

  if (key != "") {
    n[key]++
    sum_attempts[key] += attempts
    sum_rate[key]     += rate
    if (!(key in min_rate) || rate < min_rate[key]) min_rate[key] = rate
    if (!(key in max_rate) || rate > max_rate[key]) max_rate[key] = rate
  }

  bucket_ct[bucket]++
}
END{
  print "key\trows\tavg_attempts\tavg_rate\tmin_rate\tmax_rate" > out_summary
  for (k in n) {
    printf "%s\t%d\t%.3f\t%.4f\t%.4f\t%.4f\n",
      k, n[k],
      (n[k]?sum_attempts[k]/n[k]:0),
      (n[k]?sum_rate[k]/n[k]:0),
      min_rate[k], max_rate[k] > out_summary
  }

  print "bucket\tcount" > out_buckets
  for (b in bucket_ct) printf "%s\t%d\n", b, bucket_ct[b] > out_buckets
}
AWK
fi

echo "Running Task 4: computing success_rate and buckets. Press Enter if it is hanging here."
awk -v hi=0.80 -v mid=0.50 \
    -v out_summary="$OUT/summary_by_key.tsv" \
    -v out_buckets="$OUT/bucket_counts.tsv" \
    -v col_key=1 -v col_attempts=2 -v col_success=3 \
    -f "$OUT/scripts/ratios.awk" "$INPUT" \
  | { read -r H; echo "$H"; sort -t$'\t' -k1,1; } \
  > "$OUT/with_rates.tsv"
{ read -r H; echo "$H"; sort -t$'\t' -k1,1; } < "$OUT/summary_by_key.tsv" > "$OUT/summary_by_key.sorted" \
  && mv "$OUT/summary_by_key.sorted" "$OUT/summary_by_key.tsv"

{ read -r H; echo "$H"; tail -n +2 "$OUT/bucket_counts.tsv" | sort -t$'\t' -k1,1; } > "$OUT/bucket_counts.sorted" \
  && { echo -e "bucket\tcount" > "$OUT/bucket_counts.tsv"; cat "$OUT/bucket_counts.sorted" >> "$OUT/bucket_counts.tsv"; rm "$OUT/bucket_counts.sorted"; }

echo "Row-wise output: $OUT/with_rates.tsv"
echo "Per-key summary: $OUT/summary_by_key.tsv"
echo "Bucket counts:   $OUT/bucket_counts.tsv"

# Task 5 - Temporal OR string structure (choose based on your data)
echo "Starting Task 5 - string structure"
awk '
BEGIN {
        FS =","
        OFS="\t"
        printf "%s\t%s\t%s\n", "condition","SD1 mean", "SD2 mean"
        }
NR>1 {
        sum1[$7]+=$2
        cnt[$7]++
        sum2[$7]+=$3
        }
END {
        for (p in cnt) {
                printf "%s\t%.2f\t%.2f\n", p, (sum1[p]/cnt[p]), (sum2[p]/cnt[p])
         }
 }
 ' $INPUT_FILE > $OUT/task5.tsv

 echo "Completed Task 5 successfully..moving on to Task 6"

 # Task 6 - "Signal discovery" tailored to your feature types
 echo "Starting Task 6 - Signal discovery"
awk 'BEGIN{
        FS=","
        OFS="\t"

        }
function find_min(num1, num2){
   if (num1 < num2)
   return num1
   return num2
}
function find_max(num1, num2){
   if (num1 > num2)
   return num1
   return num2
}


NR==2{
        SD1min=$2
        SD2min=$3
        sampenmin=$4
        higucimin=$5
        SD1max=$2
        SD2max=$3
        sampenmax=$4
        higucimax=$5
        }

NR>1{
        sumSD1+=$2
        sumSD2+=$3
        sumSampen+=$4
        sumHiguci+=$5
        sumsqSD1+=($2*$2)
        sumsqSD2+=($3*$3)
        sumsqSampen+=($4*$4)
        sumsqHiguci+=($5*$5)
        SD1min=find_min($2, SD1min)
        SD2min=find_min($2, SD2min)
        sampenmin=find_min($2, sampenmin)
        higucimin=find_min($2, higucimin)
        SD1max=find_max($2, SD1max)
        SD2max=find_max($3, SD2max)
        sampenmax=find_max($4, sampenmax)
        higucimax=find_max($5, higucimax)

        }
END{
        stSD1=sqrt((sumsqSD1/NR)-((sumSD1/NR)^2))
        stSD2=sqrt((sumsqSD2/NR)-((sumSD2/NR)^2))
        stSampen=sqrt((sumsqSampen/NR)-((sumSampen/NR)^2))
        stHiguci=sqrt((sumsqHiguci/NR)-((sumHiguci/NR)^2))
        printf "%s\t%s\t%s\t%s\t%s\n", "Column Values", "SD1", "SD2", "Sampen", "Higuci"
        printf "%s\t%.2f\t%.2f\t%.2f\t%.2f\n", "Standard Dev",  stSD1, stSD2, stSampen, stHiguci
        printf "%s\t%.2f\t%.2f\t%.2f\t%.2f\n", "Mean/Average", (sumSD1/NR), (sumSD2/NR), (sumSampen/NR), (sumHiguci/NR)
        printf "%s\t%.2f\t%.2f\t%.2f\t%.2f\n", "Minimum Val",  SD1min, SD2min, sampenmin, higucimin
        printf "%s\t%.2f\t%.2f\t%.2f\t%.2f\n", "Maximum Val",  SD1max, SD2max, sampenmax, higucimax
        }
	' $INPUT_FILE > $OUT/task6.tsv
	echo "Completed Task 6 successfully! All tasks are completed"

