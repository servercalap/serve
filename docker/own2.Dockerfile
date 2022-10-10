ARG BASE_IMAGE=nvidia/cuda:11.6.0-cudnn8-runtime-ubuntu20.04

FROM ubuntu:focal-20201106 as ubuntubase 
ENV PYTHONUNBUFFERED TRUE

RUN --mount=type=cache,id=apt-dev,target=/var/cache/apt \
    apt-get update && \
    apt remove python-pip  python3-pip && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    ca-certificates \
    wget \
    curl \
    g++ \
    sudo \
    git \
    htop \
    vim \
    && rm -rf /var/lib/apt/lists/*

RUN echo 'alias python=python3' >> ~/.bashrc
RUN echo 'alias pip=pip3' >> ~/.bashrc


#     openjdk-17-jdk \

FROM ubuntubase AS builderbase

RUN wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    bash Miniconda3-latest-Linux-x86_64.sh -b -p /home/$USERNAME/miniconda3 && \
    rm Miniconda3-latest-Linux-x86_64.sh

ENV PATH=/home/$USERNAME/miniconda3/bin:${PATH}
RUN conda update -y conda && \
# Create serve environment
    conda create --name serve python=3.8 && \
    conda init bash && \
    echo "conda activate serve" >> /home/$USERNAME/.bashrc
SHELL ["conda", "run", "-n", "serve", "/bin/bash", "-c"]

# CUDA and Torch setup
RUN export USE_CUDA=1
ARG CUDA_VERSION="cu116"
ARG TORCH_VER="1.12.1"
ARG TORCH_VISION_VER="0.13.1"

# install torch related
RUN python -m pip install -U pip setuptools && \
    conda install pytorch torchvision cudatoolkit=11.3 -c pytorch && \
    conda install -c conda-forge captum && \
    conda install -c pytorch torchserve torch-model-archiver torch-workflow-archiver && \
    conda install -c conda-forge faiss-gpu && \
    conda install -c conda-forge albumentations && \
    conda clean -afy && \
    python -m pip install nvgpu

RUN conda-pack -n serve -o /tmp/env.tar && \
  mkdir /venv && cd /venv && tar xf /tmp/env.tar && \
  rm /tmp/env.tar

# We've put venv in same path it'll be in final image,
# so now fix up paths:
RUN /venv/bin/conda-unpack


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

COPY  --chown=model-server --from=builderbase /venv /venv
ENV PATH="/venv/bin:$PATH"
COPY dockerd-entrypoint.sh /usr/local/bin/dockerd-entrypoint.sh
RUN chmod +x /usr/local/bin/dockerd-entrypoint.sh \
&& chown -R model-server /home/model-server

COPY config.properties /home/model-server/config.properties
RUN mkdir /home/model-server/model-store && chown -R model-server /home/model-server/model-store

EXPOSE 8080 8081 8082 7070 7071

USER model-server
WORKDIR /home/model-server
ENV TEMP=/home/model-server/tmp
ENTRYPOINT ["/usr/local/bin/dockerd-entrypoint.sh"]
CMD ["serve"]
