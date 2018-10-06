# Docker Stack Wait

Waits for a docker stack deploy to complete.

Example Usage:

`docker-stack-wait.sh $stack_name`

Help output:

```
$ ./docker-stack-wait.sh -h
docker-stack-wait.sh [opts] stack_name
  -h:     this help message
  -s sec: frequency to poll service state (default 5 sec)
  -t sec: timeout to stop waiting
```

