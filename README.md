# Time Series Prediction with PyTorch
Distributed time series forecasting using PyTorch Forecasting and Ray on the Ares HPC cluster. 

## Setup

See [docs/SETUP.md](docs/SETUP.md) for environment installation, Ray cluster configuration, and execution instructions.

## Theoretical Design and Implementation

The implementation focuses on a **distributed deep learning pipeline** designed to scale time series forecasting across an HPC cluster.

* **Model Architecture:** Utilizes **PyTorch Forecasting** to implement state-of-the-art neural networks (e.g., Temporal Fusion Transformers) optimized for complex seasonality and multi-horizon predictions.
* **Distributed Orchestration:** **Ray** acts as the compute engine, dynamically managing worker nodes and GPU resources within a SLURM-allocated environment to enable parallel training.
* **Execution Workflow:**
    * **Data Preparation:** Generation of synthetic autoregressive data to benchmark model performance.
    * **Cluster Topology:** A head-worker structure where the head node handles global scheduling and the Jupyter interface, while workers execute distributed training shards.
    * **Monitoring:** Real-time tracking of resource utilization and training metrics via the integrated Ray Dashboard.

## Libraries:

* [PyTorch Forecasting](https://pytorch-forecasting.readthedocs.io/en/stable/index.html)
* [Ray by Anyscale](https://www.ray.io/)

## Resources:

* [Introducing PyTorch Forecasting](https://towardsdatascience.com/introducing-pytorch-forecasting-64de99b9ef46/)
* [generate_ar_data](https://pytorch-forecasting.readthedocs.io/en/stable/api/pytorch_forecasting.data.examples.generate_ar_data.html)
* [How to Train Time Series Forecasting Faster using Ray, part 3 of 3](https://medium.com/data-science/faster-time-series-forecasting-with-ray-air-distributed-computing-part-3-of-3-632c96974774)
