# Docker Stack Wait

Waits for a docker stack deploy to complete.

Example Usage:

`docker-stack-wait.sh $stack_name`

Help output:

```bash
$ ./docker-stack-wait.sh -h
docker-stack-wait.sh [opts] stack_name
  -f filter: only wait for services matching filter, may be passed multiple
             times, see docker stack services for the filter syntax
  -h:        this help message
  -n name:   only wait for specific service names, overrides any filters,
             may be passed multiple times, do not include the stack name prefix
  -r:        treat a rollback as successful
  -s sec:    frequency to poll service state (default 5 sec)
  -t sec:    timeout to stop waiting
```

## Usage as container

An image is available at:

- Docker Hub: `sudobmitch/docker-stack-wait`
- GHCR: `ghcr.io/sudo-bmitch/docker-stack-wait`

To use this image, you will need to mount the docker socket:

```bash
$ docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  sudobmitch/docker-stack-wait $stack_name
```

or with an alias

```bash
$ alias docker-stack-wait='docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \
  sudobmitch/docker-stack-wait'
```

## Filter Examples

The `-n` and `-f` options allow to select a subset of the services in a stack.
With the following compose yml file:

```yaml
version: '3.7'

services:
  normal:
    image: busybox
    command: /bin/sh -c ":>/healthy; tail -f /dev/null"
    deploy:
      labels:
        deploy.wait: "true"
        deploy.quick: "true"
    healthcheck:
      test: /bin/sh -c "[ -f /healthy ] && exit 0 || exit 1"
      interval: 15s
      start_period: 60s
      retries: 3

  slow:
    image: busybox
    command: /bin/sh -c "sleep 50; :>/healthy; tail -f /dev/null"
    deploy:
      labels:
        deploy.wait: "true"
    healthcheck:
      test: /bin/sh -c "[ -f /healthy ] && exit 0 || exit 1"
      interval: 15s
      start_period: 60s
      retries: 3

  tooslow:
    image: busybox
    command: /bin/sh -c "sleep 300; :>/healthy; tail -f /dev/null"
    deploy:
      labels:
        deploy.wait: "false"
    healthcheck:
      test: /bin/sh -c "[ -f /healthy ] && exit 0 || exit 1"
      interval: 15s
      start_period: 60s
      retries: 3
```

We can wait for only the first two services using labels:

```bash
docker-stack-wait.sh -f label=deploy.wait=true waittest
```

Or by waiting on individual service names:

```bash
docker-stack-wait.sh -n normal -n slow waittest
```

If you deploy a stack using multiple compose files, you can wait for the
services in a single compose file using the following example that uses
`docker-compose` to generate a list of services from one file:

```bash
wait_args=""
for arg in $(docker-compose -f docker-compose.yml config --services 2>/dev/null); do
  wait_args="${wait_args:+${wait_args} }-n $arg"
done
docker-stack-wait.sh $wait_args waittest
```
