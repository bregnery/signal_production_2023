echo "Warning: Run this on the LPC only, otherwise too slow"
source svj.sh source

base=root://cmseos.fnal.gov//store/user/lpcsusyhad/SusyRA2Analysis2015/Run2ProductionV20

pats=(
    "$base/Summer20UL1*/QCD_Pt*"
    "$base/Summer20UL1*/TTJets_*"
    "$base/Summer20UL1*/WJetsToLNu_*"
    "$base/Summer20UL1*/ZJetsToNuNu_*"
    )

list_dirs(){
    for pat in ${pats[@]} ; do
        remote-ls-wildcard $pat
    done
    }

dirs=( $(list_dirs) )

# For testing only:
# dirs=( "${dirs[@]:3:10}" )

echo "Looking for .root files in ${#dirs[@]} remote directories, using 8 concurrent processes. Output in bkg.txt."

{
    printf "%s\n" "${dirs[@]}" | xargs -i -P 8 -n 1 bash -c 'source svj.sh source; remote-ls-wildcard {}/*.root'
} >> bkg.txt
