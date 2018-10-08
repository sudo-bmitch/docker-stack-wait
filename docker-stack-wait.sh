#!/bin/sh

# By: Brandon Mitchell <public@bmitch.net>
# License: MIT
# Source repo: https://github.com/sudo-bmitch/docker-stack-wait

opt_h=0
opt_s=5
opt_t=3600
start_epoc=$(date +%s)

usage() {
  echo "$(basename $0) [opts] stack_name"
  echo "  -h:     this help message"
  echo "  -s sec: frequency to poll service state (default $opt_s sec)"
  echo "  -t sec: timeout to stop waiting"
  [ "$opt_h" = "1" ] && exit 0 || exit 1
}
check_timeout() {
  # timeout when a timeout is defined and we will exceed the timeout after the
  # next sleep completes
  if [ "$opt_t" -gt 0 ]; then
    cur_epoc=$(date +%s)
    cutoff_epoc=$(expr ${start_epoc} + $opt_t - $opt_s)
    if [ "$cur_epoc" -gt "$cutoff_epoc" ]; then
      echo "Error: Timeout exceeded"
      exit 1
    fi
  fi
}
service_state() {
  # output the state when it changes from the last state for the service
  service=$1
  # strip any invalid chars from service name for caching state
  service_safe=$(echo "$service" | sed 's/[^A-Za-z0-9_]/_/g')
  state=$2
  if eval [ \"\$cache_${service_safe}\" != \"\$state\" ]; then
    echo "Service $service is $state"
    eval cache_${service_safe}=\"\$state\"
  fi
}

while getopts 'h' opt; do
  case $opt in
    h) opt_h=1;;
    s) opt_s="$OPTARG";;
    t) opt_t="$OPTARG";;
  esac
done
shift $(expr $OPTIND - 1)

if [ $# -ne 1 -o "$opt_h" = "1" -o "$opt_s" -le "0" ]; then
  usage
fi

stack_name=$1

# 0 = running, 1 = success, 2 = error
done=0
while [ "$done" != "1" ]; do
  done=1
  for service_id in $(docker stack services -q "${stack_name}"); do
    service_done=1
    service=$(docker service inspect --format '{{.Spec.Name}}' "$service_id")
    replicas=$(docker service ls --format '{{.Replicas}}' --filter "id=$service_id")
    current=$(echo "$replicas" | cut -d/ -f1)
    target=$(echo "$replicas" | cut -d/ -f2)
    if [ "$current" != "$target" ]; then
      service_state "$service" "replicating $replicas"
      done=0
      service_done=0
    fi
    if [ $service_done != 0 ]; then
      # hardcode a "new" state when UpdateStatus is not defined
      state=$(docker service inspect -f '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{else}}new{{end}}' "$service_id")
      service_state "$service" "$state"
      if [ "$state" = "paused" ]; then
        # cannot complete the deployment with an update paused
        # only change to error state when no other updates are still running
        if [ "$done" != "0" ]; then
          done=2
        fi
        service_done=2
      elif [ "$state" != "new" -a "$state" != "completed" ]; then
        done=0
        service_done=0
      fi
    fi
  done
  if [ "$done" = "2" ]; then
    echo "Error: Deployment will not complete"
    exit 1
  fi
  if [ "$done" != "1" ]; then
    check_timeout
    sleep "${opt_s}"
  fi
done
 
