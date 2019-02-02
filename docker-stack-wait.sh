#!/bin/sh

# By: Brandon Mitchell <public@bmitch.net>
# License: MIT
# Source repo: https://github.com/sudo-bmitch/docker-stack-wait

opt_h=0
opt_r=0
opt_s=5
opt_t=3600
start_epoc=$(date +%s)

usage() {
  echo "$(basename $0) [opts] stack_name"
  echo "  -h:     this help message"
  echo "  -r:     treat a rollback as successful (by default, a rollback indicates failure)"
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
    echo "Service $service state: $state"
    eval cache_${service_safe}=\"\$state\"
  fi
}

while getopts 'hrs:t:' opt; do
  case $opt in
    h) opt_h=1;;
    r) opt_r=1;;
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
stack_done=0
while [ "$stack_done" != "1" ]; do
  stack_done=1
  for service_id in $(docker stack services -q "${stack_name}"); do
    service_done=1
    service=$(docker service inspect --format '{{.Spec.Name}}' "$service_id")

    # hardcode a "new" state when UpdateStatus is not defined
    state=$(docker service inspect -f '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{else}}new{{end}}' "$service_id")

    # check for failed update states
    case "$state" in
      paused|rollback_paused)
        service_done=2
        ;;
      rollback_*)
        if [ "$opt_r" = "0" ]; then
          service_done=2
        fi
        ;;
    esac

    # identify/report current state
    if [ "$service_done" != "2" ]; then
      replicas=$(docker service ls --format '{{.Replicas}}' --filter "id=$service_id")
      current=$(echo "$replicas" | cut -d/ -f1)
      target=$(echo "$replicas" | cut -d/ -f2)
      if [ "$current" != "$target" ]; then
        # actively replicating service
        service_done=0
        state="replicating $replicas"
      fi
    fi
    service_state "$service" "$state"

    # check for states that indicate an update is done
    if [ "$service_done" = "1" ]; then
      case "$state" in
        new|completed|rollback_completed)
          service_done=1
          ;;
        *)
          # any other state is unknown, not necessarily finished
          service_done=0
          ;;
      esac
    fi

    # update stack done state
    if [ "$service_done" = "2" ]; then
      # error condition
      stack_done=2
    elif [ "$service_done" = "0" -a "$stack_done" = "1" ]; then
      # only go to an updating state if not in an error state
      stack_done=0
    fi
  done
  if [ "$stack_done" = "2" ]; then
    echo "Error: This deployment will not complete"
    exit 1
  fi
  if [ "$stack_done" != "1" ]; then
    check_timeout
    sleep "${opt_s}"
  fi
done
 
