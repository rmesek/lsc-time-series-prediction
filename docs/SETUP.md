## Step 0: Connect to Ares via VS Code
Install the **Remote - SSH** extension by Microsoft in **VS Code**, then:

1. Open the **Command Palette** (`CMD+SHIFT+P`).
2. Search for and select **Remote-SSH: Connect to Host...**.
3. Enter the host address (e.g., `<PLGUSER_NAME>@ares.cyfronet.pl`).
4. (Optional) To simplify future logins, add this entry to your `~/.ssh/config`:
    ```ssh
    Host ares.cyfronet.pl
      AddKeysToAgent yes
      UseKeychain yes
      IdentityFile ~/.ssh/id_ed25519
      ServerAliveInterval 60
    ```

## Step 1: Environment Setup (One-time)
To avoid disk quota issues in your home directory, install the environment on `${SCRATCH}`.
```bash
# Log in to Ares and start a temporary session to build the environment
srun --time=1:00:00 --mem=8G --ntasks 1 --gres=gpu:1 --partition=plgrid-gpu-v100 --account=plglscclass26-gpu --pty /bin/bash

# Load and configure conda
module load miniconda3
conda config --add envs_dirs ${SCRATCH}/.conda/envs
conda config --add pkgs_dirs ${SCRATCH}/.conda/pkgs

# Create Python 3.12 environment
conda create -n ray-cluster python=3.12 jupyter ipykernel -c conda-forge -y
conda activate ray-cluster

# Install Ray (without PyTorch for now)
pip install "ray[default]" pandas numpy

# Register the kernel for Jupyter
python -m ipykernel install --user --name ray-cluster --display-name "Python 3.12 (Ray Cluster)"
exit
```

## Step 2: Create the Multi-Node Ray Launch Script
Create a file named `start-ray.sh` in your home or scratch directory with the following content.
```bash
#!/bin/bash
#SBATCH --job-name=ray-cluster
#SBATCH --nodes=2
#SBATCH --tasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:2
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=plgrid-gpu-v100
#SBATCH --account=plglscclass26-gpu

set -euo pipefail

# 1. Load Environment
module load miniconda3
eval "$(conda shell.bash hook)"
conda activate ray-cluster

# 2. Path Variables (We must keep Ray sockets in local /tmp to avoid path length limits)
export RAY_TMP_DIR="/tmp/ray-${USER}-${SLURM_JOB_ID}"
mkdir -p "$RAY_TMP_DIR"

# 3. Networking
nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)
head_node=${nodes_array[0]}
head_node_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" hostname --ip-address | awk '{print $1}')
port=$(shuf -i 10000-65500 -n 1)
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
jupyter_port=$(shuf -i 8000-9999 -n 1)
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
```

## Step 3: Submit the Job
Use the integrated terminal in VS Code to manage your cluster.

1. Submit the job:
    ```bash
    sbatch start-ray.sh
    ```

2. Check the job status and retrieve the JOB_ID:
    ```bash
    squeue --me
    ```

3. (Optional) Terminate the job when finished:
    ```bash
    scancel <JOB_ID>
    ```

## Step 4: Configure the Jupyter Notebook
Open or create a Jupyter Notebook and connect it to your running Ray cluster:

1. Click **Select Kernel** > **Select Another Kernel...** > **Existing Jupyter Server...**.
2. Retrieve the connection URL from the generated `jupyter-url-<JOB_ID>.txt` file (e.g., `http://172.22.26.1:8423/?token=ray-course`).
3. Paste the URL and select the kernel named **Python 3.12 (Ray Cluster)**.
4. Run the following code in a notebook cell to verify the connection:
    ```python
    import ray
    import os

    ray.shutdown()
    ray.init(address='auto')

    print("Cluster Resources:", ray.cluster_resources())
    print("Nodes in cluster:", len(ray.nodes()))

    ray.shutdown()
    ```

## Step 5: Execute Cells and Access Ray Dashboard
Once your kernel is connected, run the first cell in the notebook. The output will display the internal dashboard URL (e.g., `Connected to Ray cluster. View the dashboard at http://172.22.26.2:8265`).

To view this dashboard on your local machine:

1. In VSCode, open the panel at the bottom and select the **Ports** tab.
2. Click **Forward a Port**.
3. Paste the `<IP>:<PORT>` exactly as it appeared in your cell output (e.g., `172.22.26.2:8265`) and press Enter.
4. Click the local address generated by VSCode (e.g., `http://localhost:8265`) to open the dashboard in your web browser.