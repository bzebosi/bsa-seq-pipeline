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
        logmsg "Minimap2 index already exists for ${gbase} - skipping indexing"
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


# -------------------------------------------------------------------------------------------------------
# trim read
# -------------------------------------------------------------------------------------------------------

# Directory names
reads_name="raw_reads"
fastp_name="fastp_trim"
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

# -------------------------------------------------------------------------------------------------------
# Map Reads 
# -------------------------------------------------------------------------------------------------------
map_reads(){
    local project=$1
    local gbase=$2
    local project_dir
    project_dir=$(get_project_dir "${project}") || return 1
    local trim_dir=${project_dir}/${fastp_name}/${trim_reads_name}
    local idx_dir=${ref_dir}/indexes
    local bam_dir=${project_dir}/${bam}
    local stats_dir=${project_dir}/${stats}
    local reports_dir=${stats_dir}/${reports}
    local plots_dir=${stats_dir}/${plots}


    create_dir "${bam_dir}" "${stats_dir}" "${reports_dir}" "${plots_dir}" || return 1
    # create reference paths
    local idx_mmi=${idx_dir}/${gbase}.mmi
    local genome_fa=${idx_dir}/${gbase}.fa

    if [[ -s "${idx_mmi}" && -s "${genome_fa}" ]]; then
        logmsg "Using index: ${idx_mmi} and FASTA: ${genome_fa}"
    else
        logmsg "Error: index or FASTA missing for ${gbase}"
        return 1
    fi

    # Check if overall coverage file exists, create if missing
    local overall_coverage="${stats_dir}/overall_coverage.tsv"

    # Initialize coverage summary
    if [[ ! -s "${overall_coverage}" ]]; then
        if echo -e "Genome\tSample\tRead_Type\tCoverage\tTotal_Reads\tMapped_Reads\tProperly_Paired\tMapped_%" > "${overall_coverage}"; then

            logmsg "Successfully created ${overall_coverage}"
        else
            logmsg "Error creating ${overall_coverage}"
            return 1
        fi
    fi

    local O1

    for O1 in "${trim_dir}"/*_trim_R1.fq.gz; do
        local sbase=$(basename "${O1}" "_trim_R1.fq.gz")
        local O2=${trim_dir}/${sbase}_trim_R2.fq.gz
        local tag=${gbase}_${sbase}
        local bam_out=${bam_dir}/${tag}.bam
        local read_type

        # check if paired or single end
        if [[ -s "${O2}" ]]; then
            read_type="PE"
        else
            read_type="SE"
        fi

        # Run Minimap2 alignmenT

        # Skip if BAM and BAM index already exists
        if [[ -s "${bam_out}" && -s "${bam_out}.bai" ]]; then
            logmsg "${sbase} already mapped to ${gbase}. Skipping mapping"
        fi

        
        # Map paired-end reads
        if [[ "${read_type}" == "PE" ]]; then
            logmsg "PE mapping ${sbase} to ${gbase} started"

            if minimap2 -ax sr -t "${threads}" "${idx_mmi}" "${O1}" "${O2}" |
                samtools sort -@ "${threads}" -o "${bam_out}"; then

                logmsg "PE alignment and sorting of ${bam_out} completed"
            else
                logmsg "ERROR: PE mapping failed for ${bam_out}"
                continue
            fi
        
        # Map single-end reads
        else
            logmsg "SE mapping ${sbase} to ${gbase} started"

            if minimap2 -ax sr -t "${threads}" "${idx_mmi}" "${O1}" |
                samtools sort -@ "${threads}" -o "${bam_out}"; then

                logmsg "SE alignment and sorting for ${bam_out} completed"
            else
                logmsg "ERROR: SE mapping failed for ${bam_out}"
                continue
            fi
        fi

        # Index BAM file
        logmsg "samtools indexing ${bam_out} started"

        if samtools index "${bam_out}"; then
            logmsg "${bam_out} successfully indexed"
        else
            logmsg "Indexing of ${bam_out} failed"
            continue
        fi

        logmsg "Read mapping completed for ${sbase}"

        if awk -F '\t' -v genome="${gbase}" -v sample="${sbase}" \
            '$1 == genome && $2 == sample {found=1} END {exit !found}'\
            "${overall_coverage}"; then

            logmsg "Coverage for ${tag} already present. Skipping stats.."
        else
            # Run samtools flagstat and extract relevant values
            local stats total_reads mapped_reads properly_paired depth

            logmsg "Flagstat for ${bam_out}"
            stats=$(samtools flagstat "${bam_out}")

            # Extract read statistics
            total_reads=$(echo "${stats}" |
            awk '/in total/ {print $1; exit}')

            mapped_reads=$(echo "${stats}" |
            awk '$4 == "mapped" {print $1; exit}')

            if [[ ${read_type} == "PE" ]]; then
                properly_paired=$(echo "${stats}" |
                    awk '/properly paired/ {print $1; exit}')
            else
                # For single-end data, paired reads are not applicable
                properly_paired="NA"
            fi

            # Check read statistics
            if [[ -z "${total_reads}" || -z "${mapped_reads}" || "${total_reads}" -eq 0 ]]; then
                logmsg "Error: Could not retrieve valid read statistics for ${bam_out}"
                continue
            fi

            local alignment_percentage
            if alignment_percentage=$(awk -v total="${total_reads}" -v mapped="${mapped_reads}" \
                'BEGIN {printf "%.2f", (mapped/total)*100}'); then
                logmsg "Aignment percentage calculated"
            fi

            # compute coverage depth using samtoools - depth
            logmsg "computing coverage depth ${bam_out} started"
            if depth=$(samtools depth -a ${bam_out} | awk '{sum+=$3} END { print sum/NR }'); then 
                logmsg "Coverage calculated for ${bam_out}: ${depth}x"
            else
                logmsg "Coverage calculation failed for ${bam_out}" &&  exit 1
            fi

            # Append structured tab-separated results
            echo -e "${gbase}\t${sbase}\t${read_type}\t${depth}\t${total_reads}\t\
            ${mapped_reads}\t${properly_paired}\t${alignment_percentage}" >> "${overall_coverage}"
        fi

    done
}
