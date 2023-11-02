#!/bin/bash
export DRYMODE=0

streq(){
    return $(test "x$1" = "x$2")
    }

strneq(){
    return $(test "x$1" != "x$2")
    }

strempty(){
    return $(test -z "$1")
    }

strnempty(){
    return $(test ! -z "$1")
    }

error(){
    printf "[$(date)] ERROR: $1"
    exit 1
    }

log(){
    # Like echo, but colored and with a time stamp
    local normal=$'\e[0m'
    local blue=$'\e[94m'
    echo "$blue[$(date)] $1$normal"
    }

extract_opt_optional(){
    # Extracts a keyword=value option from the given arguments.
    # res will be empty if not found
    local key=$1 ; shift 1
    local n=${#key}
    ((n++)) # +1 to account for the =
    for arg in $@ ; do
        if streq "${arg:0:$n}" "$key=" ; then
            res="${arg:$n}"
            return
        fi
    done
    res=""
    }

extract_opt(){
    # Extracts a keyword=value option from the given arguments.
    # Raises an error if not found
    extract_opt_optional $@
    if test -z $res; then
        error "$1= is a mandatory command line parameter"
    fi
    }

strip_slash(){
    # Strips single trailing slash from a string if there is one.
    # Echoes result.
    local s="$1"
    if streq "${s: -1}" "/" ; then
        s="${s:0:${#s}-1}"
    fi
    echo "$s"
    }

bilateral_strip_slash(){
    # Strips single slashes from the beginning and end of a string
    # Echoes result.
    local s="$1"
    if streq "${s:0:1}" "/" ; then
        s="${s:1}"
    fi
    if streq "${s: -1}" "/" ; then
        s="${s:0:${#s}-1}"
    fi
    echo "$s"
    }

fullpath(){
    # Echoes the full path to a file/directory.
    # Useful if realpath is not installed.
    echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    }

# ______________________________________________________________________________________
# HTCondor utils

getkey(){
    # Greps the .ad file _CONDOR_JOB_AD for a key, and stores the part _after_ the = to
    # an output variable $res.
    # Also strips quotation ""
    # 
    # Example:
    # $ getkey procid ; echo $res
    # >>> 0
    local key="$1"
    local line=$(grep -i "^$key = " "${_CONDOR_JOB_AD}")
    local EXITCODE=$?
    if [ $EXITCODE -ne 0 ]; then
        echo "No such key: $key"
        return 1
    fi
    res=$(echo $line | cut -d '=' -f 2- | tr -d '"')
    # Removing the leading white space that's still there
    res="${res:1}"
    }

get_procid(){
    getkey "procid"
    }

getrow(){
    # Gets a row from a file; Result is put in $res
    if test $2 -eq 0; then
        log "warning: getrow infile 0 will return nothing; pass 1 instead"
    fi
    res=$(head "-$2" $1 | tail -1)
    }

nrows(){
    # Counts number of lines in a file
    # See: https://stackoverflow.com/a/59573533
    res=$(grep -c ^ "$1")
    }

cat-jobad(){
    echo "Contents of ${_CONDOR_JOB_AD}:"
    cat ${_CONDOR_JOB_AD}
    }

# ______________________________________________________________________________________
# Easier XRootD interface

is-remote(){
    if [[ $1 == *"://"* ]]; then
        return 0
    else
        return 1
    fi
    }

is-not-remote(){
    if [[ $1 == *"://"* ]]; then
        return 1
    else
        return 0
    fi
    }

remote-split(){
    # Splits a remote path into the server and the path.
    # Result is set in $res
    local components
    local path="$1"
    # First replace "//" with ";", then split on ";"
    IFS=";" read -ra components <<< ${path//\/\//;}
    # echo "${components[@]}"
    res=("${components[0]}//${components[1]}" "/${components[2]}" )
    }

remote-ls(){
    # Calls xrdfs ... ls ... on a single path.
    # Output will have the server name in front of it.
    local path="$1"
    remote-split $path
    xrdfs "${res[0]}" ls "${res[1]}" | while read line; do
        echo "${res[0]}/$line"
    done
    }

remote-exists(){
    # Checks if a path exists. Returns 0 if exists, 1 if not.
    local path="$1"
    remote-split $path
    xrdfs "${res[0]}" stat "${res[1]}" 1> /dev/null 2> /dev/null
    local exitcode="$?"
    if test $exitcode -eq 0 ; then
        return 0
    else
        return 1
    fi
    }

remote-not-exists(){
    # Simply the inverse of remote-exists
    if remote-exists $1 ; then
        return 1
    else
        return 0
    fi
    }

remote-ls-root(){
    # Takes remote-ls output, and only prints if the line ends with .root
    remote-ls $1 | while read line; do 
        if test ${line:(-5)} = ".root" ; then
            echo $line
        fi
    done
    }

_remote-ls-wildcard(){
    local prefix="$1"; shift 1
    local curr="$1"; shift 1
    local components=("$@"); shift 1
    local ncomponents=${#components[@]}

    # echo "components=${components[@]}"

    local i=0
    while test $i -lt $ncomponents && ! [[ ${components[$i]} == *['['']''}''{''!'@#\$%^\&*()+]* ]]; do
        curr="$curr/${components[$i]}"
        ((i++))
    done

    local inext=$((i+1))

    if test $i -eq $ncomponents; then
        # There were no stars in the pattern; just echo the current path, if it exists
        if remote-exists "$prefix/$curr"; then
            echo "$prefix/$curr"
        fi
        return
    fi

    # Pop off all components that have been moved to $curr
    local pat="${components[$i]}"
    local remaining_components="${components[@]:$inext}"

    # echo "curr=$curr i=$i pat=$pat remaining_components=${remaining_components[@]}"

    # Get directory contents of $curr
    for f in $(xrdfs $prefix ls $curr ); do
        # For every node that matches the current component, resolve the rest of the 
        # pattern
        local b=$(basename $f)
        # echo "Comparing $b with $pat"
        if [[ $b == $pat ]]; then
            # It's a match
            if test $inext -eq $ncomponents; then
                # If there are no further components, this is a final match
                echo "$prefix/$f"
            else
                # There are further things to match
                _remote-ls-wildcard "$prefix" "$f" "${remaining_components[@]}"
            fi
        fi
    done
    }

remote-ls-wildcard(){
    # Like xrdfs ... ls ..., but accepts wildcards and other patterns
    # 
    # Example:
    # remote-ls-wildcard root://cmseos.fnal.gov//store/user/klijnsma/package_test_files/dev-stars/bar[ab]/file*.txt
    # root://cmseos.fnal.gov//store/user/klijnsma/package_test_files/dev-stars/bara/file1.txt
    # root://cmseos.fnal.gov//store/user/klijnsma/package_test_files/dev-stars/bara/file2.txt
    # root://cmseos.fnal.gov//store/user/klijnsma/package_test_files/dev-stars/barb/file2.txt
    # root://cmseos.fnal.gov//store/user/klijnsma/package_test_files/dev-stars/barb/file3.txt
    # 
    # Echoes results.
    local input="$1"
    remote-split $input
    local prefix="${res[0]}"
    local starpath="${res[1]}"
    starpath=$(bilateral_strip_slash "$starpath")
    # Split on "/"
    local components
    IFS="/" read -ra components <<< $starpath
    # echo "prefix=$prefix"
    # echo "starpath=$starpath"
    # echo "components=${components[@]}"
    _remote-ls-wildcard "$prefix" "" "${components[@]}"
    }

# ______________________________________________________________________________________
# SVJ Productions interface

default_physics(){
    # Default physics:
    #    0   1    2     3     4      5    6    7
    #    mz  rinv boost mdark alpha  year part nevents
    res=(350 0.1  300   10    "peak" 2018 1    10000)   
    }

print_physics(){
    local physics=("$@")
    echo "PHYS[mz=${physics[0]} rinv=${physics[1]} boost=${physics[2]} mdark=${physics[3]} alpha=${physics[4]} year=${physics[5]} part=${physics[6]} nevents=${physics[7]}]"
    }

interpret_args(){
    # Consumes physics parameters from the input arguments
    default_physics
    while strnempty "$1" ; do
        if streq "${1:0:3}" "mz=" ; then
            res[0]="${1:3}"
        elif streq "${1:0:5}" "rinv=" ; then
            res[1]="${1:5}"
        elif streq "${1:0:6}" "boost=" ; then
            res[2]="${1:6}"
        elif streq "${1:0:6}" "mdark=" ; then
            res[3]="${1:6}"
        elif streq "${1:0:6}" "alpha=" ; then
            res[4]="${1:6}"
        elif streq "${1:0:5}" "year=" ; then
            res[5]="${1:5}"
        elif streq "${1:0:5}" "part=" ; then
            res[6]="${1:5}"
        elif streq "${1:0:8}" "nevents=" ; then
            res[7]="${1:8}"
        fi
        shift 1
    done
    }

interpret_filename(){
    local filename="$1"
    if test -z "$filename" ; then
        log "Warning: no filename passed; using default physics"
    fi

    default_physics ; local physics=("${res[@]}")

    # Extract parameters from filename and plug them into array
    local mz="$(echo $filename | grep -o mz[0-9]* | head -n 1)"
    if strneq $mz "mz" ; then
        physics[0]="${mz:2}"
    fi

    local rinv="$(echo $filename | grep -o rinv0\.[0-9\.]* | head -n 1)"
    if strneq $rinv "rinv" ; then
        physics[1]="${rinv:4}"
    fi

    local boost="$(echo $filename | grep -o madpt[0-9]* | head -n 1)"
    if strneq $boost "madpt" ; then
        physics[2]="${boost:5}"
    fi

    local mdark="$(echo $filename | grep -o mdark[0-9]* | head -n 1)"
    if strneq $mdark "mdark" ; then
        physics[3]="${mdark:5}"
    fi

    res=("${physics[@]}")
    }

mgtarball(){
    # Returns a path to the MadGraph tarball for a specific set of physics
    local download_path="root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/mgtarballs/2023MADPT"
    local physics=("$@")
    local gpname="step0_GRIDPACK_s-channel_mMed-${physics[0]}_mDark-${physics[3]}_MADPT${physics[2]}_13TeV-madgraphMLM-pythia8_n-10000.tar.xz"
    res="$download_path/$gpname"
    }

limited_outstring(){
    # Returns a physics-formatted string as created by SVJProductions.
    # Does not contain _n-{nevents}_part-{part} 
    local physics=("$@")
    res="s-channel_mMed-${physics[0]}_mDark-${physics[3]}_rinv-${physics[1]}_alpha-${physics[4]}_MADPT${physics[2]}_13TeV-madgraphMLM-pythia8"
    }

outstring(){
    # Returns a physics-formatted string as created by SVJProductions.
    # Contains _n-{nevents}_part-{part} 
    local outstep="$1"; shift 1
    local physics=("$@")
    res="${outstep}_s-channel_mMed-${physics[0]}_mDark-${physics[3]}_rinv-${physics[1]}_alpha-${physics[4]}_MADPT${physics[2]}_13TeV-madgraphMLM-pythia8_n-${physics[7]}_part-${physics[6]}"
    }

outfile(){
    # Returns a physics-formatted output rootfile as created by SVJProductions.
    outstring $@
    res="$res.root"
    }

svjcommand(){
    # Returns a cmsRun command for the instep, outstep, and given physics.
    # Does _not_ run the command.
    local instep="$1"; shift 1
    local outstep="$1"; shift 1
    local physics=("$@")
    res=(\
        "cmsRun runSVJ.py" \
        "year=${physics[5]}" \
        "madgraph=1" \
        "channel=s" \
        "outpre=$outstep" \
        "config=$outstep" \
        "part=${physics[6]}" \
        "mMediator=${physics[0]}" \
        "mDark=${physics[3]}" \
        "rinv=${physics[1]}" \
        "inpre=$instep" \
        "boost=${physics[2]}" \
        "boostvar=madpt"
        )
    if streq $instep "step0_GRIDPACK" ; then
        res+=("maxEventsIn=10000")
    fi
    if strnempty "${physics[7]}" ; then
        res+=("maxEvents=${physics[7]}")
    fi
    res="${res[@]}"
    }

runstep(){
    # Runs a single step of the SVJProductions chain.
    local cmsswdir=$1 ; shift 1
    local instep=$1 ; shift 1
    local outstep=$1 ; shift 1
    local inrootfile=$1 ; shift 1
    local physics=("$@")

    local rundir="$cmsswdir/src/SVJ/Production/test"

    log "===================================================================="
    log "===================================================================="
    log "Running $instep -> $outstep"
    
    log "CMS env setup in $cmsswdir"
    if test $DRYMODE -eq 0 ; then
        cd "$cmsswdir/src"
        scram b ProjectRename
        cmsenv
        cd SVJ/Production/test
    fi

    # Make the input files needed for the step available
    # For step_LHE-GEN, this is a tarball; for all other steps this is the rootfile
    # of the previous step
    if streq $instep "step0_GRIDPACK"; then
        # Copy the input tarball
        mgtarball "${physics[@]}"; local mgtb="$res"
        if remote-not-exists $mgtb ; then
            error "mgtarball $mgtb does not exist; cannot generate."
        fi
        log "Copying $mgtb -> $rundir"
        if test $DRYMODE -eq 0 ; then xrdcp $mgtb $rundir ; fi
    else
        # Copy/move the input rootfile to expected location
        outfile $instep "${physics[@]}"; local expected_inrootfile=$res
        if is-remote $inrootfile ; then
            log "Copying $inrootfile -> $expected_inrootfile"
            if test $DRYMODE -eq 0 ; then xrdcp $inrootfile $expected_inrootfile ; fi
        else
            log "Moving $inrootfile -> $expected_inrootfile"
            if test $DRYMODE -eq 0 ; then mv $inrootfile $expected_inrootfile || true ; fi
        fi
    fi

    svjcommand $instep $outstep "${physics[@]}" ; local cmd="$res"
    log "Executing: $cmd"
    local exitcode=0
    if test $DRYMODE -eq 0 ; then
        set +e # Catch the exitcode
        $cmd
        local exitcode=$?
        set -e
    fi
    log "Command exited with $exitcode"

    outfile $outstep "${physics[@]}"
    res="$rundir/$res"
    return $exitcode
    }

# ______________________________________________________________________________________
# TreeMaker interface

make_dst_treemaker(){
    local rootfile="$1"
    local dstdir="$2"

    # Determine destination
    if is-remote "$dstdir"; then
        # If dstdir is remote, just put basename $rootfile in it
        res="$(strip_slash $dstdir)/$(basename $rootfile)"
    else
        # Else, replace the substring "MINIAOD" in $rootfile with $dstdir
        res="${rootfile//MINIAOD/$dstdir}"
    fi
    }

process_rootfile(){
    local rootfile="$1"
    local dstdir="$2"
    make_dst_treemaker $rootfile $dstdir; local dst="$res"
    
    log "Processing $rootfile -> $dst"

    local local_rootfile="local.root"
    local local_dst="output_RA2AnalysisTree.root"

    # Remove any pre-existing files that get in the way of xrootd
    if test $DRYMODE -eq 0 ; then
        if test -f "$local_dst"; then
            log "Removing existing ${local_dst}"
            rm $local_dst || true
        fi
        if test -f "$local_rootfile"; then
            log "Removing existing ${local_rootfile}"
            rm $local_rootfile || true
        fi
    fi

    if test $DRYMODE -eq 0 && remote-exists $dst ; then
        log "$dst already exists, skipping"
        return 0
    fi

    log "Copying $rootfile -> ${local_rootfile}"
    if test $DRYMODE -eq 0 ; then xrdcp $rootfile $local_rootfile ; fi

    cmd=(\
        "cmsRun runMakeTreeFromMiniAOD_cfg.py" \
        "numevents=-1" \
        "outfile=output" \
        "scenario=Summer20UL18sig" \
        "lostlepton=1" \
        "doZinv=0" \
        "systematics=1" \
        "deepAK8=0" \
        "deepDoubleB=0" \
        "doPDFs=1" \
        "nestedVectors=False" \
        "debugjets=0" \
        "splitLevel=99" \
        "boostedsemivisible=1" \
        "dataset=file:${local_rootfile}"\
        )
    cmd="${cmd[@]}"
    log "Running treemaker command: $cmd"

    if test $DRYMODE -eq 0 ; then
        set +e # Temporarily disable set -e to catch the exit code
        _CONDOR_CHIRP_CONFIG="" $cmd
        local exitcode=$?
        set -e
    else
        local exitcode=0
    fi

    # Check for failures; save failure code in $res but still return 0
    if test $exitcode -ne 0; then
        log "TreeMaker failed with exitcode $exitcode"
        res=$exitcode
        return 0
    fi
    if test ! -e $local_dst ; then
        log "Expected output ${local_dst} does not exist"
        res=3
        return 0
    fi

    # Stageout and cleanup
    log "Staging out ${local_dst} -> $dst"
    if test $DRYMODE -eq 0 ; then
        xrdcp -p $local_dst $dst
    fi
    log "Removing ${local_rootfile} and ${local_dst}"
    if test $DRYMODE -eq 0 ; then
        rm $local_dst
        rm $local_rootfile
    fi
    res=0
    }

treemaker(){
    local workdir="$PWD/wd$(date +%s)"
    log "Entering $workdir"
    if test $DRYMODE -eq 0 ; then
        mkdir $workdir
        cd $workdir
    fi

    extract_opt "treemakertarball" $@ ; local treemaker_tarball=$res
    extract_opt "nperjob" $@ ; local nperjob=$res
    extract_opt "infile" $@ ; local infile="$res"
    if is-not-remote "$infile"; then
        infile="$(fullpath $infile)"
    else
        log "Copying $infile -> infile.txt"
        if test $DRYMODE -eq 0 ; then
            xrdcp $infile "infile.txt"
        fi
        infile="$PWD/infile.txt"
    fi

    local dstdir="TREEMAKER_$(date +%b%d)"
    extract_opt_optional "dst" $@
    if test ! -z $res; then dstdir=$res ; fi

    # Get procid
    if test $DRYMODE -eq 0 ; then
        getkey procid ; local procid="$res"
    else
        local procid=3 # Fake procid for testing
    fi

    log "Copying and extracting $treemaker_tarball -> $workdir"
    if test $DRYMODE -eq 0 ; then
        xrdcp $treemaker_tarball .
        tar xf CMSSW_*.tar.gz
        rm CMSSW_*.tar.gz
    fi
    local cmsswdir="$workdir/CMSSW_10_6_29_patch1"

    log "CMS env setup..."
    if test $DRYMODE -eq 0 ; then
        cd CMSSW_10_6_29_patch1/src
        scram b ProjectRename
        cmsenv
        cd TreeMaker/Production/test
    fi
    log "Now in $PWD"

    nrows $infile ; local n_rootfiles=$res
    local i_start=$((procid*nperjob+1)) # start at row 1
    local i_end=$(((procid+1)*nperjob))

    log "Start processing $nperjob rootfiles, i_start=$i_start to i_end=$i_end from $n_rootfiles rootfiles in total"
    local rootfile
    for i in $( seq $i_start $i_end ) ; do
        if test $i_end -gt $n_rootfiles; then
            log "Reached end of rootfiles"
            break
        fi
        getrow $infile $i ; rootfile="$res"
        process_rootfile $rootfile $dstdir
        local exitcode=$res
        log "Exitcode $exitcode for $rootfile"
    done
    res=0
    }


# ______________________________________________________________________________________
# Job script

make_dst(){
    # Formats destination dir, outstep, and part number into a full path.
    # Echoes result.
    local dstdir=$(strip_slash $1) ; shift 1
    local outstep=${1//step_/} ; shift 1 # Remove the "step_" prefix
    local physics=("$@")
    limited_outstring "${physics[@]}"; local physdirname=$res
    echo "$dstdir/$outstep/$physdirname/${physics[6]}_n${physics[7]}.root"
    }

svjprod(){
    local workdir="$PWD/wd$(date +%s)"
    log "Entering $workdir"
    if test $DRYMODE -eq 0 ; then
        mkdir $workdir
        cd $workdir
    fi

    local inrootfile="dummy"

    extract_opt "dst" $@ ; local dstdir=$res
    extract_opt "svjprodtarball" $@ ; local svjprod_tarball=$res
    interpret_args $@ ; local physics=("${res[@]}")

    # Add procid to the part number
    if test $DRYMODE -eq 0 ; then
        getkey procid ; local procid="$res"
    else
        local procid=3 # Fake procid for testing
    fi
    physics[6]=$((physics[6]+procid))

    log "$(print_physics "${physics[@]}")"

    # ____________________________________
    # Setup CMSSWs

    log "Copying and extracting $svjprod_tarball -> $workdir"
    if test $DRYMODE -eq 0 ; then
        xrdcp $svjprod_tarball .
        tar xf CMSSW_*.tar.gz
        rm CMSSW_*.tar.gz
    fi
    local cmsswdir_noHLT="$workdir/CMSSW_10_6_29_patch1"

    # The CMSSW dir for HLT differs per year
    local cmsswdir_HLT
    if test ${physics[5]} -eq 2018 ; then
        cmsswdir_HLT="$workdir/HLT/CMSSW_10_2_16_UL"
    elif test ${physics[5]} -eq 2017 ; then
        cmsswdir_HLT="$workdir/HLT/CMSSW_9_4_14_UL_patch1"
    else
        cmsswdir_HLT="$workdir/HLT/CMSSW_8_0_33_UL"
    fi
    log "Using CMSSW $cmsswdir_noHLT"
    log "Using CMSSW $cmsswdir_HLT for HLT only"

    # ____________________________________
    # Check if there is a previous result available to start from

    local steps=("step0_GRIDPACK" "step_LHE-GEN" "step_SIM" "step_DIGI" "step_HLT" "step_RECO" "step_MINIAOD")
    local n_steps=${#steps[@]}
    local i_step_initial=1

    for i in $(seq $((n_steps-1)) -1 1) ; do
        local dst=$(make_dst $dstdir ${steps[$i]} "${physics[@]}")
        if remote-exists $dst ; then
            log "Found previously saved result $dst; skipping preceding steps"
            inrootfile=$dst
            i_step_initial=$((i+1))
            break
        fi
    done

    if test $i_step_initial -eq $n_steps ; then
        log "Final step already done; nothing to do here."
        return 0
    fi

    # ____________________________________
    # Run the steps

    local exitcode=0
    local cmsswdir
    for i in $(seq $i_step_initial $((n_steps-1))) ; do
        local t_start_step=$(date +%s.%N)
        local prev_step=${steps[$((i-1))]}
        local step=${steps[$i]}

        if streq $step "step_HLT"; then
            cmsswdir=$cmsswdir_HLT
        else
            cmsswdir=$cmsswdir_noHLT
        fi
        
        # Execute the step
        # Somewhat silly way to capture the exitcode while set -e is activated
        if runstep $cmsswdir $prev_step $step $inrootfile "${physics[@]}"; then
            local exitcode=$?
        else
            local exitcode=$?
        fi

        local expected_outfile=$res
        local runtime_step=$(echo "$(date +%s.%N) - $t_start_step" | bc)
        log "Step $step took $runtime_step seconds"

        # Exit gracefully on errors
        if test $exitcode -ne 0 ; then
            log "Step $step failed"
            if test $i -gt $i_step_initial ; then
                # If some new output was achieved, save that
                local dst=$(make_dst $dstdir $prev_step "${physics[@]}")
                log "Saving result from previous step; Copying $inrootfile -> $dst"
                if test $DRYMODE -eq 0 ; then xrdcp $inrootfile $dst ; fi
            fi
            break
        fi

        # Can safely remove the input rootfile now
        if test -f "$inrootfile"; then
            rm $inrootfile || true # Don't crash if can't remove it
        fi

        # Always stageout the last step
        if test $i -eq $((n_steps-1)) ; then
            local dst=$(make_dst $dstdir $step "${physics[@]}")
            log "Staging out $expected_outfile -> $dst"
            if test $DRYMODE -eq 0 ; then xrdcp $expected_outfile $dst ; fi
        fi

        # This step's outfile becomes the next step's infile
        inrootfile=$expected_outfile
    done

    # Return exitcode via $res
    res="$exitcode"
    }


# ______________________________________________________________________________________
# Main

main(){
    echo "Redirecting stderr -> stdout from here on out"
    exec 2>&1
    set -e
    echo "hostname: $(hostname)"
    echo "date:     $(date)"
    echo "pwd:      $(pwd)"
    echo "Initial ls -al:"
    ls -al
    export VO_CMS_SW_DIR=/cvmfs/cms.cern.ch/
    source /cvmfs/cms.cern.ch/cmsset_default.sh
    echo "---------------------------------------------------"
    local tstart=$(date +%s.%N)

    extract_opt_optional "dry" $@
    if test ! -z $res; then export DRYMODE=$res ; fi

    local script="$1"; shift 1
    res=""
    if test -z "$script" ; then
        error "Provide a command as the first argument (svjprod or treemaker)"
    elif streq "$script" "svjprod"; then
        svjprod $@
    elif streq "$script" "treemaker"; then
        treemaker $@
    elif streq "$script" "ls"; then
        remote-ls-wildcard $@
    else
        error "Invalid command: $script"
    fi
    local exitcode="$res"


    echo "---------------------------------------------------"
    echo "Job finished with exitcode $exitcode"
    echo "hostname: $(hostname)"
    echo "date:     $(date)"
    echo "pwd:      $(pwd)"
    echo "Final ls -al:"
    ls -al
    local runtime=$(echo "$(date +%s.%N) - $tstart" | bc)
    local runtime_hours=$( echo "$runtime / 3600." | bc -l )
    echo "Total runtime: $runtime seconds / $runtime_hours hours"
    }

# Allow the code to be sourced without running anything
if strneq "$1" "source"; then
    main $@
fi