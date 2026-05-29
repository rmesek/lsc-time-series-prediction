#!/bin/bash
#SBATCH --job-name=ray-cluster
#SBATCH --nodes=2
#SBATCH --tasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:2
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --partition=plgrid-gpu-v100
#SBATCH --account=plglscclass26-gpu

set -euo pipefail

# 1. Load Environment
module load miniconda3
eval "$(conda shell.bash hook)"
conda activate ray-cluster

# Helper function to find a truly available port safely
get_free_port() {
    local PYTHON_CMD
    if command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
    elif command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    else
        # Fallback if Python is completely unavailable: use shuf but actively verify it's free
        local temp_port
        while true; do
            temp_port=$(shuf -i 10000-65500 -n 1)
            # Use 'ss' to check listening ports. If grep finds nothing, the port is free.
            if ! ss -tuln | grep -q ":$temp_port "; then
                echo "$temp_port"
                return
            fi
        done
    fi
    # Use Python's socket library to ask the OS for a free port
    $PYTHON_CMD -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'
}

# 2. Path Variables (We must keep Ray sockets in local /tmp to avoid path length limits)
export RAY_TMP_DIR="/tmp/ray-${USER}-${SLURM_JOB_ID}"
mkdir -p "$RAY_TMP_DIR"

# 3. Networking
nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)
head_node=${nodes_array[0]}
head_node_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" hostname --ip-address | awk '{print $1}')

# Safely allocate a guaranteed free port
port=$(get_free_port)
export ip_head=$head_node_ip:$port

# 4. Start Ray Head
echo "Starting HEAD at $head_node ($ip_head)"
NUM_GPUS=${SLURM_GPUS_ON_NODE:-1}

srun --nodes=1 --ntasks=1 -w "$head_node" bash -c "
    export RAY_TMP_DIR='$RAY_TMP_DIR'
    ray start --head \
              --node-ip-address='$head_node_ip' \
              --port=$port \
              --num-cpus=${SLURM_CPUS_PER_TASK} \
              --num-gpus=$NUM_GPUS \
              --temp-dir='$RAY_TMP_DIR' \
              --dashboard-host=0.0.0.0 \
              --block
" &

sleep 10 # Allow head node to initialize

# 5. Start Ray Workers
for node_i in "${nodes_array[@]:1}"; do
    echo "Starting WORKER at $node_i"
    
    srun --nodes=1 --ntasks=1 -w "$node_i" bash -c "
        export RAY_TMP_DIR='$RAY_TMP_DIR'
        ray start --address='$ip_head' \
                  --num-cpus=${SLURM_CPUS_PER_TASK} \
                  --num-gpus=$NUM_GPUS \
                  --temp-dir='$RAY_TMP_DIR' \
                  --block
    " &
done

# 6. Start Jupyter Server on the Head Node
# Ensure Jupyter also gets a guaranteed free port
jupyter_port=$(get_free_port)
jupyter_url="http://${head_node_ip}:${jupyter_port}/?token=ray-course"

# Save the connection URL to a file in the current directory
echo "$jupyter_url" > "jupyter-url-${SLURM_JOB_ID}.txt"
echo "Jupyter URL saved to: jupyter-url-${SLURM_JOB_ID}.txt"

# Launch Jupyter directly in the foreground (no srun needed)
export RAY_TMP_DIR=$RAY_TMP_DIR
jupyter notebook \
    --no-browser \
    --port=$jupyter_port \
    --ip=0.0.0.0 \
    --ServerApp.token='ray-course' \
    --notebook-dir=$PWD
