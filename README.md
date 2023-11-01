# Boosted SVJ signal production script

This repo contains a single script, [svj.sh](svj.sh), which can run the boosted SVJ signal production chain.

## Using the script

These scripts should work both on an interactive node as well as in a job.

### Gridpack to MINIAOD

```bash
bash svj.sh \
    # Tell the script to run the gridpack -> MINIAOD chain, "svj"
    svj \  
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

SVJPRODTARBALL = root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/svjproductiontarballs/CMSSW_10_6_29_patch1_svjprod_el7_2018UL_cms-svj_Run2_UL_withHLT_996c8dc_Jan18.tar.gz
DST = root://cmseos.fnal.gov//store/user/lpcdarkqcd/boosted/my_output/

# Set physics model parameters
NEVENTS = 500
PART = 100000
MZ = 450
RINV = 0.2
MDARK = 10
ALPHA = peak
NEVENTS = 500
PART = 10000

args = svj mz=$(MZ) rinv=$(RINV) mdark=$(MDARK) alpha=$(ALPHA) part=$(PART) nevents=$(NEVENTS) dst=$(DST) svjprodtarball=$(SVJPRODTARBALL)

# Queue 100 jobs. The ProcID of the job will be added to the 'part' number to ensure the jobs are unique.
queue 100

# Submit another 100 jobs, with the same physics model parameters except mdark:
MDARK = 5
queue 100
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
