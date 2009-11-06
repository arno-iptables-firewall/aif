#!/bin/sh

MY_VERSION="1.0c"

# ------------------------------------------------------------------------------------------
#                           -= Arno's iptables firewall =-
#               Single- & multi-homed firewall script with DSL/ADSL support
#
#                           ~ In memory of my dear father ~
#
# (C) Copyright 2001-2009 by Arno van Amersfoort
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

check_binary()
{
  if ! which "$1" >/dev/null 2>&1; then
    printf "\033[40m\033[1;31mERROR: Binary \"$1\" does not exist or is not executable!\033[0m\n" >&2
    printf "\033[40m\033[1;31m       Please, make sure that it is (properly) installed!\033[0m\n" >&2
    exit 2
  fi
}

sanity_check()
{
  # root check
  if [ "$(id -u)" != "0" ]; then
    printf "\033[40m\033[1;31mERROR: Root check FAILED (you MUST be root to use this script)! Quitting...\033[0m\n" >&2
    exit 1
  fi

  check_binary awk
  check_binary tr
  check_binary ifconfig
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
  check_binary iptables
}


copy_ask_if_exist()
{
  if [ -z "$(find "$1" -type f)" ]; then
    echo "ERROR: Missing source file(s) \"$1\""
    exit 2
  fi

  unset IFS
  for source in `find "$1" -type f`; do
    fn="$(echo "$source" |sed "s,^$1/,,")"
    if [ -z "$fn" ]; then
      target="$2/$(basename "$1")"
    else
      target="$2/$fn"
    fi

    if [ -e "$target" ]; then
      # Ignore files that are the same in the target
      if ! diff "$source" "$target" >/dev/null; then
        printf "* File \"$target\" already exists. Overwrite(Y/N)? "

        read C
        if [ "$C" != "y" ] && [ "$C" != "Y" ]; then
          echo " No. Skipped..."
          continue;
        fi
        echo " Yes"
      else
        echo "Target file \"$target\" is the same as source. Skipping."
        continue;
      fi
    fi

    # copy file & create backup of old file if exists
    if ! cp -bv "$source" "$target"; then
      echo "ERROR: Copy error of \"$source\" to \"$target\"!"
      exit 3
    fi

    chown 0:0 "$target"
  done

  return 0
}


copy_skip_if_exist()
{
  if [ -z "$(find "$1" -type f)" ]; then
    echo "ERROR: Missing source file(s) \"$1\""
    exit 2
  fi

  unset IFS
  for source in `find $1 -type f`; do
    fn="$(echo "$source" |sed "s,^$1/,,")"
    if [ -z "$fn" ]; then
      target="$2/$(basename "$1")"
    else
      target="$2/$fn"
    fi

    if [ -e "$target" ]; then
      echo "* File \"$target\" already exists. Skipping..."
      return 1
    fi

    if ! cp -v "$source" "$target"; then
      echo "ERROR: Copy error of \"$source\" to \"$target!\""
      exit 3
    fi

    chown 0:0 "$target"
  done

  return 0
}


copy_overwrite()
{
  if [ -z "$(find "$1" -type f)" ]; then
    echo "ERROR: Missing source file(s) \"$1\""
    exit 2
  fi

  unset IFS
  for source in `find $1 -type f`; do
    fn="$(echo "$source" |sed "s,^$1/,,")"
    if [ -z "$fn" ]; then
      target="$2/$(basename "$1")"
    else
      target="$2/$fn"
    fi

    if ! cp -fv "$source" "$target"; then
      echo "ERROR: Copy error of \"$source\" to \"$target\"!"
      exit 3
    fi

    chown 0:0 "$target"
  done

  return 0
}


change_conf_var()
{
  if [ -n "$3" ]; then
    cat "$1" |sed -e "s~^$2=.*$~$2=\"$3\"~" -e "s~^#$2=.*$~$2=\"$3\"~" >|/tmp/aif_conf.tmp
    mv -f /tmp/aif_conf.tmp "$1"
  fi
}


get_conf_var()
{
  printf "$1"

  read answer

  if [ -z "$answer" ]; then
    echo "$4"
    change_conf_var "$2" "$3" "$4"
  else
    change_conf_var "$2" "$3" "$answer"
  fi

  return 0
}


get_user_yn()
{
  printf "$1"

  read answer

  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    echo " Yes"
    return 0
  fi

  if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
    echo " No"
    return 1
  fi

  # Fallback to default
  if [ "$2" = "y" ]; then
    echo " Yes"
    return 0
  else
    echo " No"
    return 1
  fi
}


setup_conf_file()
{
  # Create backup of old config
  cp -fvb /etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall.conf.bak

  printf "We will now setup the most basic settings of the firewall\n\n"

  get_conf_var "What is your external interface (aka. internet interface) (multiple interfaces should be comma separated)? " /etc/arno-iptables-firewall/firewall.conf "EXT_IF" ""

  if get_user_yn "Does your external interface get its IP through DHCP? (Y/N) " "y"; then
    change_conf_var /etc/arno-iptables-firewall/firewall.conf "EXT_IF_DHCP_IP" "1"
  fi

  if get_user_yn "Do you want to be pingable from the internet? (Y/N) "; then
    change_conf_var /etc/arno-iptables-firewall/firewall.conf "OPEN_ICMP" "1"
  fi

  get_conf_var "Which TCP ports do you want to allow from the internet? (ie. 22=SSH, 80=HTTP, etc.) (comma separate multiple ports)? " /etc/arno-iptables-firewall/firewall.conf "OPEN_TCP" ""
  get_conf_var "Which UDP ports do you want to allow from the internet? (ie. 53=DNS, etc.)  (comma separate multiple ports)? " /etc/arno-iptables-firewall/firewall.conf "OPEN_UDP" ""

  if get_user_yn "Do you have an internal(aka LAN) interface that you want to setup? (Y/N) " "n"; then
    get_conf_var "What is your internal interface (aka. LAN interface)? " /etc/arno-iptables-firewall/firewall.conf "INT_IF" ""
    get_conf_var "What is your internal net? (ie. 192.168.1.0/24)? " /etc/arno-iptables-firewall/firewall.conf "INTERNAL_NET" ""

    if get_user_yn "Do you want to enable NAT for your internal net? (Y/N) " "y"; then
      change_conf_var /etc/arno-iptables-firewall/firewall.conf "NAT" "1"
    fi
  fi

  if get_user_yn "Do you want the init script to be verbose (print out what it's doing)? (Y/N) " "n"; then
    change_conf_var /etc/init.d/arno-iptables-firewall "VERBOSE" "1"
  fi

  # Set the correct permissions on the config file
  chmod 755 /etc/init.d/arno-iptables-firewall 
  chown 0:0 /etc/arno-iptables-firewall/firewall.conf /etc/init.d/arno-iptables-firewall
  chmod 600 /etc/arno-iptables-firewall/firewall.conf
}


# main line:
AIF_VERSION="$(grep "MY_VERSION=" ./bin/arno-iptables-firewall |sed -e "s/^MY_VERSION=\"//" -e "s/\"$//")"

printf "\033[40m\033[1;32mArno's Iptables Firewall Script v$AIF_VERSION\033[0m\n"
printf "Install Script v$MY_VERSION\n"
echo "-------------------------------------------------------------------------------"

sanity_check;

# We want to run in the dir the install script is in
cd "$(dirname $0)"

printf "Continue install (Y/N)? "
read C
if [ "$C" != "y" ] && [ "$C" != "Y" ]; then
  echo " No. Install aborted"
  exit 1
fi
echo " Yes"

copy_overwrite ./bin/ /usr/local/sbin/

mkdir -pv /usr/local/share/arno-iptables-firewall
mkdir -pv /usr/local/share/arno-iptables-firewall/plugins
copy_overwrite ./share/arno-iptables-firewall/ /usr/local/share/arno-iptables-firewall/
#copy_overwrite ./share/arno-iptables-firewall/plugins/ /usr/local/share/arno-iptables-firewall/plugins/

mkdir -pv /usr/local/share/man/man1
mkdir -pv /usr/local/share/man/man8
gzip -c -v ./share/man/man8/arno-iptables-firewall.8 >/usr/local/share/man/man8/arno-iptables-firewall.8.gz
gzip -c -v ./share/man/man1/arno-fwfilter.1 >/usr/local/share/man/man8/arno-fwfilter.1.gz

mkdir -pv /etc/arno-iptables-firewall
copy_ask_if_exist ./etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/
cp -fv ./etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/firewall.conf.dist
copy_skip_if_exist ./etc/arno-iptables-firewall/custom-rules /etc/arno-iptables-firewall/
#cp -fv ./etc/arno-iptables-firewall/firewall.conf.example /etc/arno-iptables-firewall/

mkdir -pv /etc/arno-iptables-firewall/plugins
copy_ask_if_exist ./etc/arno-iptables-firewall/plugins/ /etc/arno-iptables-firewall/plugins/

copy_ask_if_exist ./etc/init.d/arno-iptables-firewall /etc/init.d/

echo ""
echo "** Install done **"
echo ""

if get_user_yn "Do you want to start the firewall at boot (via /etc/init.d/)? (Y/N) " "y"; then
  if [ -d /etc/rcS.d ]; then
    if [ -n "$(find /etc/rcS.d/ -name "*arno-iptables-firewall")" ]; then
      echo "Startup symlink seems to already exist in /etc/rcS.d so skipping that"
    else
      ln -sv /etc/init.d/arno-iptables-firewall /etc/rcS.d/S38arno-iptables-firewall
    fi
  else
    if [ -n "$(find /etc/rc2.d/ -name "*arno-iptables-firewall")" ]; then
      echo "Startup symlink seems to already exist in /etc/rc2.d so skipping that"
    else
      ln -sv /etc/init.d/arno-iptables-firewall /etc/rc2.d/S38arno-iptables-firewall
    fi
  fi
fi

if diff ./etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/firewall.conf >/dev/null; then
  if get_user_yn "Your firewall.conf is not configured yet.\nDo you want me to help you setup a basic configuration? (Y/N) " "y"; then
    setup_conf_file;
  else
    echo "*Skipped"
  fi
else
  echo "Your firewall.conf looks already customized so skipping basic configuration..."
fi

echo ""
echo "-------------------------------------------------------------------------------"
echo "** NOTE: You can now (manually) start the firewall by executing              **"
echo "**       \"/etc/init.d/arno-iptables-firewall start\"                          **"
echo "**       It is recommended however to first review the settings in           **"
echo "**       /etc/arno-iptables-firewall/firewall.conf!                          **"

exit 0

