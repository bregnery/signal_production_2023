# Boosted SVJ signal production script

This repo contains a single script, [svj.sh](svj.sh), which can run the boosted SVJ signal production chain.

## Using the script

These scripts should work both on an interactive node as well as in a job.

### Gridpack to MINIAOD

```bash
bash svj.sh \
    # Tell the script to run the gridpack -> MINIAOD chain, "svj"
    svjprod \  
    # Point to the SVJProductions tarball to use
    svjprodtarball=root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/svjproductiontarballs/CMSSW_10_6_29_patch1_svjprod_el7_2018UL_cms-svj_Run2_UL_withHLT_996c8dc_Jan18.tar.gz \ 
    # Set where to store the output files
    dst=root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/my_output/ \
    # Give all the physics options, these are optional.
    mz=450 rinv=0.2 mdark=10 alpha=peak nevents=500 part=1234 year=2018
    # The default physics options are:
    # mz=350 rinv=0.1 mdark=10 alpha=peak year=2018 nevents=10000 part=1
```

### MINIAOD to TreeMaker Ntuple

```bash
bash svj.sh \
    # Tell the script to create the Ntuple from MINIAOD
    treemaker \  
    # Point to the TreeMaker tarball to use
    treemakertarball=root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/svjproductiontarballs/CMSSW_10_6_29_patch1_TreeMaker_Run2_UL_df47918_Sep11.tar.gz \ 
    # Supply a list of MINIAOD root files. Currently only possible via a text file
    infile=my_miniaod_rootfiles.txt \
    # Set where to store the output files.
    # If this is a remote directory, every rootfile in $infile will be copied to it without renaming.
    # If this is a relative path, the substring "MINIAOD" in $infile will be replaced by $dst
    dst=TREEMAKER_test001 \
    # Tell the script how many rootfiles from $infile it should do. The default is 1.
    nperjob=1
```

## Example .jdl files

Here is an example submission file to run the gridpack to miniaod chain:

```
executable = svj.sh
log = htcondor.log
on_exit_hold = (ExitBySignal == true) || (ExitCode != 0)
output = out_$(Year)_$(Month)_$(Day)_$(Cluster)_$(Process).txt
universe = vanilla
args = svjprod mz=$(MZ) rinv=$(RINV) mdark=$(MDARK) alpha=$(ALPHA) part=$(PART) nevents=$(NEVENTS) dst=$(DST) svjprodtarball=$(SVJPRODTARBALL)

SVJPRODTARBALL = root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/svjproductiontarballs/CMSSW_10_6_29_patch1_svjprod_cms-svj_Run2_UL_20231103_withHLT.tar.gz
DST = root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/my_output/

# Set benchmark physics model parameters
NEVENTS = 500
PART = 100000
MZ = 450
RINV = 0.2
MDARK = 10
ALPHA = peak
NEVENTS = 500
PART = 10000

# Queue 100 jobs. The ProcID of the job will be added to the 'part' number to ensure the jobs are unique.
queue 100

# Submit a 1D scan over rinv. Make sure to reset RINV to its benchmark value afterwards.
# 100 jobs per rinv value are submitted.
queue 100 RINV in (0.0,0.05,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0)
RINV = 0.3

# Submit a 1D scan over mdark
queue 100 MDARK in (1,5,10)

# Etc.
```

Here is an example submission file to create TreeMaker ntuples from MINIAOD files:

```
executable = svj.sh
log = htcondor.log
on_exit_hold = (ExitBySignal == true) || (ExitCode != 0)
output = out_$(Year)_$(Month)_$(Day)_$(Cluster)_$(Process).txt
universe = vanilla

TREEMAKERTARBALL = root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/svjproductiontarballs/CMSSW_10_6_29_patch1_TreeMaker_Run2_UL_df47918_Sep11.tar.gz
DST = TREEMAKER_test002
INFILE = root://cmseos.fnal.gov//store/user/myusername/my_miniaod_rootfile.txt
NPERJOB = 25

args = treemaker infile=$(INFILE) nperjob=$(NPERJOB) dst=$(DST) treemakertarball=$(TREEMAKERTARBALL)

# Queue as many jobs as you need to cover all rootfiles in your INFILE.
queue 384
```


## Experimental

A common mishap is that a part of you TreeMaker jobs fail.
In that case, you only want to resubmit jobs for the failed MINIAOD -> TreeMaker cases,
and you need to know which MINIAOD files still need to ntupled.
The script [prep_treemaker_infile.sh](prep_treemaker_infile.sh) is a utility to compute this list:

```bash
bash prep_treemaker_infile.sh \
    dst=TREEMAKER_v01 \
    miniaod=root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/signal_production_2023/MINIAOD/*/*.root \
    > missing.txt
```

The script will subtract all existing ntuples from the list of all needed ntuples, and
return a list of all MINIAOD files that still need to be ntupled.

This script is experimental and will probaby contain some gotcha's.