#!/bin/bash

# -------------------------------------------------------------------------------------------------------
# log functions for updates and status
# -------------------------------------------------------------------------------------------------------
logmsg() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" ; }


# -------------------------------------------------------------------------------------------------------
# Validate project and its directory
# -------------------------------------------------------------------------------------------------------
get_project_dir(){
    local project=$1
    local dir

    # check if the project was provided
    if [[ -z ${project} ]]; then
        logmsg "Error : No project specified."
        return 1
    fi 
    
    # Build the project directory path
    dir="${base_dir}/${project}"
    
    # check if the project directory exits
    if [[ -d ${dir} ]]; then
        logmsg ${dir} 
    else
        logmsg "Error: Project directory does not exit ${dir}"
        return 1
    fi
}

# -------------------------------------------------------------------------------------------------------
# Create one or more directories
# -------------------------------------------------------------------------------------------------------
create_dir() {
    local dir

    # Loop through each directory provided
    for dir in "$@"; do
        
        # check if the directory already exists
        if [[ -d ${dir} ]]; then
            logmsg "Directory already exists: ${dir}"

            # create the directory
            elif mkdir -p ${dir}; then
                logmsg "Directory created: ${dir}"
            
            # Report an error if the directory failed to create
            else
                logmsg "Error: Failed to create directory: ${dir}"
                return 1
        fi
    done
}

# -------------------------------------------------------------------------------------------------------
# download genome functions
# . looks up URL in genome_urls[]
# -------------------------------------------------------------------------------------------------------

download_genome(){
    local gbase=$1
    local url=${genome_urls[$gbase]:-}
    local genome=${ref_dir}/${gbase}.fa.gz

    # Create reference directory
    create_dir ${ref_dir}

    # Check if a URL was found for the genome
    if [[ -z $url ]]; then
        logmsg "Error: No URL found for genome: $gbase"
        return 1
    fi

    logmsg "Checking genome $gbase : $genome"

    # Skip download if genome already exists and is not empty
    if [[ -s ${genome} ]]; then
        logmsg "Genome ${genome} already exits - skipping download."
    else
        # Download genome
        logmsg "Downloading ${gbase} genome.."
        if wget -O ${genome} ${url}; then
            logmsg "${gbase} sucessfully downloaded"
        else 
            logmsg "Error: download failed or URL missing for ${gbase}"
            return 1
        fi
    fi
    
}

# -------------------------------------------------------------------------------------------------------
# index genome
# -------------------------------------------------------------------------------------------------------

index_genome(){
    local gbase=$1
    local genome_gz=${ref_dir}/${gbase}.fa.gz
    local genome=${ref_dir}/${gbase}.fa
    local idx_dir=${ref_dir}/indexes
    local mmi=${idx_dir}/${gbase}.mmi
    local fai=${idx_dir}/${gbase}.fa.fai
    local link_fa=${idx_dir}/${gbase}.fa

    create_dir ${idx_dir}

    # check genome 
    if [[ ! -s ${genome} && ! -s ${genome_gz} ]]; then 
        logmsg "Error: ${genome_gz} not found or empty - cannot index"
        return 1
    fi

    # unzip genome if needed
    if [[ ! -s ${genome} &&  -s ${genome_gz} ]]; then 
        logmsg "Unzipping ${genome_gz}"
        if gunzip -c ${genome_gz} > ${genome}; then
            logmsg "Unzipped genome created: ${genome}"
        else
            logmsg "Error: Failed to unzip ${genome_gz}"
            return 1
        fi
    fi

    # index the genome using minimap2
    logmsg "Starting Minimap2 indexing for ${genome}.."
    if [[ -s ${mmi} ]]; then
        logmsg "Minimap2 index already exists for ${gbase} - skipping"
    else
        logmsg "Building minimap2 index for ${gbase}..."
        if minimap2 -t ${threads} -d ${mmi} ${genome} ; then
            logmsg "Minimap2 index completed ${mmi}"
        else
            logmsg "Error: minimap2 index failed for ${genome}"
            return 1
        fi
    fi

    # index the genome using samtools faidx .fai and .gzi
    if [[ -s ${fai} ]]; then
        logmsg "samtools index .fai for ${gbase} already exists - skip indexing"
    else
        if [[ -s ${genome}.fai ]]; then
            mv -u ${genome}.fai ${fai} && logmsg "moved ${genome}.fai to ${fai}"
        else
            logmsg "Running samtools faidx on ${genome}.."
            if samtools faidx ${genome} ; then
                logmsg "samtools faidx complete for ${gbase}"
                if [[ -f ${genome}.fai ]]; then
                    mv -u ${genome}.fai ${fai} && logmsg "moved ${genome}.fai to ${fai}"
                fi
            else
                logmsg "samtools index failed for ${gbase}. " 
                return 1
            fi
        fi
    fi

    # create fasta symlink besides the indexs
    if [[ -e ${link_fa} ]]; then
        logmsg "symlink already exists"
    else
        if ln -s ${genome} ${link_fa}; then
            logmsg "Symlink created ${link_fa} for ${genome}"
        else
            logmsg "Error: failed to created symlink for genome: ${gbase}"
            return 1
        fi
    fi
}

# Directory names
reads_name="01_raw_reads"
fastp_name="02_fastp_trim"
fastqc_name="03_fastqc"
trim_reads_name="trim_reads"
reports_name="reports"

trim_reads(){
    local project=$1
    local project_dir
    project_dir=$(get_project_dir ${project}) || return 1
    local raw_reads_dir=${project_dir}/${reads_name}
    local fastp_dir=${project_dir}/${fastp_name}
    local trim_dir=${fastp_dir}/${trim_reads_name}
    local report_dir=${fastp_dir}/${reports_name}
    local summary=${report_dir}/fastp_summary.tsv

    create_dir ${trim_dir} ${report_dir} || return 1

    # Initialize summary file 
    if [[ ! -s ${summary} ]]; then
        # Add a header to the summary file
        echo -e "Sample\tRead_Type\tTotal_Reads_Before\tGC_Content_Before\tTotal_Reads_After\t\
        GC_Content_After\tPassed_Filter_Reads\tLow_Quality_Reads\tToo_Many_N_Reads\t\
        Too_Short_Reads\tDuplication_Rate\tInsert_Size_Peak" > ${summary}

        logmsg "Summary file created: ${summary}"
    fi

    local R1
    for R1 in ${raw_reads_dir}/*_R1.fq.gz; do
        local fname=$(basename ${R1})

        local sbase=${fname%_R1.fq.gz}
        local R2=${raw_reads_dir}/${sbase}_R2.fq.gz
        local O1=${trim_dir}/${sbase}_trim_R1.fq.gz
        local O2=${trim_dir}/${sbase}_trim_R2.fq.gz
        local ht=${report_dir}/${sbase}_fastp_report.html
        local jt=${report_dir}/${sbase}_fastp_report.json
        local metrics=""
        local read_type

        # Check matching R2
        if [[ -s "${R2}" ]]; then
            read_type="PE"
        else
            read_type="SE"
        fi

        # Skip if already summarized
        if awk -F '\t' -v sample="${sbase}" -v type="${read_type}" '
            NR > 1 && $1 == sample && $2 == type && NF == 12 {found = 1}
            END {exit !found}
        ' "${summary}"; then
            logmsg "${sbase} already completed. Skipping."
            continue
        fi

        # Run fastp
        if [[ ${read_type} == "PE" ]]; then
            if [[ ! -s "${O1}" || ! -s "${O2}" || ! -s "${jt}" ]]; then
                if fastp -i ${R1} -I ${R2} -o ${O1} -O ${O2} --detect_adapter_for_pe \
                    --thread ${threads} -h ${ht} -j ${jt}; then
                    logmsg "fastp complete for ${sbase}"
                else
                    logmsg "ERROR : fastp failed ${sbase}"
                    continue
                fi
            else
                logmsg "$(basename "${O1}") and $(basename "${O1}") already exist and trimmed. skip fastp..."
                
            fi

         else

            if [[ ! -s "${O1}" || ! -s "${jt}" ]]; then
                if fastp -i ${R1} -o ${O1} --thread ${threads} -h ${ht} -j ${jt} ; then
                    logmsg "fastp complete for ${sbase}"
                else
                    logmsg "ERROR : fastp failed ${sbase}"
                    continue
                fi
            else
                logmsg "$(basename "${O1}") already exists and is trimmed. Skipping fastp..."
            fi
        fi

        # Extract fastp metrics
        if [[ -s "${jt}" ]]; then
            metrics="$(
                jq -r '
                    [.summary.before_filtering.total_reads, .summary.before_filtering.gc_content,
                    .summary.after_filtering.total_reads, .summary.after_filtering.gc_content,
                    .filtering_result.passed_filter_reads, .filtering_result.low_quality_reads,
                    .filtering_result.too_many_N_reads, .filtering_result.too_short_reads,
                    .duplication.rate, .insert_size.peak ] | @tsv' "${jt}"
                )" || metrics=""
        fi

        # Check metrics
        if [[ -z "${metrics}" ]]; then
            logmsg "ERROR: Could not extract fastp metrics for ${sbase}"
            continue
        fi

        # Add summary row
        echo -e "${sbase}\t${read_type}\t${metrics}" >> "${summary}"

        logmsg "fastp complete for ${sbase} (${read_type})"
    done

     logmsg "Read trimming completed for project: ${project}"
}

