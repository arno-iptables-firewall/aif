#!/bin/bash

MY_VERSION="1.02a"

# ------------------------------------------------------------------------------------------
#                           -= Arno's iptables firewall =-
#               Single- & multi-homed firewall script with DSL/ADSL support
#
#                           ~ In memory of my dear father ~
#
# (C) Copyright 2001-2010 by Arno van Amersfoort
# Homepage              : http://rocky.eld.leidenuniv.nl/
# Freshmeat homepage    : http://freshmeat.net/projects/iptables-firewall/?topic_id=151
# Email                 : a r n o v a AT r o c k y DOT e l d DOT l e i d e n u n i v DOT n l
#                         (note: you must remove all spaces and substitute the @ and the .
#                         at the proper locations!)
# ------------------------------------------------------------------------------------------
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# ------------------------------------------------------------------------------------------

# Check if the environment file exists and if so, load it
#########################################################
if [ -f ./share/arno-iptables-firewall/environment ]; then
  . ./share/arno-iptables-firewall/environment
else
  printf "\033[40m\033[1;31mERROR: Could not read environment file ./share/arno-iptables-firewall/environment!\033[0m\n" >&2
  exit 2
fi

# Allow user to override firewall.conf location (undocumented)
FIREWALL_CONF=${1:-/etc/arno-iptables-firewall/firewall.conf}

sanity_check()
{
  # root check
  if [ "$(id -u)" != "0" ]; then
    printf "\033[40m\033[1;31mERROR: Root check FAILED (you MUST be root to use this script)! Quitting...\033[0m\n" >&2
    exit 1
  fi

  check_binary iptables
  check_binary awk
  check_binary tr
  check_binary ip
  check_binary cut
  check_binary uname
  check_binary sed
  check_binary cat
  check_binary date
  check_binary modprobe
  check_binary sysctl
  check_binary head
  check_binary tail
  check_binary wc
  check_binary gzip
  check_binary logger
}


copy_ask_if_exist()
{
  if [ -z "$(find "$1" -type f)" ]; then
    echo "ERROR: Missing source file(s) \"$1\""
    exit 2
  fi

  unset IFS
  for source in `find "$1" -type f`; do
    if [ -d "$2" ]; then
      fn="$(echo "$source" |sed "s,^$1,,")"
      if [ -z "$fn" ]; then
        target="$2$(basename "$1")"
      else
        target="$2$fn"
      fi
    else
      target="$2"
    fi
    
    if [ ! -d "$(dirname $target)" ]; then
      echo "* Target directory $(dirname "$target") does not exist. Skipping copy of $fn"
      continue;
    fi
 
    if [ -f "$source" -a -f "$target" ]; then
      # Ignore files that are the same in the target
      if ! diff "$source" "$target" >/dev/null; then
        printf "File \"$target\" already exists. Overwrite (Y/N)? "

        read -s -n1 C
        if [ "$C" != "y" ] && [ "$C" != "Y" ]; then
          echo "No. Skipped..."
          continue;
        fi
        echo "Yes"
      else
        echo "* Target file \"$target\" is the same as source. Skipping copy of $source"
        continue;
      fi
    fi

    # copy file & create backup of old file if exists
    if ! cp -bv "$source" "$target"; then
      echo "ERROR: Copy error of \"$source\" to \"$target\"!" >&2
      exit 3
    fi

    chown 0:0 "$target"
  done

  return 0
}


copy_skip_if_exist()
{
  if [ -z "$(find "$1" -type f)" ]; then
    echo "ERROR: Missing source file(s) \"$1\"" >&2
    exit 2
  fi

  unset IFS
  for source in `find "$1" -type f`; do
    if [ -d "$2" ]; then
      fn="$(echo "$source" |sed "s,^$1,,")"
      if [ -z "$fn" ]; then
        target="$2$(basename "$1")"
      else
        target="$2$fn"
      fi
    else
      target="$2"
    fi
    
    if [ ! -d "$(dirname $target)" ]; then
      echo "* Target directory $(dirname "$target") does not exist. Skipping copy of $fn"
      continue;
    fi
 
    if [ -f "$target" ]; then
      echo "* File \"$target\" already exists. Skipping copy of $source"
      continue;
    fi

    if ! cp -v "$source" "$target"; then
      echo "ERROR: Copy error of \"$source\" to \"$target!\"" >&2
      exit 3
    fi

    chown 0:0 "$target"
  done

  return 0
}


copy_overwrite()
{
  if [ -z "$(find "$1" -type f)" ]; then
    echo "ERROR: Missing source file(s) \"$1\"" >&2
    exit 2
  fi

  unset IFS
  for source in `find "$1" -type f`; do
    if [ -d "$2" ]; then
      fn="$(echo "$source" |sed "s,^$1,,")"
      if [ -z "$fn" ]; then
        target="$2$(basename "$1")"
      else
        target="$2$fn"
      fi
    else
      target="$2"
    fi

    if [ ! -d "$(dirname $target)" ]; then
      echo "* Target directory $(dirname "$target") does not exist. Skipping copy of $fn"
      continue;
    fi

    if ! cp -fv "$source" "$target"; then
      echo "ERROR: Copy error of \"$source\" to \"$target\"!" >&2
      exit 3
    fi

    chown 0:0 "$target"
  done

  return 0
}


change_conf_var()
{
  if [ -n "$3" ]; then
    sed -i -e "s~^$2=.*$~$2=\"$3\"~" -e "s~^#$2=.*$~$2=\"$3\"~" "$1"
  fi
}


get_conf_var()
{
  printf "$1 "

  read answer

  if [ -z "$answer" ]; then
    if [ -n "$4" ]; then
#      echo "$4"
      change_conf_var "$2" "$3" "$4"
#    else
#      echo "(None)"
    fi
  else
    change_conf_var "$2" "$3" "$answer"
  fi

  return 0
}


get_user_yn()
{
  printf "$1 "

  read -s -n1 answer

  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    echo "Yes"
    return 0
  fi

  if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
    echo "No"
    return 1
  fi

  # Fallback to default
  if [ "$2" = "y" ]; then
    echo "Yes"
    return 0
  else
    echo "No"
    return 1
  fi
}

verify_interfaces()
{
  if [ -z "$1" ]; then
    if ! get_user_yn "No interface(s) specified. These are required! Continue anyway(Y/N)?" "n"; then
      return 1
    fi
  fi
  
  IFS=' ,'
  for interface in $1; do
    if ! check_interface $interface; then
      if ! get_user_yn "Interface \"$interface\" does not exist (yet). Continue anyway(Y/N)?" "n"; then
        return 1
      fi
    fi
  done
  
  return 0
}

setup_conf_file()
{
  # Create backup of old config
  cp -fvb "$FIREWALL_CONF" /etc/arno-iptables-firewall.conf.bak

  printf "We will now setup the most basic settings of the firewall\n\n"

  while true; do
    printf "What is your external (aka. internet) interface (multiple interfaces should be comma separated)? "
    read EXT_IF
    
    if verify_interfaces $EXT_IF; then
      if [ -n "$EXT_IF" ]; then
        change_conf_var "$FIREWALL_CONF" "EXT_IF" "$EXT_IF"
      
        local EXTERNAL_NET=""
        local EXT_NET_BCAST_ADDRESS=""
        IFS=' ,'
        for interface in $EXT_IF; do
          EXTERNAL_NET="$EXTERNAL_NET${EXTERNAL_NET:+ }$(get_network_ipv4_address_mask $interface)"
          EXT_NET_BCAST_ADDRESS="$EXT_NET_BCAST_ADDRESS${EXT_NET_BCAST_ADDRESS:+ }$(get_network_ipv4_broadcast $interface)"
        done
      
        if [ -n "$EXTERNAL_NET" ]; then
          echo "* Auto-detected external net(s): $EXTERNAL_NET"
          change_conf_var "$FIREWALL_CONF" "EXTERNAL_NET" "$EXTERNAL_NET"
        fi
        
        if [ -n "$EXT_NET_BCAST_ADDRESS" ]; then
          echo "* Auto-detected external broadcast address(es): $EXT_NET_BCAST_ADDRESS"
          change_conf_var "$FIREWALL_CONF" "EXT_NET_BCAST_ADDRESS" "$EXT_NET_BCAST_ADDRESS"
        fi
      fi

      break
    fi
  done  
  
  if get_user_yn "Does your external interface get its IP through DHCP (Y/N)?" "y"; then
    change_conf_var "$FIREWALL_CONF" "EXT_IF_DHCP_IP" "1"
  fi

  if get_user_yn "Do you want to be pingable from the internet (Y/N)?"; then
    change_conf_var "$FIREWALL_CONF" "OPEN_ICMP" "1"
  fi

  get_conf_var "Which TCP ports do you want to allow from the internet? (eg. 22=SSH, 80=HTTP, etc.) (comma separate multiple ports)?" "$FIREWALL_CONF" "OPEN_TCP" ""
  get_conf_var "Which UDP ports do you want to allow from the internet? (eg. 53=DNS, etc.) (comma separate multiple ports)?" "$FIREWALL_CONF" "OPEN_UDP" ""

  if get_user_yn "Do you have an internal(aka LAN) interface that you want to setup (Y/N)?" "n"; then
    while true; do
      printf "What is your internal interface (aka. LAN interface)? "
      read INT_IF
      
      if verify_interfaces $INT_IF; then
        if [ -n "$INT_IF" ]; then
          change_conf_var "$FIREWALL_CONF" "INT_IF" "$INT_IF"
        
          local INTERNAL_NET=""
          local INT_NET_BCAST_ADDRESS=""
          IFS=' ,'
          for interface in $INT_IF; do
            INTERNAL_NET="$INTERNAL_NET${INTERNAL_NET:+ }$(get_network_ipv4_address_mask $interface)"
            INT_NET_BCAST_ADDRESS="$INT_NET_BCAST_ADDRESS${INT_NET_BCAST_ADDRESS:+ }$(get_network_ipv4_broadcast $interface)"
          done
        
          if [ -n "$INTERNAL_NET" ]; then
            echo "* Auto-detected internal net(s): $INTERNAL_NET"
            change_conf_var "$FIREWALL_CONF" "INTERNAL_NET" "$INTERNAL_NET"
          fi

          if [ -n "$INT_NET_BCAST_ADDRESS" ]; then
            echo "* Auto-detected external broadcast address(es): $INT_NET_BCAST_ADDRESS"
            change_conf_var "$FIREWALL_CONF" "INT_NET_BCAST_ADDRESS" "$INT_NET_BCAST_ADDRESS"
          fi
          
          if [ -n "$INTERNAL_NET" ]; then
            if get_user_yn "Do you want to enable NAT/masquerading for your internal net (Y/N)?" "n"; then
              change_conf_var "$FIREWALL_CONF" "NAT" "1"
              change_conf_var "$FIREWALL_CONF" "NAT_INTERNAL_NET" '\$INTERNAL_NET'
            fi
          fi
        fi
        break
      fi
    done
  fi
  
  # Set the correct permissions on the config file
  chmod 755 /etc/init.d/arno-iptables-firewall 
  chown 0:0 "$FIREWALL_CONF" /etc/init.d/arno-iptables-firewall
  chmod 600 "$FIREWALL_CONF"
}


# main line:
AIF_VERSION="$(grep "MY_VERSION=" ./bin/arno-iptables-firewall |sed -e "s/^MY_VERSION=\"//" -e "s/\"$//")"

printf "\033[40m\033[1;32mArno's Iptables Firewall Script v$AIF_VERSION\033[0m\n"
printf "Install Script v$MY_VERSION\n"
echo "-------------------------------------------------------------------------------"

sanity_check;

# We want to run in the dir the install script is in
cd "$(dirname $0)"

if ! get_user_yn "Continue install (Y/N)?" "n"; then
  echo "*Install aborted"
  exit 1
fi

copy_overwrite ./bin/ /usr/local/sbin/

mkdir -pv /usr/local/share/arno-iptables-firewall/plugins
copy_overwrite ./share/arno-iptables-firewall/ /usr/local/share/arno-iptables-firewall/

mkdir -pv /usr/local/share/man/man1
mkdir -pv /usr/local/share/man/man8
gzip -c -v ./share/man/man8/arno-iptables-firewall.8 >/usr/local/share/man/man8/arno-iptables-firewall.8.gz
gzip -c -v ./share/man/man1/arno-fwfilter.1 >/usr/local/share/man/man8/arno-fwfilter.1.gz

mkdir -pv /etc/arno-iptables-firewall/plugins
copy_ask_if_exist ./etc/arno-iptables-firewall/plugins/ /etc/arno-iptables-firewall/plugins/

copy_overwrite ./etc/init.d/arno-iptables-firewall /etc/init.d/

copy_overwrite ./etc/arno-iptables-firewall/firewall.conf ./etc/arno-iptables-firewall/firewall.conf.dist
copy_skip_if_exist ./etc/arno-iptables-firewall/custom-rules /etc/arno-iptables-firewall/
copy_ask_if_exist ./etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/

echo ""
echo "** Install done **"
echo ""

# Remove any symlinks in rc*.d out of the way
rm -f /etc/rc*.d/*arno-iptables-firewall 2>/dev/null

if get_user_yn "Do you want to start the firewall at boot (via /etc/init.d/) (Y/N)?" "y"; then
  if [ -d /etc/rcS.d ]; then
    ln -sv /etc/init.d/arno-iptables-firewall /etc/rcS.d/S41arno-iptables-firewall
  else
    ln -sv /etc/init.d/arno-iptables-firewall /etc/rc2.d/S11arno-iptables-firewall
  fi
fi

if diff ./etc/arno-iptables-firewall/firewall.conf "$FIREWALL_CONF" >/dev/null; then
  if get_user_yn "Your firewall.conf is not configured yet.\nDo you want me to help you setup a basic configuration (Y/N)?" "y"; then
    setup_conf_file;
  else
    echo "* Skipped"
  fi
else
  echo "* Your firewall.conf looks already customized so skipping basic configuration..."
fi

if get_user_yn "Do you want the init script to be verbose (print out what it's doing) (Y/N)?" "n"; then
  change_conf_var /etc/init.d/arno-iptables-firewall "VERBOSE" "1"
fi
 
echo ""
echo "-------------------------------------------------------------------------------"
echo "** NOTE: You can now (manually) start the firewall by executing              **"
echo "**       \"/etc/init.d/arno-iptables-firewall start\"                          **"
echo "**       It is recommended however to first review the settings in           **"
echo "**       /etc/arno-iptables-firewall/firewall.conf!                          **"

exit 0

