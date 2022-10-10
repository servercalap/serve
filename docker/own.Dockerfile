FROM continuumio/miniconda3 AS build
RUN --mount=type=cache,id=apt-dev,target=/var/cache/apt \
    apt-get update && \
    apt remove python-pip  python3-pip && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    ca-certificates
RUN conda update -y conda && \
# Create serve environment
    conda create --name serve python=3.8
#    conda init bash \
#&& \
 #    echo "conda activate serve" >> /home/$USERNAME/.bashrc \
SHELL ["conda", "run", "-n", "serve", "/bin/bash", "-c"]
RUN conda install -c conda-forge conda-pack && \
     conda install -c conda-forge numpy && \
     conda install pytorch torchvision cudatoolkit=11.3 -c pytorch && \
     conda install -c conda-forge captum && \
     conda install -c pytorch torchserve torch-model-archiver torch-workflow-archiver && \
     conda install -c conda-forge faiss-gpu && \
     conda install -c conda-forge albumentations && \
     conda clean -afy && \
     python -m pip install nvgpu \




FROM nvidia/cuda:11.6.0-cudnn8-runtime-ubuntu20.04 AS compile-image
ENV PYTHONUNBUFFERED TRUE

RUN --mount=type=cache,id=apt-dev,target=/var/cache/apt \
    apt-get update && \
    apt remove python-pip  python3-pip && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    ca-certificates \
    wget \
    curl \
    g++ \
    openjdk-17-jdk \
    sudo \
    git \
    htop \
    vim \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash -g root -G sudo -u $USERID $USERNAME && \
    adduser $USERNAME sudo && \
    echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
USER model-server
WORKDIR /home/model-server

COPY --from=build /venv /venv


COPY dockerd-entrypoint.sh /usr/local/bin/dockerd-entrypoint.sh

RUN chmod +x /usr/local/bin/dockerd-entrypoint.sh \
    && chown -R model-server /home/model-server

COPY config.properties /home/model-server/config.properties
RUN mkdir /home/model-server/model-store && chown -R model-server /home/model-server/model-store

EXPOSE 8080 8081 8082 7070 7071

USER model-server
WORKDIR /home/model-server
ENTRYPOINT ["/usr/local/bin/dockerd-entrypoint.sh"]
CMD ["serve"]