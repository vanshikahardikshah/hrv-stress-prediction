#Begin Spark
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

spark = SparkSession.builder \
    .appName("HeartRateStressAnalysis") \
    .getOrCreate()

#Read from Google Bucket the CSV file
df = spark.read.csv(
    "gs://group5cs131/input/heart_rate_non_linear_features_test.csv",
    header=True,
    inferSchema=True
)

print("\nData Schema:")
df.printSchema()

#Clean the file
df_clean = (
    df.select("uuid","SD1","SD2","sampen","higuci","datasetId","condition")
      .withColumn("condition", F.trim(F.col("condition")))
      .filter((F.col("SD1") > 0) & (F.col("SD2") > 0) &
              (F.col("sampen") > 0) & (F.col("higuci") > 0))
      .dropna(subset=["SD1","SD2","sampen","higuci","condition","datasetId"])
)

df_fe = (
    df_clean
      .withColumn("sd_ratio", F.col("SD2")/F.col("SD1"))
      .withColumn("sd_product", F.col("SD1")*F.col("SD2"))
      .withColumn("log_sampen", F.log(F.col("sampen")))
)

w_ds = Window.partitionBy("datasetId")

#Find Z score
def zscore(colname):
    mu  = F.avg(F.col(colname)).over(w_ds)
    sig = F.stddev(F.col(colname)).over(w_ds)
    return F.when(sig > 0, (F.col(colname) - mu)/sig).otherwise(F.lit(0.0))

df_win = (
    df_fe
      .withColumn("SD1_z", zscore("SD1"))
      .withColumn("SD2_z", zscore("SD2"))
      .withColumn("sampen_z", zscore("sampen"))
      .withColumn("higuci_z", zscore("higuci"))
      .withColumn("sd_ratio_z", zscore("sd_ratio"))
      .withColumn("sd_product_z", zscore("sd_product"))
)

#Show first 10
df_win.select("datasetId","SD1","SD1_z","SD2","SD2_z","sampen","sampen_z","higuci","higuci_z") \
      .show(10, truncate=False)

#Aggregations by Dataset and Condition
agg_by_ds_cond = (
    df_win.groupBy("datasetId","condition")
          .agg(
              F.count("*").alias("n"),
              F.avg("SD1").alias("SD1_mean"),
              F.stddev("SD1").alias("SD1_sd"),
              F.avg("SD2").alias("SD2_mean"),
              F.stddev("SD2").alias("SD2_sd"),
              F.avg("sampen").alias("sampen_mean"),
              F.avg("higuci").alias("higuci_mean"),
              F.expr("percentile_approx(sd_ratio, 0.5)").alias("sd_ratio_median")
          ).orderBy("datasetId","condition")
)

class_balance = (
    df_win.groupBy("datasetId")
          .pivot("condition")
          .count()
          .fillna(0)
          .orderBy("datasetId")
)

df_win.write \
    .mode("overwrite") \
    .partitionBy("condition") \
    .option("header", "true") \
    .csv("/tmp/output/processed_data/")

agg_by_ds_cond.write \
    .mode("overwrite") \
    .option("header", "true") \
    .csv("/tmp/output/aggregations/")

spark.stop()
