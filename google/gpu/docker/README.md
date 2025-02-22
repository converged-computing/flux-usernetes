# Docker

Note that for this build I retrieved the data from the "latest" (2 years old) image, and pushed it to an artifact on a GPU machine to pull down to my CPU machine, and then could build the container here with the data. Figuring out the format (organization) was hard because I went down the wrong path of not realizing that it also checks the content digests, and I had the data in the correct organization:

```console
data/
└── FashionMNIST
    └── raw
        ├── t10k-images-idx3-ubyte
        ├── t10k-images-idx3-ubyte.gz
        ├── t10k-labels-idx1-ubyte
        ├── t10k-labels-idx1-ubyte.gz
        ├── train-images-idx3-ubyte
        ├── train-images-idx3-ubyte.gz
        ├── train-labels-idx1-ubyte
        └── train-labels-idx1-ubyte.gz
```

but the content digests were wrong. To test this, I shelled into the container, unzipped the python egg, found the source code for mnist.py, and realized what it was doing. Then I just needed to update to use latest for this build:

```
REPOSITORY                                                                                        TAG               DIGEST                                                                    IMAGE ID       CREATED         SIZE
kubeflowkatib/pytorch-mnist                                                                       latest            sha256:eb09bd9c9c101df4bba0c8c924d73813cbf93a956a53a656a7e30e4bab5b8797   28382eee2f03   2 years ago     1.88GB
```

Instead of what I originally tested with, an older tag.

```
REPOSITORY                                                                                        TAG               DIGEST                                                                    IMAGE ID       CREATED         SIZE
kubeflowkatib/pytorch-mnist                                                                       v1beta1-45c5727   sha256:5164399299fc6ceebcdfa0df5b303a2d63c05776188f55a336c5d3514a4e3227   699d6906496b   3 years ago     2.8GB
```

The container build here matches the data to the version of the software.

```console
docker build -t ghcr.io/converged-computing/pytorch-mnist:fashion .
docker push ghcr.io/converged-computing/pytorch-mnist:fashion 
```

The reason we want to have the data already in the container is to avoid time it takes to download it (or errors, as I ran into).
