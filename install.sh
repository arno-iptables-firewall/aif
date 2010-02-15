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
ln -sv /usr/local/share/arno-iptables-firewall/traffic-accounting-show /usr/local/sbin/traffic-accounting-show

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

if get_user_yn "Do you want to run the configuration script (Y/N)?" "y"; then
  ./configure.sh
fi
 
echo ""
echo "-------------------------------------------------------------------------------"
echo "** NOTE: You can now (manually) start the firewall by executing              **"
echo "**       \"/etc/init.d/arno-iptables-firewall start\"                          **"
echo "**       It is recommended however to first review the settings in           **"
echo "**       /etc/arno-iptables-firewall/firewall.conf!                          **"

exit 0
