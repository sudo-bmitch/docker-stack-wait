# Docker Stack Wait

Waits for a docker stack deploy to complete.

Example Usage:

`docker-stack-wait.sh $stack_name`

Help output:

```bash
$ ./docker-stack-wait.sh -h
docker-stack-wait.sh [opts] stack_name
  -h:     this help message
  -s sec: frequency to poll service state (default 5 sec)
  -t sec: timeout to stop waiting
```

## Usage as container

```bash
$ docker run --rm -it \
           -v `pwd`/docker-compose.yml:/docker-compose.yml \
           -v /var/run/docker.sock:/var/run/docker.sock \
           simplificator/docker-stack-wait $STACK_NAME
```

or with an alias

```bash
$ alias docker-stack-wait='docker run --rm -i -v `pwd`/docker-compose.yml:/docker-compose.yml -v /var/run/docker.sock:/var/run/docker.sock simplificator/docker-stack-wait'
```

The respective container is available on [Docker Hub](https://hub.docker.com/r/simplificator/docker-stack-wait) and built with [Docker Hub Automated Builds](https://docs.docker.com/docker-hub/builds/).

