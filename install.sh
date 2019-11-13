#!/bin/bash

MY_VERSION="1.12"

# ------------------------------------------------------------------------------------------
#                         -= Arno's Iptables Firewall(AIF) =-
#              Single- & multi-homed firewall script with DSL/ADSL support
#
#                           ~ In memory of my dear father ~
#
# (C) Copyright 2001-2019 by Arno van Amersfoort
# Homepage              : https://rocky.eld.leidenuniv.nl/
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

EOL='
'

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

  check_command_error iptables
  if [ "$IPV6_DETECTED" = "1" ]; then
    check_command_error ip6tables
  fi
  check_command_error awk
  check_command_error tr
  check_command_error ip
  check_command_error cut
  check_command_error uname
  check_command_error sed
  check_command_error cat
  check_command_error date
  check_command_error modprobe
  check_command_error sysctl
  check_command_error head
  check_command_error tail
  check_command_error wc
  check_command_error gzip
  check_command_error logger
  check_command_error chmod
  check_command_error chown
  check_command_error find
  check_command_error cp
  check_command_error rm
  check_command_error mkdir
  check_command_error rmdir
  check_command_error ln
  check_command_warning dig nslookup
}


shell_diff()
{
  local FILE1_DATA="$(cat "$1")"
  local FILE2_DATA="$(cat "$2")"

  if [ "$FILE1_DATA" != "$FILE2_DATA" ]; then
    # If mismatch, check whether it's only the comments that differ
    FILE1_DATA="$(echo "$FILE1_DATA" |sed 's/#.*//')"
    FILE2_DATA="$(echo "$FILE2_DATA" |sed 's/#.*//')"

    if [ "$FILE1_DATA" = "$FILE2_DATA" ]; then
      return 1 # Only comments differ
    fi

    return 2 # Full mismatch
  fi

  return 0 # Match
}


copy_ask_if_exist()
{
  local diff_retval=-1
  local retval

  if [ -z "$(find "$1" -type f)" ]; then
    echo "ERROR: Missing source file(s) \"$1\""
    exit 2
  fi

  unset IFS
  for source in `find "$1" -type f |grep -v -e '/\.svn/' -e '/\.git/'`; do
    if echo "$2" |grep -q '/$'; then
      fn="$(echo "$source" |sed "s,^$1,,")"
      if [ -z "$fn" ]; then
        target="${2}$(basename "$1")"
      else
        target="${2}${fn}"
      fi
      target_dir="$2"
    else
      target="$2"
      target_dir="$(dirname "$2")"
    fi

    if [ ! -d "$target_dir" ]; then
      printf "\033[40m\033[1;31m* WARNING: Target directory $target_dir does not exist. Skipping copy of $source!\033[0m\n" >&2
      continue
    fi

    if [ -f "$source" -a -f "$target" ]; then
      # Ignore files that are the same in the target
      shell_diff "$source" "$target"
      diff_retval=$? # 0 = full match, 1 = match (excluding comments), 2 = full mismatch (including comments)

      if [ $diff_retval -eq 2 ] && ! get_user_yn "File \"$target\" already exists. Overwrite" "n"; then
        if [ -z "$3" ]; then
          echo "Skipped..."
          continue
        else
          # Copy as e.g. .dist-file:
          target="${target}.${3}"
          rm -f "$target"
        fi
      fi
    fi

    retval=0
    if [ $diff_retval -eq 2 ]; then
      # copy file & create backup of old file if exists
      cp -bv --preserve=mode,timestamps "$source" "$target"
      retval=$?
    else
      # Only comments mismatch, so no point in keeping a backup file
      cp -v --preserve=mode,timestamps "$source" "$target"
      retval=$?
    fi

    if [ $retval -ne 0 ]; then
      echo "ERROR: Copy of \"$source\" to \"$target\" failed!" >&2
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
  for source in `find "$1" -type f |grep -v -e '/\.svn/' -e '/\.git/'`; do
    if echo "$2" |grep -q '/$'; then
      fn="$(echo "$source" |sed "s,^$1,,")"
      if [ -z "$fn" ]; then
        target="$2$(basename "$1")"
      else
        target="$2$fn"
      fi
      target_dir="$2"
    else
      target="$2"
      target_dir="$(dirname "$2")"
    fi

    if [ ! -d "$target_dir" ]; then
      printf "\033[40m\033[1;31m* WARNING: Target directory $target_dir does not exist. Skipping copy of $source!\033[0m\n" >&2
      continue
    fi

    if [ -f "$target" ]; then
      if [ -z "$3" ]; then
        echo "* File \"$target\" already exists. Skipping copy of $source"
        continue
      else
        # Copy as e.g. .dist-file:
        target="${target}.${3}"
        rm -f "$target"
      fi
    fi

    # NOTE: Always copy, even if contents is the same to make sure permissions are updated 
    if ! cp -v --preserve=mode,timestamps "$source" "$target"; then
      echo "ERROR: Copy of \"$source\" to \"$target!\" failed!" >&2
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
  for source in `find "$1" -type f |grep -v -e '/\.svn/' -e '/\.git/'`; do
    if echo "$2" |grep -q '/$'; then
      fn="$(echo "$source" |sed "s,^$1,,")"
      if [ -z "$fn" ]; then
        target="$2$(basename "$1")"
      else
        target="$2$fn"
      fi
      target_dir="$2"
    else
      target="$2"
      target_dir="$(dirname "$2")"
    fi

    if [ ! -d "$target_dir" ]; then
      printf "\033[40m\033[1;31m* WARNING: Target directory $target_dir does not exist. Skipping copy of $source!\033[0m\n" >&2
      continue
    fi

    # NOTE: Always copy, even if contents is the same to make sure permissions are updated
    if ! cp -fv --preserve=mode,timestamps "$source" "$target"; then
      echo "ERROR: Copy of \"$source\" to \"$target\" failed!" >&2
      exit 3
    fi

    chown 0:0 "$target"
  done

  return 0
}


get_user_yn()
{
  if [ "$2" = "y" ]; then
    printf "$1 (Y/n)? "
  else
    printf "$1 (y/N)? "
  fi

  read answer_with_case

  ANSWER=`echo "$answer_with_case" |tr A-Z a-z`

  if [ "$ANSWER" = "y" -o "$ANSWER" = "yes" ]; then
    return 0
  fi

  if [ "$ANSWER" = "n" -o "$ANSWER" = "no" ]; then
    return 1
  fi

  # Fallback to default
  if [ "$2" = "y" ]; then
    return 0
  else
    return 1
  fi
}


check_18_version()
{
  if grep -q "^MY_VERSION=" "/etc/init.d/arno-iptables-firewall" 2>/dev/null; then
    if get_user_yn "WARNING: An old version is still installed. Removing it first is *STRONGLY* recommended. Remove" "y"; then
      rm -fv /etc/init.d/arno-iptables-firewall
      mv -fv /etc/arno-iptables-firewall/custom-rules /etc/arno-iptables-firewall/custom-rules.old
      mv -fv /etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/firewall.conf.old
      rm -fv /etc/arno-iptables-firewall/plugins/*.plugin
      rm -fv /etc/rc*.d/*arno-iptables-firewall
    fi
  fi
}


# Check plugins for (old) versions with different priority
check_plugins()
{
  if [ -d /usr/local/share/arno-iptables-firewall/plugins ] && ls /usr/local/share/arno-iptables-firewall/plugins/*.plugin >/dev/null 2>&1; then
    unset IFS
    for PLUGIN_FILE in ./share/arno-iptables-firewall/plugins/*.plugin; do
      PLUGIN_NAME="$(basename "$PLUGIN_FILE" |sed 's/^[0-9]*//')"

      ls /usr/local/share/arno-iptables-firewall/plugins/*.plugin 2>/dev/null |grep "/[0-9]*${PLUGIN_NAME}$" |grep -v "/$(basename "$PLUGIN_FILE")$" |while IFS=$EOL read PLUGIN_OLD; do
        echo "* Removing old plugin: $PLUGIN_OLD"
        rm -fv "$PLUGIN_OLD"
      done
    done
  fi
}


# main line:
AIF_VERSION="$(grep "MY_VERSION=" ./bin/arno-iptables-firewall |sed -e "s/^MY_VERSION=\"//" -e "s/\"$//")"

printf "\033[40m\033[1;32mArno's Iptables Firewall Script(AIF) v$AIF_VERSION\033[0m\n"
printf "Install Script v$MY_VERSION\n"
echo "-------------------------------------------------------------------------------"

sanity_check

# We want to run in the dir the install script is in
cd "$(dirname $0)"

if ! get_user_yn "Continue install" "n"; then
  echo "*Install aborted"
  exit 1
fi

# Make sure there still isn't an old version installed
check_18_version

copy_overwrite ./bin/arno-iptables-firewall /usr/local/sbin/
copy_overwrite ./bin/arno-fwfilter /usr/local/bin/

# Remove old version:
rm -f /usr/local/sbin/arno-fwfilter

mkdir -pv /usr/local/share/arno-iptables-firewall/plugins || exit 1
copy_overwrite ./share/arno-iptables-firewall/ /usr/local/share/arno-iptables-firewall/

if [ ! -e /usr/local/sbin/traffic-accounting-show ]; then 
  ln -sv /usr/local/share/arno-iptables-firewall/plugins/traffic-accounting-show /usr/local/sbin/traffic-accounting-show
fi

mkdir -pv /usr/local/share/man/man1 || exit 1
mkdir -pv /usr/local/share/man/man8 || exit 1
gzip -c -v ./share/man/man8/arno-iptables-firewall.8 >/usr/local/share/man/man8/arno-iptables-firewall.8.gz
gzip -c -v ./share/man/man1/arno-fwfilter.1 >/usr/local/share/man/man8/arno-fwfilter.1.gz

mkdir -pv /usr/local/share/doc/arno-iptables-firewall || exit 1
copy_overwrite ./README /usr/local/share/doc/arno-iptables-firewall/

# Install init.d script, but only if init.d folder existss
if [ -d "/etc/init.d" ]; then
  copy_ask_if_exist ./etc/init.d/arno-iptables-firewall /etc/init.d/
fi

# Make sure only one service file exists in /lib/.. or /usr/lib/ where we prefer /lib/
rm -f /usr/lib/systemd/system/arno-iptables-firewall.service

# Install service file if systemd directory is available, use fallbacks to support different systems
if [ -d "/lib/systemd/system" ]; then
  copy_overwrite ./lib/systemd/system/arno-iptables-firewall.service /lib/systemd/system/
elif [ -d "/usr/lib/systemd/system" ]; then
  copy_overwrite ./lib/systemd/system/arno-iptables-firewall.service /usr/lib/systemd/system/
elif [ -d "/etc/systemd/system" ]; then
 copy_ask_if_exist ./lib/systemd/system/arno-iptables-firewall.service /etc/systemd/system/
else
  echo "NOTE: Could not find any systemd/system directory, skipping systemd configuration" >&2
fi

# Install rsyslog config file (if rsyslog is available)
if [ -d "/etc/rsyslog.d" ]; then
  copy_ask_if_exist ./etc/rsyslog.d/arno-iptables-firewall.conf /etc/rsyslog.d/
fi

mkdir -pv /etc/arno-iptables-firewall || exit 1

copy_overwrite ./etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/firewall.conf.dist
copy_ask_if_exist ./etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/ 

copy_skip_if_exist ./etc/arno-iptables-firewall/custom-rules /etc/arno-iptables-firewall/

mkdir -pv /etc/arno-iptables-firewall/plugins || exit 1
copy_ask_if_exist ./etc/arno-iptables-firewall/plugins/ /etc/arno-iptables-firewall/plugins/ "dist"

mkdir -pv /etc/arno-iptables-firewall/conf.d || exit 1
echo "Files with a .conf extension in this directory will be sourced by the environment file" >/etc/arno-iptables-firewall/conf.d/README

check_plugins

echo ""
echo "** Install done **"
echo ""

if get_user_yn "Do you want to run the configuration script"; then
  ./configure.sh
fi

echo ""
echo "-------------------------------------------------------------------------------"
echo "** NOTE: You can now (manually) start the firewall by executing              **"
echo "**       \"/usr/local/sbin/arno-iptables-firewall start\"                      **"
echo "**       It is recommended however to first review the settings in           **"
echo "**       /etc/arno-iptables-firewall/firewall.conf!                          **"
echo "-------------------------------------------------------------------------------"
echo ""

if get_user_yn "(Re)start firewall"; then
  /usr/local/sbin/arno-iptables-firewall restart
fi

exit 0
