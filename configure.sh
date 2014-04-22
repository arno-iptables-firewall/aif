#!/bin/bash

MY_VERSION="1.02d"

# -----------------------------------------------------------------------------
#                       -= Arno's iptables firewall =-
#         Single- & multi-homed firewall script with DSL/ADSL support
#
#                       ~ In memory of my dear father ~
#
# (C) Copyright 2001-2014 by Arno van Amersfoort & Lonnie Abelbeck
# Homepage : http://rocky.eld.leidenuniv.nl/
# Email    : a r n o v a AT r o c k y DOT e l d DOT l e i d e n u n i v DOT n l
#              (note: you must remove all spaces and substitute the @ and the .
#              at the proper locations!)
# -----------------------------------------------------------------------------

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# -----------------------------------------------------------------------------

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
  
  check_command_error sed
  check_command_error chmod
  check_command_error chown
  check_command_error cp
  check_command_error ln
  check_command_error rm
  check_command_error ip
  check_command_error cut
  check_command_error diff
  check_command_error sed
}


change_conf_var()
{
  if ! grep -E -q "^#?$2=" "$1"; then
    printf "\033[40m\033[1;31mERROR: Variable \"$2\" not found in \"$1\". File is probably outdated!\033[0m\n" >&2
  elif [ -n "$3" ]; then
    sed -i -e "s~^#\?$2=.*$~$2=\"$3\"~" "$1"
  else
    # If no value is entered, then remove (unless commented) previously
    # set values: this is to prevent e.g. ports from remaining open, or
    # internal interfaces from remaining enabled with NAT.
    sed -i -e "s~^$2=.*$~$2=\"\"~" "$1"
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
    else
#      echo "(None)"
      # This allows the function change_conf_var to remove previously set
      # values (e.g. for open ports) which are not specified anymore.
      change_conf_var "$2" "$3" ""
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

  if [ "$answer" = "y" -o "$answer" = "Y" ]; then
    echo "Yes"
    return 0
  fi

  if [ "$answer" = "n" -o "$answer" = "N" ]; then
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
      change_conf_var "$FIREWALL_CONF" "EXT_IF" "$EXT_IF"

      break
    fi
  done
  
  if get_user_yn "Does your external interface get its IP through DHCP (Y/N)?" "n"; then
    change_conf_var "$FIREWALL_CONF" "EXT_IF_DHCP_IP" "1"
  else
    change_conf_var "$FIREWALL_CONF" "EXT_IF_DHCP_IP" "0"
  fi

  if get_user_yn "Do you want to enable IPv6 support (Y/N)?" "y"; then
    change_conf_var "$FIREWALL_CONF" "IPV6_SUPPORT" "1"
  else
    change_conf_var "$FIREWALL_CONF" "IPV6_SUPPORT" "0"
  fi
  
  if get_user_yn "Do you want to be pingable from the internet (Y/N)?" "n"; then
    change_conf_var "$FIREWALL_CONF" "OPEN_ICMP" "1"
  else
    change_conf_var "$FIREWALL_CONF" "OPEN_ICMP" "0"
  fi
  
  get_conf_var "Which TCP ports do you want to allow from the internet? (e.g. 22=SSH, 80=HTTP, etc.) (comma separate multiple ports)?" "$FIREWALL_CONF" "OPEN_TCP" ""
  get_conf_var "Which UDP ports do you want to allow from the internet? (e.g. 53=DNS, etc.) (comma separate multiple ports)?" "$FIREWALL_CONF" "OPEN_UDP" ""

  if get_user_yn "Do you have an internal(aka LAN) interface that you want to setup (Y/N)?" "n"; then
    while true; do
      printf "What is your internal interface (aka. LAN interface)? "
      read INT_IF
      
      if verify_interfaces $INT_IF; then
        change_conf_var "$FIREWALL_CONF" "INT_IF" "$INT_IF"
      
        local INTERNAL_NET=""
        local INT_NET_BCAST_ADDRESS=""
        IFS=' ,'
        for interface in $INT_IF; do
          INTERNAL_NET="$INTERNAL_NET${INTERNAL_NET:+ }$(get_network_ipv4_address_mask $interface)"
          INT_NET_BCAST_ADDRESS="$INT_NET_BCAST_ADDRESS${INT_NET_BCAST_ADDRESS:+ }$(get_network_ipv4_broadcast $interface)"
        done
      
        if [ -n "$INTERNAL_NET" ] && [ -n "$INT_NET_BCAST_ADDRESS" ]; then
          echo "* Auto-detected internal IPv4 net(s): $INTERNAL_NET"
          echo "* Auto-detected internal IPv4 broadcast address(es): $INT_NET_BCAST_ADDRESS"
          
          change_conf_var "$FIREWALL_CONF" "INTERNAL_NET" "$INTERNAL_NET"
          change_conf_var "$FIREWALL_CONF" "INT_NET_BCAST_ADDRESS" "$INT_NET_BCAST_ADDRESS"

          if get_user_yn "Do you want to enable NAT/masquerading for your internal subnet (Y/N)?" "n"; then
            change_conf_var "$FIREWALL_CONF" "NAT" "1"
            change_conf_var "$FIREWALL_CONF" "NAT_INTERNAL_NET" '\$INTERNAL_NET'
          else
            change_conf_var "$FIREWALL_CONF" "NAT" "0"
          fi
        fi

        break
      fi
    done
  else
    # If no internal interface is entered, then remove previously
    # set values related to it.
    change_conf_var "$FIREWALL_CONF" "INT_IF" ""
    change_conf_var "$FIREWALL_CONF" "INTERNAL_NET" ""
    change_conf_var "$FIREWALL_CONF" "INT_NET_BCAST_ADDRESS" ""
    change_conf_var "$FIREWALL_CONF" "NAT" "0"
  fi
  
  # Set the correct permissions on the config file
  chmod 755 /etc/init.d/arno-iptables-firewall
  chown 0:0 "$FIREWALL_CONF" /etc/init.d/arno-iptables-firewall
  chmod 600 "$FIREWALL_CONF"
}


# main line:
AIF_VERSION="$(grep "MY_VERSION=" ./bin/arno-iptables-firewall |sed -e "s/^MY_VERSION=\"//" -e "s/\"$//")"

printf "\033[40m\033[1;32mArno's Iptables Firewall Script v$AIF_VERSION\033[0m\n"
printf "Configure Script v$MY_VERSION\n"
echo "-------------------------------------------------------------------------------"

sanity_check;

# Remove any symlinks in rc*.d out of the way
rm -f /etc/rc*.d/*arno-iptables-firewall

if get_user_yn "Do you want to start the firewall at boot (via /etc/init.d/) (Y/N)?" "y"; then
  if [ -d /etc/rcS.d ]; then
    ln -sv /etc/init.d/arno-iptables-firewall /etc/rcS.d/S41arno-iptables-firewall
  else
    ln -sv /etc/init.d/arno-iptables-firewall /etc/rc2.d/S11arno-iptables-firewall
  fi

  # Check for insserv. Used for dependency based booting on e.g. Debian
  INSSERV="$(find_command /sbin/insserv)"
  if [ -n "$INSSERV" ]; then
    "$INSSERV" arno-iptables-firewall
  fi
fi

if get_user_yn "Do you want the init script to be verbose (print out what it's doing) (Y/N)?" "n"; then
  change_conf_var /etc/init.d/arno-iptables-firewall "VERBOSE" "1"
else
  change_conf_var /etc/init.d/arno-iptables-firewall "VERBOSE" "0"
fi

if diff ./etc/arno-iptables-firewall/firewall.conf "$FIREWALL_CONF" >/dev/null; then
  if get_user_yn "Your firewall.conf is not configured yet.\nDo you want me to help you setup a basic configuration (Y/N)?" "y"; then
    setup_conf_file;
  else
    echo "* Skipped"
  fi
else
  if get_user_yn "Your firewall.conf looks already customized.\nModify configuration (Y/N)?" "n"; then
    setup_conf_file;
  else
    echo "* Skipped"
  fi
fi

echo ""
echo "** Configuration done **"
echo ""

exit 0

