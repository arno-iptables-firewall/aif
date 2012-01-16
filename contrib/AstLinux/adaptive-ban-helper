#!/bin/bash

LOCKFILE="/var/lock/aif_adaptive_ban.lock"

ARGSFILE="/var/tmp/aif_adaptive_ban.args"

TEMPFILE="/var/tmp/aif_adaptive_ban.temp"

start_run()
{
  local num file time count arg args argstime=0 filetime=0 ARGS IFS
  
  ARGS="$@"
  
  # Robust 'bash' method of creating/testing for a lockfile
  if ! ( set -o noclobber; echo "$$" > "$LOCKFILE" ) 2>/dev/null; then
    echo "$ARGS" > "$ARGSFILE"
    echo "adaptive-ban-helper: already running, lockfile \"$LOCKFILE\" exists, process id: $(cat "$LOCKFILE")."
    return 9
  fi
  
  trap 'rm -f "$LOCKFILE" "$ARGSFILE" "$TEMPFILE"; exit $?' INT TERM EXIT
  
  echo "$ARGS" > "$ARGSFILE"
  
  # Delay to allow firewall script to complete
  idle_wait 45
  
  while [ -f "$ARGSFILE" ]; do
  
    # Check whether chains exists
    if ! check_for_chain ADAPTIVE_BAN_CHAIN; then
      log_msg "ADAPTIVE_BAN_CHAIN does not exist"
      break
    fi
    if ! check_for_chain ADAPTIVE_BAN_DROP_CHAIN; then
      log_msg "ADAPTIVE_BAN_DROP_CHAIN does not exist"
      break
    fi
    
    ARGS="$(cat "$ARGSFILE")"
    
    file=""
    args=""
    num=0
    unset IFS
    for arg in $ARGS; do
      num=$((num+1))
      case "$num" in
        1) file="$arg" ;;
        2) time="$arg" ;;
        3) count="$arg" ;;
        *) args="${args}${args:+ }$arg" ;;
      esac
    done
    
    if [ ! -f "$file" ]; then
      log_msg "Input log file $file does not exist"
      break
    fi
    
    if [ "$filetime" != "$(date -r "$file" "+%s")" -o "$argstime" != "$(date -r "$ARGSFILE" "+%s")" ]; then
      filter "$file" "$count" $args
      
      filetime="$(date -r "$file" "+%s")"
      argstime="$(date -r "$ARGSFILE" "+%s")"
    fi
    
    # Idle - interrupted if ARGSFILE is deleted
    idle_wait $time
  done
  
  rm -f "$LOCKFILE" "$ARGSFILE" "$TEMPFILE"
  trap - INT TERM EXIT
  
  return 0
}

stop()
{

  rm -f "$ARGSFILE"

  # If the background start_run() is in idle_wait() this ensures a clean stop.
  sleep 1
  # If start_run() is not in idle_wait() we deal with that as well.
  # We could loop while LOCKFILE exists, but doesn't seem necessary.
}

status()
{

  echo "  Banned Hosts:"
  echo "  =============================="
  ip4tables -n -L ADAPTIVE_BAN_CHAIN | awk '$1 == "ADAPTIVE_BAN_DROP_CHAIN" { print "  "$4 }'
  if [ "$IPV6_SUPPORT" = "1" ]; then
    ip6tables -n -L ADAPTIVE_BAN_CHAIN | awk '$1 == "ADAPTIVE_BAN_DROP_CHAIN" { print "  "$3 }'
  fi
  echo "  ------------------------------"
  echo ""
  
  echo "  Whitelisted Hosts:"
  echo "  =============================="
  ip4tables -n -L ADAPTIVE_BAN_CHAIN | awk '$1 == "RETURN" { print "  "$4 }'
  if [ "$IPV6_SUPPORT" = "1" ]; then
    ip6tables -n -L ADAPTIVE_BAN_CHAIN | awk '$1 == "RETURN" { print "  "$3 }'
  fi
  echo "  ------------------------------"
  echo ""
}

filter()
{
  local file="$1" count="$2" type types PREFIX HOST IFS
 
  shift 2
  types="$@"
  
  # regex to pull out offending IPv4/IPv6 address
  #
  HOST="([0-9a-fA-F:.]{7,})"

  unset IFS
  for type in $types; do

    # regex match the start of the syslog string
    #
    PREFIX=".*${type}\[[0-9]*]:[[:space:]]*"

    case "$type" in
      sshd) filter_sshd "$file" "$PREFIX" "$HOST"
         ;;
      asterisk) filter_asterisk "$file" "$PREFIX" "$HOST"
         ;;
      lighttpd) filter_lighttpd "$file" "$PREFIX" "$HOST"
         ;;
      mini_httpd) filter_mini_httpd "$file" "$PREFIX" "$HOST"
         ;;
      pptpd) filter_pptpd "$file" "$PREFIX" "$HOST"
         ;;
      *) log_msg "Unsupported type \"$type\""
         continue
         ;;
    esac
    if [ $? -ne 0 ]; then
      log_msg "Filter Error for type \"$type\""
    else
      count_attempts_then_ban "$count" "$type"
    fi
    rm -f "$TEMPFILE"
  done
}

filter_sshd()
{
  local file="$1" PREFIX="$2" HOST="$3"

  sed -n -r -e "s/^${PREFIX}Failed (password|publickey) for .* from ${HOST}( port [0-9]*)?( ssh[0-9]*)?$/\2/p" \
            -e "s/^${PREFIX}[iI](llegal|nvalid) user .* from ${HOST}[[:space:]]*$/\2/p" \
               "$file" >"$TEMPFILE"
}

filter_asterisk()
{
  local file="$1" PREFIX="$2" HOST="$3"

  sed -n -r -e "s/^${PREFIX}NOTICE.* .*: Registration from '.*' failed for '${HOST}' - Wrong password$/\1/p" \
            -e "s/^${PREFIX}NOTICE.* .*: Registration from '.*' failed for '${HOST}' - No matching peer found$/\1/p" \
            -e "s/^${PREFIX}NOTICE.* .*: Registration from '.*' failed for '${HOST}' - Username\/auth name mismatch$/\1/p" \
            -e "s/^${PREFIX}NOTICE.* .*: Registration from '.*' failed for '${HOST}' - Device does not match ACL$/\1/p" \
            -e "s/^${PREFIX}NOTICE.* '${HOST}' - Dialplan Noted Suspicious IP Address$/\1/p" \
            -e "s/^${PREFIX}NOTICE.* ${HOST} failed to authenticate as '.*'$/\1/p" \
            -e "s/^${PREFIX}NOTICE.* .*: No registration for peer '.*' \(from ${HOST}\)$/\1/p" \
            -e "s/^${PREFIX}NOTICE.* .*: Host ${HOST} failed MD5 authentication for '.*' \(.*\)$/\1/p" \
               "$file" >"$TEMPFILE"
}

filter_lighttpd()
{
  local file="$1" PREFIX="$2" HOST="$3"

  sed -n -r -e "s/^${PREFIX}.* password doesn't match for .* IP: ${HOST}[[:space:]]*$/\1/p" \
            -e "s/^${PREFIX}.* get_password failed, IP: ${HOST}[[:space:]]*$/\1/p" \
               "$file" >"$TEMPFILE"
}

filter_mini_httpd()
{
  local file="$1" PREFIX="$2" HOST="$3"

  sed -n -r -e "s/^${PREFIX}${HOST} authentication failure - access denied$/\1/p" \
               "$file" >"$TEMPFILE"
}

filter_pptpd()
{
  local file="$1" PREFIX="$2" HOST="$3" PPP_PREFIX=".*pppd\[[0-9]*]:[[:space:]]*"

  sed -n -r -e "/^${PPP_PREFIX}.* failed CHAP authentication$/ {N;N;N;N;N;N;N;N;N;N;N;N;N;N;N;\
               s/^.*\n${PREFIX}CTRL: Client ${HOST} control connection finished\n.*$/\1/p}" \
               "$file" >"$TEMPFILE"
}

count_attempts_then_ban()
{
  local count="$1" type="$2" line host IFS

  # Remove possible IPv4 port numbers, IPv4:PORT -> IPv4
  sed -i -r -e 's/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):[0-9]+$/\1/' "$TEMPFILE"

  IFS=$'\n'
  for line in $(sort "$TEMPFILE" | uniq -c); do
    if [ "$(echo "$line" | awk '{ print $1; }')" -ge "$count" ]; then
      host="$(echo "$line" | awk '{ print $2; }')"
      ban_host "$host" "$type"
    fi
  done
}

ban_host()
{
  local host="$1" type="$2"

  get_numeric_ip_version "$host"
  case $? in
  4)
    if ! ip4tables -n -L ADAPTIVE_BAN_CHAIN | grep -q " ${host//./\.}[/ ]"; then
      ip4tables -A ADAPTIVE_BAN_CHAIN -s $host -j ADAPTIVE_BAN_DROP_CHAIN
      if [ $? -eq 0 ]; then
        log_msg "Banned IPv4 Host: $host  Filter Type: $type"
      fi
    fi
    ;;
  6)
    if [ "$IPV6_SUPPORT" = "1" ]; then
      if ! ip6tables -n -L ADAPTIVE_BAN_CHAIN | grep -q " ${host}[/ ]"; then
        ip6tables -A ADAPTIVE_BAN_CHAIN -s $host -j ADAPTIVE_BAN_DROP_CHAIN
        if [ $? -eq 0 ]; then
          log_msg "Banned IPv6 Host: $host  Filter Type: $type"
        fi
      fi
    fi
    ;;
  esac
}

idle_wait()
{
  local time="$1" cnt=0

  while [ -f "$ARGSFILE" -a $cnt -lt $time ]; do
    cnt=$((cnt+1))
    sleep 1
  done
}

check_for_chain()
{
  local err

  ip4tables -n -L "$1" >/dev/null 2>&1
  err=$?
  
  if [ "$IPV6_SUPPORT" = "1" -a $err -eq 0 ]; then
    ip6tables -n -L "$1" >/dev/null 2>&1
    err=$?
  fi
  
  return $err
}

ip4tables()
{
  local result retval

  result="$($IP4TABLES "$@" 2>&1)"
  retval=$?
  
  if [ $retval -ne 0 ]; then
    log_msg "$IP4TABLES: ($retval) $result"
  elif [ -n "$result" ]; then
    echo "$result"
  fi

  return $retval
}

ip6tables()
{
  local result retval

  result="$($IP6TABLES "$@" 2>&1)"
  retval=$?
  
  if [ $retval -ne 0 ]; then
    log_msg "$IP6TABLES: ($retval) $result"
  elif [ -n "$result" ]; then
    echo "$result"
  fi

  return $retval
}

get_numeric_ip_version()
{
  case $1 in
  0/0)
    ;;
  [0-9][0-9.][0-9.][0-9.][0-9.]*.*[0-9])
    return 4
    ;;
  [0-9]*.*/*[0-9]|[0-9]/*[0-9]|[1-9][0-9]/*[0-9]|[12][0-9][0-9]/*[0-9])
    return 4
    ;;
  *:*)
    return 6
    ;;
  esac

  return 0
}

log_msg()
{
  logger -t "firewall: adaptive-ban" -p kern.info "$1"
  echo "$1" >&2
}

# main

ACTION="$1"

IP4TABLES="$2"
if [ -z "$IP4TABLES" -o "$IP4TABLES" = "ip4tables" ]; then
  ACTION=""
fi

IP6TABLES="$3"
if [ -z "$IP6TABLES" -o "$IP6TABLES" = "ip6tables" ]; then
  ACTION=""
fi

IPV6_SUPPORT="$4"

shift 4

case $ACTION in

start)
  if [ -z "$1" -o -z "$2" -o -z "$3" -o -z "$4" ]; then
    echo "Usage: adaptive-ban-helper start ip4tables_path ip6tables_path ipv6_flag logfile time count args..."
    exit 1
  fi
  start_run "$@"
  ;;

stop)
  stop
  ;;

status)
  status
  ;;

*)
  echo "Usage: adaptive-ban-helper start|stop|status ip4tables_path ip6tables_path ipv6_flag"
  echo "                           [ logfile time count args... ]"
  exit 1
  ;;
  
esac

