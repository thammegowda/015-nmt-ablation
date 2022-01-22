#!/usr/bin/env bash

#SBATCH --partition=isi --time=0-48:00:00
#SBATCH --mem=60g --ntasks=1 --cpus-per-task=6 --gres=gpu:a40:1
#SBATCH --output=R-%x.out.%j --error=R-%x.err.%j  --export=NONE

# Pipeline script for MT
#
# Author = Thamme Gowda (tg@isi.edu)
# Date = April 3, 2019

#SCRIPTS_DIR=$(dirname "${BASH_SOURCE[0]}")  # get the directory name
#RTG_PATH=$(realpath "${SCRIPTS_DIR}/..")


# used rtg==0.6.0  *(develop branch, unreleased at the time of experiments)
RTG_PATH=/home1/tnarayan/work1/repos/rtg-develop

# Use tmp dir
export RTG_TMP=$TMPDIR
# restrict threads / cpus
export RTG_CPUS=4 #$SLURM_CPUS_ON_NODE
export RTG_CPUS=4 #$SLURM_CPUS_ON_NODE
export OMP_NUM_THREADS=$RTG_CPUS
export MKL_NUM_THREADS=$RTG_CPUS


OUT=
CONF_PATH=
FP16=

#defaults
source ~/.bashrc
CONDA_ENV=rtg-py39     # empty means don't activate environment

# TODO: change this -- point to cuda libs
#export LD_LIBRARY_PATH=~jonmay/cuda-9.0/lib64:~jonmay/cuda/lib64:/usr/local/lib

usage() {
    echo "Usage: $0 -d <exp/dir>
    [-r RTG_PATH (default: $RTG_PATH)]
    [-u update the code, get the latest from $RTG_PATH [default: do not update]
    [-f enable mixed precision training [default: disabled]
    [-e conda_env  default:$CONDA_ENV (empty string disables activation)] " 1>&2;
    exit 1;
}

while getopts ":ud:c:e:p:r:" o; do
    case "${o}" in
        d) OUT=${OPTARG} ;;
        e) CONDA_ENV=${OPTARG} ;;
	u) UPDATE=YES ;;
	r) RTG_PATH=${OPTARG} ;;
	f) FP16="--fp16" ;;
        *) usage ;;
    esac
done


[[ -n $OUT ]] || usage   # show usage and exit

#################


echo "Output dir = $OUT"
[[ -d $OUT ]] || mkdir -p $OUT
OUT=`realpath $OUT`

if [[ ! -f $OUT/rtg.zip  || -n $UPDATE ]]; then
    [[ -f $RTG_PATH/rtg/__init__.py ]] || { echo "Error: RTG_PATH=$RTG_PATH is not valid"; exit 2; }
    echo "Zipping source code from $RTG_PATH to $OUT/rtg.zip"
    OLD_DIR=$PWD
    cd ${RTG_PATH}

    zip -r $OUT/rtg.zip rtg -x "*__pycache__*"
    #[[ -e $OUT/scripts ]] || ln -s ${PWD}/scripts $OUT/scripts  # scripts are needed
    git rev-parse HEAD > $OUT/githead   # git commit message
    cd $OLD_DIR
fi

if [[ -n ${CONDA_ENV} ]]; then
    echo "Activating environment $CONDA_ENV"
    source activate ${CONDA_ENV} || { echo "Unable to activate $CONDA_ENV" ; exit 3; }
fi


export PYTHONPATH=$OUT/rtg.zip

# copy this script for reproducibility
cp "${BASH_SOURCE[0]}"  $OUT/job.sh.bak
echo  "`date`: Starting pipeline... $OUT"


n_gpus=$(echo ${CUDA_VISIBLE_DEVICES} | tr ',' '\n' | wc -l)
master_addr="127.0.0.1"
master_port=29600
master_port=$(python -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')  # get an unused port
tot_nodes=1
rank=0


#cmd="python -m rtg.pipeline $OUT $CONF_ARG --fp16 --gpu-only"
cmd="python -m rtg.distrib.launch -N $tot_nodes -r $rank -P $n_gpus -G 1 --master-addr $master_addr --master-port $master_port"
cmd="$cmd -m rtg.pipeline $OUT -G $FP16"
echo "RUN:: $(hostname):: $cmd"
eval $cmd
      
if eval ${cmd}; then
    echo "`date` :: Done"
else
    echo "Error: exit status=$?" >&2
    exit 2
fi
