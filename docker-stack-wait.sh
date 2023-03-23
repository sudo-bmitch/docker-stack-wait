#!/bin/sh

# By: Brandon Mitchell <public@bmitch.net>
# License: MIT
# Source repo: https://github.com/sudo-bmitch/docker-stack-wait

set -e
trap "{ exit 1; }" TERM INT
opt_h=0
opt_r=0
opt_p=0
opt_s=5
opt_t=3600
start_epoc=$(date +%s)
cmd_min_timeout=15

usage() {
  echo "$(basename $0) [opts] stack_name"
  echo "  -f filter: only wait for services matching filter, may be passed multiple"
  echo "             times, see docker stack services for the filter syntax"
  echo "  -h:        this help message"
  echo "  -n name:   only wait for specific service names, overrides any filters,"
  echo "             may be passed multiple times, do not include the stack name prefix"
  echo "  -p lines:  print last n lines of relevant service logs at end"
  echo "             passed to the '--tail' option of docker service logs"
  echo "  -r:        treat a rollback as successful"
  echo "  -s sec:    frequency to poll service state (default $opt_s sec)"
  echo "  -t sec:    timeout to stop waiting"
  [ "$opt_h" = "1" ] && exit 0 || exit 1
}

check_timeout() {
  # timeout when a timeout is defined and we will exceed the timeout after the
  # next sleep completes
  if [ "$opt_t" -gt 0 ]; then
    cur_epoc=$(date +%s)
    cutoff_epoc=$(expr ${start_epoc} + $opt_t - $opt_s)
    if [ "$cur_epoc" -gt "$cutoff_epoc" ]; then
      echo "ERROR: Timeout exceeded"
      print_service_logs
      exit 1
    fi
  fi
}

cmd_with_timeout() {
  # run a command that will not exceed the timeout
  # there is a minimum time all commands are given
  if [ "$opt_t" -gt 0 ]; then
    cur_epoc=$(date +%s)
    remain_timeout=$(expr ${start_epoc} + ${opt_t} - ${cur_epoc})
    if [ "${remain_timeout}" -lt "${cmd_min_timeout}" ]; then
      remain_timeout=${cmd_min_timeout}
    fi
    timeout ${remain_timeout} "$@"
  else
    "$@"
  fi
}

get_service_ids() {
  if [ -n "$opt_n" ]; then
    service_list=""
    for name in $opt_n; do
      service_list="${service_list:+${service_list} }${stack_name}_${name}"
    done
    docker service inspect --format '{{.ID}}' ${service_list}
  else
    docker stack services ${opt_f} -q "${stack_name}"
  fi
}

service_state() {
  # output the state when it changes from the last state for the service
  service=$1
  # strip any invalid chars from service name for caching state
  service_safe=$(echo "$service" | sed 's/[^A-Za-z0-9_]/_/g')
  state=$2
  if eval [ \"\$cache_${service_safe}\" != \"\$state\" ]; then
    echo "INFO: Service $service state: $state"
    eval cache_${service_safe}=\"\$state\"
  fi
}

print_service_logs() {
  if [ "$opt_p" != "0" ]; then
    echo "INFO: Retrieving last $opt_p service log lines..."
    service_ids=$(get_service_ids)
    for service_id in ${service_ids}; do
      cmd_with_timeout docker service logs --tail $opt_p "$service_id"
    done
  fi
}

while getopts 'f:hn:p:rs:t:' opt; do
  case $opt in
    f) opt_f="${opt_f:+${opt_f} }-f $OPTARG";;
    h) opt_h=1;;
    n) opt_n="${opt_n:+${opt_n} } $OPTARG";;
    p) opt_p="$OPTARG";;
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

echo "INFO: Waiting for stack $stack_name deployment..."

# 0 = running, 1 = success, 2 = error
stack_done=0
while [ "$stack_done" != "1" ]; do
  stack_done=1

  # run get_service_ids outside of the for loop to catch errors
  service_ids=$(get_service_ids)


  if [ -z "${service_ids}" ]; then
    echo "ERROR: no services found" >&2
    exit 1
  fi

  for service_id in ${service_ids}; do
    service_done=0 # unknown
    service=$(docker service inspect --format '{{.Spec.Name}}' "$service_id")

    # hardcode a "unknown" state when UpdateStatus is not defined
    state=$(docker service inspect -f '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{else}}unknown{{end}}' "$service_id")

    if [ $state == "unknown" ]; then # Corner case for first stack deployments https://github.com/moby/moby/issues/28012
      # Checking task status 
      if [[  $(docker service ps --format '{{ .CurrentState }}' $service_id | grep "Failed")  != "" ]]; then 
        state="failed"
      elif [[  $(docker service ps --format '{{ .CurrentState }}' $service_id | grep "Running")  != "" ]]; then 
        state="unknown" # set to unknown as we override state        
      elif [[  $(docker service ps --format '{{ .CurrentState }}' $service_id | grep "Complete")  != "" ]]; then 
        state="completed"
      # else is not needed as we cover the replica count outisde this corner case    
      fi    
    fi

    case "$state" in
      failed|paused|rollback_paused)
        service_done=2
        docker service ps --format 'ERROR: {{ .Name }} {{ .CurrentState }}: {{ .Error }}' $service_id  | grep "Failed"
        ;;
      rollback_completed)
        if [ "$opt_r" = "0" ]; then
          service_done=2
        fi
        ;;
      deployed|completed)
        service_done=1
        ;;
      *)
        # any other state is unknown, not necessarily finished
        replicas=$(docker service ls --format '{{.Replicas}}' --filter "id=$service_id" | cut -d' ' -f1)
        current=$(echo "$replicas" | cut -d/ -f1)
        target=$(echo "$replicas" | cut -d/ -f2)
        service_done=0
        if [ "$current" != "$target" ]; then
          state="$replicas"
          service_done=0
        else
          state="deployed"
          service_done=1
        fi

        ;;        
    esac   

    service_state "$service" "$state"
 
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
    echo "ERROR: This deployment has failed"
    print_service_logs
    exit 1
  elif [ "$stack_done" != "1" ]; then
    check_timeout
    sleep "${opt_s}"
  else
    echo "INFO: This deployment has succeed"
  fi
done

print_service_logs
