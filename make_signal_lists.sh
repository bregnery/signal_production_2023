echo "Warning: Run this on the LPC only, otherwise too slow"
source svj.sh source

base=root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/signal_madpt300_2023/MINIAOD

pats=(
    "$base/madpt300_*"
    )

list_dirs(){
    for pat in ${pats[@]} ; do
        remote-ls-wildcard $pat
    done
    }

dirs=( $(list_dirs) )

# For testing only:
# dirs=( "${dirs[@]:3:10}" )

echo "Looking for .root files in ${#dirs[@]} remote directories, using 8 concurrent processes. Output in signals_jetconst.txt."

{
    printf "%s\n" "${dirs[@]}" | xargs -i -P 8 -n 1 bash -c 'source svj.sh source; remote-ls-wildcard {}/*.root'
} >> signals_jetconst.txt
