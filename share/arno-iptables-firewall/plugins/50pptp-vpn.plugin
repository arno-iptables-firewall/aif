# ------------------------------------------------------------------------------
#               -= Arno's iptables firewall - PPTP VPN plugin =-
#
PLUGIN_NAME="PPTP VPN plugin"
PLUGIN_VERSION="1.00 BETA"
PLUGIN_CONF_FILE="pptp-vpn.conf"
#
# Last changed          : February 21, 2011
# Requirements          : AIF 2.0.0+
# Comments              : This plugin adds all required rules for using a PPTP Server.
#
# Author                : (C) Copyright 2011 by Lonnie Abelbeck & Arno van Amersfoort
# Homepage              : http://rocky.eld.leidenuniv.nl/
# Email                 : a r n o v a AT r o c k y DOT e l d DOT l e i d e n u n i v DOT n l
#                         (note: you must remove all spaces and substitute the @ and the .
#                         at the proper locations!)
# ------------------------------------------------------------------------------
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
# ------------------------------------------------------------------------------

# Plugin start function
plugin_start()
{
  local host net eif ppp_ifs="" IFS

  iptables -N PPTP_VPN_INPUT 2>/dev/null
  iptables -F PPTP_VPN_INPUT

  iptables -N PPTP_VPN_FORWARD_IN 2>/dev/null
  iptables -F PPTP_VPN_FORWARD_IN

  iptables -N PPTP_VPN_FORWARD_OUT 2>/dev/null
  iptables -F PPTP_VPN_FORWARD_OUT

  IFS=' ,'
  for eif in $EXT_IF; do
    case $eif in
      ppp+)
        echo "${INDENT}ERROR: Cannot distinguish between external and PPTP-VPN 'ppp+' interfaces."
        echo "${INDENT}       ${PLUGIN_NAME} functionally is disabled."
        return 0
        ;;
      ppp[0-9]*)
        ppp_ifs="$ppp_ifs${ppp_ifs:+ }$eif"
        ;;
    esac
  done
  
  # Setup PPTP VPN rules
  if [ -n "$ppp_ifs" ]; then
    echo "${INDENT}Excluding external interfaces '$ppp_ifs' from PPTP VPN"
    IFS=' ,'
    for eif in $ppp_ifs; do
      iptables -A PPTP_VPN_INPUT -i $eif -j RETURN
      iptables -A PPTP_VPN_FORWARD_IN -i $eif -j RETURN
      iptables -A PPTP_VPN_FORWARD_OUT -o $eif -j RETURN
    done
  fi
  if [ -n "$PPTP_VPN_ALLOW_HOSTS" ]; then
    echo "${INDENT}Allowing PPTP VPN packets to hosts: $PPTP_VPN_ALLOW_HOSTS"
    IFS=' ,'
    for host in $PPTP_VPN_ALLOW_HOSTS; do
      iptables -A PPTP_VPN_INPUT -d $host -j ACCEPT
      iptables -A PPTP_VPN_FORWARD_IN -d $host -j ACCEPT
      iptables -A PPTP_VPN_FORWARD_OUT -s $host -j ACCEPT
    done
  fi
  if [ -n "$PPTP_VPN_DENY_HOSTS" ]; then
    echo "${INDENT}Denying PPTP VPN packets to hosts: $PPTP_VPN_DENY_HOSTS"
    IFS=' ,'
    for host in $PPTP_VPN_DENY_HOSTS; do
      if [ "$PPTP_VPN_DENY_LOG" = "1" ]; then
        iptables -A PPTP_VPN_INPUT -d $host -m limit --limit 3/m -j LOG \
                 --log-level $LOGLEVEL --log-prefix "AIF:PPTP-VPN denied: "
        iptables -A PPTP_VPN_FORWARD_IN -d $host -m limit --limit 3/m -j LOG \
                 --log-level $LOGLEVEL --log-prefix "AIF:PPTP-VPN denied: "
        iptables -A PPTP_VPN_FORWARD_OUT -s $host -m limit --limit 3/m -j LOG \
                 --log-level $LOGLEVEL --log-prefix "AIF:PPTP-VPN denied: "
      fi
      iptables -A PPTP_VPN_INPUT -d $host -j DROP
      iptables -A PPTP_VPN_FORWARD_IN -d $host -j DROP
      iptables -A PPTP_VPN_FORWARD_OUT -s $host -j DROP
    done
  fi
  # Default policy, allow all the rest
  iptables -A PPTP_VPN_INPUT -j ACCEPT
  iptables -A PPTP_VPN_FORWARD_IN -j ACCEPT
  iptables -A PPTP_VPN_FORWARD_OUT -j ACCEPT

  # Filter ppp+ traffic related to the PPTP VPN
  if [ -n "$PPTP_VPN_NETS" ]; then
    echo "${INDENT}Applying rules for PPTP VPN nets $PPTP_VPN_NETS"
    IFS=' ,'
    for net in $PPTP_VPN_NETS; do
      # Adjust spoof check
      iptables -I SPOOF_CHK -i ppp+ -s $net -j RETURN
      
      # Insert rule in the INPUT chain
      iptables -A INPUT -i ppp+ -s $net -j PPTP_VPN_INPUT
      
      # Insert rules in the FORWARD chain
      iptables -A FORWARD -i ppp+ -s $net -j PPTP_VPN_FORWARD_IN
      iptables -A FORWARD -o ppp+ -d $net -j PPTP_VPN_FORWARD_OUT
    done
  fi

  echo "${INDENT}Allowing internet hosts $PPTP_VPN_TUNNEL_HOSTS to access the PPTP VPN service"
  IFS=' ,'
  for host in $(ip_range "$PPTP_VPN_TUNNEL_HOSTS"); do
    iptables -A EXT_INPUT_CHAIN -p gre -s $host -j ACCEPT
    iptables -A EXT_INPUT_CHAIN -p tcp --dport 1723 -s $host -j ACCEPT
  done
  
  return 0
}


# Plugin restart function
plugin_restart()
{

  # Skip plugin_stop on a restart
  plugin_start

  return 0
}


# Plugin stop function
plugin_stop()
{

  iptables -F PPTP_VPN_INPUT
  iptables -X PPTP_VPN_INPUT 2>/dev/null

  iptables -F PPTP_VPN_FORWARD_IN
  iptables -X PPTP_VPN_FORWARD_IN 2>/dev/null

  iptables -F PPTP_VPN_FORWARD_OUT
  iptables -X PPTP_VPN_FORWARD_OUT 2>/dev/null

  return 0
}


# Plugin status function
plugin_status()
{
  return 0
}


# Check sanity of eg. environment
plugin_sanity_check()
{
  # Sanity check
  if [ -z "$PPTP_VPN_TUNNEL_HOSTS" ]; then
    printf "\033[40m\033[1;31m${INDENT}ERROR: The plugin config file is not properly set!\033[0m\n" >&2
    return 1
  fi

  return 0
}


############
# Mainline #
############

# Check where to find the config file
CONF_FILE=""
if [ -n "$PLUGIN_CONF_PATH" ]; then
  CONF_FILE="$PLUGIN_CONF_PATH/$PLUGIN_CONF_FILE"
fi

# Preinit to success:
PLUGIN_RET_VAL=0

# Check if the config file exists
if [ ! -e "$CONF_FILE" ]; then
  printf "NOTE: Config file \"$CONF_FILE\" not found!\n        Plugin \"$PLUGIN_NAME v$PLUGIN_VERSION\" ignored!\n" >&2
else
  # Source the plugin config file
  . "$CONF_FILE"

  if [ "$ENABLED" = "1" -a "$PLUGIN_CMD" != "stop-restart" ] ||
     [ "$ENABLED" = "0" -a "$PLUGIN_CMD" = "stop-restart" ] ||
     [ -n "$PLUGIN_LOAD_FILE" -a "$PLUGIN_CMD" = "stop" ] ||
     [ -n "$PLUGIN_LOAD_FILE" -a "$PLUGIN_CMD" = "status" ]; then
    # Show who we are:
    echo "${INDENT}$PLUGIN_NAME v$PLUGIN_VERSION"

    # Increment indention
    INDENT="$INDENT "

    # Only proceed if environment ok
    if ! plugin_sanity_check; then
      PLUGIN_RET_VAL=1
    else
      case $PLUGIN_CMD in
        start|'') plugin_start; PLUGIN_RET_VAL=$? ;;
        restart ) plugin_restart; PLUGIN_RET_VAL=$? ;;
        stop|stop-restart) plugin_stop; PLUGIN_RET_VAL=$? ;;
        status  ) plugin_status; PLUGIN_RET_VAL=$? ;;
        *       ) PLUGIN_RET_VAL=1; printf "\033[40m\033[1;31m${INDENT}ERROR: Invalid plugin option \"$PLUGIN_CMD\"!\033[0m\n" >&2 ;;
      esac
    fi
  fi
fi
