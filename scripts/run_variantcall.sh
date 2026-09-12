#!/bin/bash

# -------------------------------------------------------------------------------------------------------
# log functions for updates and status
# -------------------------------------------------------------------------------------------------------
logmsg() { echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" ; }


# -------------------------------------------------------------------------------------------------------
# Validate project and its directory
# -------------------------------------------------------------------------------------------------------
project_dir(){
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

