### Workflow images
This directory contains docker images used to execute workflow for installing k8s on top of RPi4.

**Note**: `00-base` is using an armv7 alpine image, which means it won't be possible to build it on standard `x86_64` machine. 
In case it is impossible to build them locally, you can pull them from dockerhub:
```bash
docker pull ...
.. to be implemented
```