#!/bin/bash
# ============================================================================================================================
# VARIANT CALLING CONFIG
# ============================================================================================================================


# Run structural variant calling with Manta
sv_call="true" # set to "false" to skip structural variant calling

# ---------------------------------------------------------------------------------------------------------------------------------
# Reference genome location
# ---------------------------------------------------------------------------------------------------------------------------------
ref_dir="/nfs5/BPP/Leiboff_Lab/Brian/genomes_tmp/genomes"


# ---------------------------------------------------------------------------------------------------------------------------------
# Available reference genomes
# Genomes of interest - edit keys & URLs
# ---------------------------------------------------------------------------------------------------------------------------------
declare -A genome_urls=(
    [b73]="https://download.maizegdb.org/Genomes/B73/Zm-B73-REFERENCE-NAM-5.0/Zm-B73-REFERENCE-NAM-5.0.fa.gz"
    [mo17]="https://download.maizegdb.org/Genomes/Mo17/Zm-Mo17-REFERENCE-CAU-1.0/Zm-Mo17-REFERENCE-CAU-1.0.fa.gz"
    [w22]="https://download.maizegdb.org/Genomes/W22/Zm-W22-REFERENCE-NRGENE-2.0/Zm-W22-REFERENCE-NRGENE-2.0.fa.gz"
    [p39]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-P39-REFERENCE-NAM-1.0/Zm-P39-REFERENCE-NAM-1.0.fa.gz"
    [ki11]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-Ki11-REFERENCE-NAM-1.0/Zm-Ki11-REFERENCE-NAM-1.0.fa.gz"
    [a188]="https://download.maizegdb.org/Genomes/A188/Zm-A188-REFERENCE-KSU-1.0/Zm-A188-REFERENCE-KSU-1.0.fa.gz"
    [a632]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-A632-REFERENCE-CAAS_FIL-1.0/Zm-A632-REFERENCE-CAAS_FIL-1.0.fa.gz"
    [oh43]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-Oh43-REFERENCE-NAM-1.0/Zm-Oh43-REFERENCE-NAM-1.0.fa.gz"
    [cml247]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-CML247-REFERENCE-NAM-1.0/Zm-CML247-REFERENCE-NAM-1.0.fa.gz"
    [tx303]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-Tx303-REFERENCE-NAM-1.0/Zm-Tx303-REFERENCE-NAM-1.0.fa.gz"
    [ky21]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-Ky21-REFERENCE-NAM-1.0/Zm-Ky21-REFERENCE-NAM-1.0.fa.gz"
    [oh7b]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-Oh7B-REFERENCE-NAM-1.0/Zm-Oh7B-REFERENCE-NAM-1.0.fa.gz"
    [tzi8]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-Tzi8-REFERENCE-NAM-1.0/Zm-Tzi8-REFERENCE-NAM-1.0.fa.gz"
    [nc350]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-NC350-REFERENCE-NAM-1.0/Zm-NC350-REFERENCE-NAM-1.0.fa.gz"
    [cml277]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-CML277-REFERENCE-NAM-1.0/Zm-CML277-REFERENCE-NAM-1.0.fa.gz"
    [b97]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-B97-REFERENCE-NAM-1.0/Zm-B97-REFERENCE-NAM-1.0.fa.gz"
    [cml322]="https://download.maizegdb.org/Genomes/NAM_Founders/Zm-CML322-REFERENCE-NAM-1.0/Zm-CML322-REFERENCE-NAM-1.0.fa.gz"
)

# ---------------------------------------------------------------------------------------------------------------------------------
# Available sample locations
# ---------------------------------------------------------------------------------------------------------------------------------
declare -A sample_loc=(
    [q1]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/bds1_ts"
    [q2]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S7_6508K"
    [q3]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/tsh3"
    [q4]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/rzl2"
    [q5]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S4_6508P"
    [q6]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S2_6609A"
    [q7]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S3_6508Q"
    [q8]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S1_6609B"
    [q9]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S8_6508F"
    [q10]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S6_6508N"
    [q11]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S5_6508O"
    [q12]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/S9_5807N"
    [q13]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/rzl1"
    [q14]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/ts3"
    [q17]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/mb6_ts071L"
    [q15]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/mb7_tsN2490"
    [q16]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/mb8_ts1967"
    [q21]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026/S004"
    [q22]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026/S674"
    [q23]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026/S676"
    [q24]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026/S687"
    [q25]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026/S691"
    [q26]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_sv"
    [q27]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_sv/svra3"
    [q391]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S391"
    [q393]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S393"
    [q539]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S539"
    [q599]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S599"
    [q600]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S600"
    [q605]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S605"
    [q609]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S609"
    [q617]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S617"
    [q623]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S623"
    [q626]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S626"
    [q627]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S627"
    [q630]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S630"
    [q639]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S639"
    [q648]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S648"
    [q651]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S651"
    [q689]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/S689"
    [q700]="/nfs5/BPP/Leiboff_Lab/Brian/bsa_2026B/cle7"
    [mb7]="/nfs5/BPP/Leiboff_Lab/Brian/bsa/mb7_tsN2490"
)


# ---------------------------------------------------------------------------------------------------------------------------------
# Genomes to process
# ---------------------------------------------------------------------------------------------------------------------------------

declare -a goi=( b73 )

# ---------------------------------------------------------------------------------------------------------------------------------
# samples to process
# ---------------------------------------------------------------------------------------------------------------------------------

declare -a samples=( q1 )

# *************** End of user setting **************************************