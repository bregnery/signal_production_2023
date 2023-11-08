source svj.sh source

# Make sure subshells can use these functions too, needed for xargs
export -f make_dst_treemaker remote-ls remote-ls-root is-remote remote-split remote-exists

main(){
    extract_opt "miniaod" $@; export miniaod_pat="$res"
    extract_opt "dst" $@; export dstdir="$res"

    local miniaods=$(remote-ls-wildcard "$miniaod_pat")

    # Transform every miniaod rootfile to its treemaker destination
    local needed_ntuples=$(echo "$miniaods" | xargs -l bash -c 'make_dst_treemaker $0 $dstdir && echo $res' | sort)

    # Collect all different directories of the needed ntuples
    local needed_ntuples_dirs=$(echo "$needed_ntuples" | xargs dirname | uniq)

    # Get a list of all root files that already exist in these directories
    local existing_ntuples=$(echo "$needed_ntuples_dirs" | xargs -l bash -c 'remote-exists $0 && remote-ls-root $0' | sort)

    # Get files that are only in $needed but not in $existing
    # See https://serverfault.com/a/68786
    local ntuples_to_produce=$(comm -23 <(echo "${needed_ntuples[@]}") <(echo "${existing_ntuples[@]}"))

    # Finally, replace $dstdir back to MINIAOD to transform this into a list of MINIAOD files that need to be processed
    echo "$ntuples_to_produce" | sed 's/'$dstdir'/MINIAOD/'
    }

main $@