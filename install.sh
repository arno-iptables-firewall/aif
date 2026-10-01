#!/bin/bash

MY_VERSION="1.14e"

# ------------------------------------------------------------------------------------------
#                         -= Arno's Iptables Firewall(AIF) =-
#              Single- & multi-homed firewall script with DSL/ADSL support
#
#                           ~ In memory of my dear parents ~
#
# (C) Copyright 2001-2026 by Arno van Amersfoort
# Web                   : https://github.com/arno-iptables-firewall/aif
# Email                 : a r n o DOT v a n DOT a m e r s f o o r t AT g m a i l DOT c o m
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
# The environment file looks for the installed files, which don't exist (yet) on a
# first install, so tell it where they go
USR_SHARE_PATH="/usr/local/share/arno-iptables-firewall"

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
  if [ "$(cat "$1")" = "$(cat "$2")" ]; then
    return 0 # Match
  fi

  # Check whether only comments differ. Only full comment lines count as comments,
  # as a '#' within a line can also be part of a value (eg. "eth0#0/0>1.2.3.4~22")
  if [ "$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$1")" = "$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$2")" ]; then
    return 1 # Only comments differ
  fi

  return 2 # Full mismatch
}


# Does the file only contain comments, empty lines and VAR=value lines?
is_var_config()
{
  ! grep -q -v -E -e '^[[:space:]]*(#|$)' -e '^[A-Za-z_][A-Za-z0-9_]*=' "$1"
}


# Usage: merge_config NEW_FILE OLD_FILE
# Prints NEW_FILE with the settings (VAR=value lines) of OLD_FILE: an active
# VAR=, or else a commented out #VAR= in NEW_FILE, gets the line of OLD_FILE.
# Settings NEW_FILE doesn't have (anymore) are added at the end
merge_config()
{
  awk '
    FNR == 1 { pass++ }
    pass == 1 {
      if (match($0, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
        var = substr($0, 1, RLENGTH - 1)
        if (!(var in old)) order[++n] = var
        old[var] = $0
      }
      next
    }
    pass == 2 {
      if (match($0, /^[A-Za-z_][A-Za-z0-9_]*=/)) active[substr($0, 1, RLENGTH - 1)] = 1
      next
    }
    {
      if (match($0, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
        var = substr($0, 1, RLENGTH - 1)
        if (var in old) { print old[var]; used[var] = 1; next }
      } else if (match($0, /^#[A-Za-z_][A-Za-z0-9_]*=/)) {
        var = substr($0, 2, RLENGTH - 2)
        if ((var in old) && !(var in active) && !(var in used)) { print old[var]; used[var] = 1; next }
      }
      print
    }
    END {
      for (i = 1; i <= n; i++) {
        if (!(order[i] in used)) {
          if (!header) {
            print ""
            print "# ------------------------------------------------------------------------------"
            print "# Settings of the previous version of this file that are not in this version"
            print "# (eg. obsolete or renamed), kept by install.sh. Please review them!"
            print "# ------------------------------------------------------------------------------"
            header = 1
          }
          print old[order[i]]
        }
      }
    }' "$2" "$1" "$1"
}


copy_ask_if_exist()
{
  local DIFF_RETVAL=-1
  local RETVAL
  local DEFAULT_YN="${3:-'n'}" # Default to n(o)
  local BACKUP_EXT="$4"
  local FALLBACK_EXT="$5"

  if [ -z "$(find "$1" -type f)" ]; then
    echo "ERROR: Missing source file(s) \"$1\"" >&2
    exit 2
  fi

  unset IFS
  for SOURCE in `find "$1" -type f |grep -v -e '/\.svn/' -e '/\.git/'`; do
    if echo "$2" |grep -q '/$'; then
      FN="${SOURCE#$1}"
      if [ -z "$FN" ]; then
        TARGET="${2}$(basename "$1")"
      else
        TARGET="${2}${FN}"
      fi
      TARGET_DIR="$2"
    else
      TARGET="$2"
      TARGET_DIR="$(dirname "$2")"
    fi

    if [ ! -d "$TARGET_DIR" ]; then
      printf "\033[40m\033[1;31m* WARNING: Target directory $TARGET_DIR does not exist. Skipping copy of $SOURCE!\033[0m\n" >&2
      continue
    fi

    if [ -f "$SOURCE" -a -f "$TARGET" ]; then
      # Ignore files that are the same in the target
      shell_diff "$SOURCE" "$TARGET"
      DIFF_RETVAL=$? # 0 = full match, 1 = match (excluding comments), 2 = full mismatch (including comments)

      # Config files: offer to take over the current settings into the new version,
      # unless that changes nothing (it only differs in the settings themselves)
      if [ $DIFF_RETVAL -eq 2 ] && is_var_config "$SOURCE" && is_var_config "$TARGET"; then
        MERGED="$(merge_config "$SOURCE" "$TARGET")"

        if [ "$MERGED" = "$(cat "$TARGET")" ]; then
          continue
        fi

        if get_user_yn "File \"$TARGET\" differs from the new version. Merge your settings into the new version" "y"; then
          if ! cp -v --preserve=mode,timestamps "$TARGET" "$TARGET.${BACKUP_EXT:-old}" ||
             ! printf '%s\n' "$MERGED" >"$TARGET"; then
            echo "ERROR: Merge into \"$TARGET\" failed!" >&2
            exit 3
          fi

          echo "* Merged your settings into the new \"$TARGET\" (previous version: \"$TARGET.${BACKUP_EXT:-old}\")"
          if grep -q '^# Settings of the previous version of this file that are not in this version' "$TARGET"; then
            echo "  NOTE: Some settings no longer exist in the new version, they're kept at the end of the file"
          fi
          continue
        fi
      fi

      if [ $DIFF_RETVAL -eq 2 ] && ! get_user_yn "File \"$TARGET\" already exists. Overwrite" "$DEFAULT_YN"; then
        if [ -z "$FALLBACK_EXT" ]; then
          echo "Skipped..."
          continue
        else
          # Copy as e.g. .dist-file:
          TARGET="${TARGET}.${FALLBACK_EXT}"
          rm -f "$TARGET"
        fi
      fi
    fi

    RETVAL=0
    if [ $DIFF_RETVAL -eq 2 -a -n "$BACKUP_EXT" ]; then
      # copy file & create backup of old file if exists
      cp -v --suffix=".${BACKUP_EXT}" --backup=simple --preserve=mode,timestamps "$SOURCE" "$TARGET"
      RETVAL=$?
    else
      # Only comments mismatch, so no point in keeping a backup file
      cp -v --preserve=mode,timestamps "$SOURCE" "$TARGET"
      RETVAL=$?
    fi

    if [ $RETVAL -ne 0 ]; then
      echo "ERROR: Copy of \"$SOURCE\" to \"$TARGET\" failed!" >&2
      exit 3
    fi

    chown 0:0 "$TARGET"
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
  for SOURCE in `find "$1" -type f |grep -v -e '/\.svn/' -e '/\.git/'`; do
    if echo "$2" |grep -q '/$'; then
      FN="${SOURCE#$1}"
      if [ -z "$FN" ]; then
        TARGET="$2$(basename "$1")"
      else
        TARGET="$2$FN"
      fi
      TARGET_DIR="$2"
    else
      TARGET="$2"
      TARGET_DIR="$(dirname "$2")"
    fi

    if [ ! -d "$TARGET_DIR" ]; then
      printf "\033[40m\033[1;31m* WARNING: Target directory $TARGET_DIR does not exist. Skipping copy of $SOURCE!\033[0m\n" >&2
      continue
    fi

    if [ -f "$TARGET" ]; then
      if [ -z "$3" ]; then
        echo "* File \"$TARGET\" already exists. Skipping copy of $SOURCE"
        continue
      else
        # Copy as e.g. .dist-file:
        TARGET="${TARGET}.${3}"
        rm -f "$TARGET"
      fi
    fi

    # NOTE: Always copy, even if contents is the same to make sure permissions are updated 
    if ! cp -v --preserve=mode,timestamps "$SOURCE" "$TARGET"; then
      echo "ERROR: Copy of \"$SOURCE\" to \"$TARGET!\" failed!" >&2
      exit 3
    fi

    chown 0:0 "$TARGET"
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
  for SOURCE in `find "$1" -type f |grep -v -e '/\.svn/' -e '/\.git/'`; do
    if echo "$2" |grep -q '/$'; then
      FN="${SOURCE#$1}"
      if [ -z "$FN" ]; then
        TARGET="$2$(basename "$1")"
      else
        TARGET="$2$FN"
      fi
      TARGET_DIR="$2"
    else
      TARGET="$2"
      TARGET_DIR="$(dirname "$2")"
    fi

    if [ ! -d "$TARGET_DIR" ]; then
      printf "\033[40m\033[1;31m* WARNING: Target directory $TARGET_DIR does not exist. Skipping copy of $SOURCE!\033[0m\n" >&2
      continue
    fi

    # NOTE: Always copy, even if contents is the same to make sure permissions are updated
    if ! cp -fv --preserve=mode,timestamps "$SOURCE" "$TARGET"; then
      echo "ERROR: Copy of \"$SOURCE\" to \"$TARGET\" failed!" >&2
      exit 3
    fi

    chown 0:0 "$TARGET"
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


check_dist_version()
{
  if [ -f /usr/sbin/arno-iptables-firewall ]; then
    if ! get_user_yn "WARNING: It seems a distribution version is already installed. It's *STRONGLY* recommended to remove it first. Continue anyway" "n"; then
      return 1
    fi
  fi

  return 0
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


setup_start_scripts()
{
  # Install init.d script, but only if init.d folder exists
  if [ -d "/etc/init.d" ]; then
    copy_overwrite ./etc/init.d/arno-iptables-firewall /etc/init.d/
  fi

  # Make sure only one service file exists in /lib/.. or /usr/lib/ where we prefer /lib/
  rm -f /usr/lib/systemd/system/arno-iptables-firewall.service

  # Install service file if systemd directory is available, use fallbacks to support different systems
  if [ -d "/lib/systemd/system" ]; then
    copy_overwrite ./lib/systemd/system/arno-iptables-firewall.service /lib/systemd/system/
  elif [ -d "/usr/lib/systemd/system" ]; then
    copy_overwrite ./lib/systemd/system/arno-iptables-firewall.service /usr/lib/systemd/system/
  elif [ -d "/etc/systemd/system" ]; then
    copy_ask_if_exist ./lib/systemd/system/arno-iptables-firewall.service /etc/systemd/system/ "y"
  else
    echo "NOTE: Could not find any systemd/system directory, skipping systemd configuration" >&2
  fi

  RC_PATH="/etc"
  # Check for Redhat/SUSE rc.d
  if [ -d "/etc/rc.d" ]; then
    RC_PATH="/etc/rc.d"
  fi

  # Remove any symlinks in rc*.d out of the way
  rm -f $RC_PATH/rc0.d/*arno-iptables-firewall
  rm -f $RC_PATH/rc1.d/*arno-iptables-firewall
  rm -f $RC_PATH/rc2.d/*arno-iptables-firewall
  rm -f $RC_PATH/rc3.d/*arno-iptables-firewall
  rm -f $RC_PATH/rc4.d/*arno-iptables-firewall
  rm -f $RC_PATH/rc5.d/*arno-iptables-firewall
  rm -f $RC_PATH/rc6.d/*arno-iptables-firewall
  rm -f $RC_PATH/rcS.d/*arno-iptables-firewall

  if get_user_yn "Do you want to start the firewall at boot" "y"; then
    DONE=0

    if check_command systemctl; then
      if systemctl enable arno-iptables-firewall; then
        echo "* Successfully enabled service with systemctl"
        DONE=1
      fi
    elif check_command update-rc.d; then
      # Note: Currently update-rc.d doesn't seem to properly use the init script's LSB header, so specify explicitly
      if update-rc.d -f arno-iptables-firewall start 11 S . stop 10 0 6 .; then
        echo "* Successfully enabled service with update-rc.d"
        DONE=1
      fi
    elif check_command chkconfig; then
      if chkconfig --add arno-iptables-firewall && chkconfig arno-iptables-firewall on; then
        echo "* Successfully enabled service with chkconfig"
        DONE=1
      fi
    else
      if [ -d "$RC_PATH/rcS.d" ]; then
        if ln -sv /etc/init.d/arno-iptables-firewall "$RC_PATH/rcS.d/S11arno-iptables-firewall" &&
          ln -sv /etc/init.d/arno-iptables-firewall "$RC_PATH/rc0.d/K10arno-iptables-firewall" &&
          ln -sv /etc/init.d/arno-iptables-firewall "$RC_PATH/rc6.d/K10arno-iptables-firewall"; then
          echo "* Successfully enabled service through $RC_PATH/rcS.d/ symlink"
          DONE=1
        fi
      elif [ -d "$RC_PATH/rc2.d" ]; then
        if ln -sv /etc/init.d/arno-iptables-firewall "$RC_PATH/rc2.d/S09arno-iptables-firewall" &&
          ln -sv /etc/init.d/arno-iptables-firewall "$RC_PATH/rc0.d/K91arno-iptables-firewall" &&
          ln -sv /etc/init.d/arno-iptables-firewall "$RC_PATH/rc6.d/K91arno-iptables-firewall"; then
          echo "* Successfully enabled service through $RC_PATH/rc2.d/ symlink"
          DONE=1
        fi
      else
        echo "WARNING: Unable to detect /rc2.d or /rcS.d directories. Skipping runlevel symlinks" >&2
      fi
    fi

    if [ $DONE -eq 0 ]; then
      echo "ERROR: Unable to setup automatic start at boot. Please investigate" >&2
    fi
  fi
}


# main line:
AIF_VERSION="$(grep "MY_VERSION=" ./bin/arno-iptables-firewall |sed -e "s/^MY_VERSION=\"//" -e "s/\"$//")"

printf "\033[40m\033[1;32mArno's Iptables Firewall Script(AIF) v$AIF_VERSION\033[0m\n"
printf "Install Script v$MY_VERSION\n"
echo "-------------------------------------------------------------------------------"

sanity_check

# We want to run in the dir the install script is in
cd "$(dirname $0)" || exit 1

if ! get_user_yn "Continue install" "n"; then
  echo "*Install aborted"
  exit 1
fi

# Make sure an old version is not still installed
check_18_version

# Make sure a dist version is not already installed
if ! check_dist_version; then
  echo "*Install aborted"
  exit 1
fi

copy_overwrite ./bin/arno-iptables-firewall /usr/local/sbin/
copy_overwrite ./bin/arno-fwfilter /usr/local/bin/

# Remove old version:
rm -f /usr/local/sbin/arno-fwfilter

mkdir -pv /usr/local/share/arno-iptables-firewall/plugins || exit 1
copy_overwrite ./share/arno-iptables-firewall/ /usr/local/share/arno-iptables-firewall/

# Shared with Arno's (NFT) Firewall, it always points to the version installed last
if [ "$(readlink /usr/local/sbin/traffic-accounting-show)" != "/usr/local/share/arno-iptables-firewall/plugins/traffic-accounting-show" ]; then
  ln -sfnv /usr/local/share/arno-iptables-firewall/plugins/traffic-accounting-show /usr/local/sbin/traffic-accounting-show
fi

mkdir -pv /usr/local/share/man/man1 || exit 1
mkdir -pv /usr/local/share/man/man8 || exit 1
gzip -c -v ./share/man/man8/arno-iptables-firewall.8 >/usr/local/share/man/man8/arno-iptables-firewall.8.gz
gzip -c -v ./share/man/man1/arno-fwfilter.1 >/usr/local/share/man/man8/arno-fwfilter.1.gz

mkdir -pv /usr/local/share/doc/arno-iptables-firewall || exit 1

# Remove old version:
rm -fv /usr/local/share/doc/arno-iptables-firewall/README
copy_overwrite ./README.md /usr/local/share/doc/arno-iptables-firewall/

# Install rsyslog config file (if rsyslog is available)
if [ -d "/etc/rsyslog.d" ]; then
  copy_ask_if_exist ./etc/rsyslog.d/arno-iptables-firewall.conf /etc/rsyslog.d/ "y" "old" "dist"
fi

copy_ask_if_exist ./etc/logrotate.d/arno-iptables-firewall /etc/logrotate.d/ "y"

mkdir -pv /etc/arno-iptables-firewall || exit 1

copy_overwrite ./etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/firewall.conf.dist
copy_ask_if_exist ./etc/arno-iptables-firewall/firewall.conf /etc/arno-iptables-firewall/

copy_skip_if_exist ./etc/arno-iptables-firewall/custom-rules /etc/arno-iptables-firewall/

mkdir -pv /etc/arno-iptables-firewall/plugins || exit 1
copy_ask_if_exist ./etc/arno-iptables-firewall/plugins/ /etc/arno-iptables-firewall/plugins/ "n" "old" "dist"

mkdir -pv /etc/arno-iptables-firewall/conf.d || exit 1
echo "Files with a .conf extension in this directory will be sourced by the environment file" >/etc/arno-iptables-firewall/conf.d/README

# Check old plugins
check_plugins


setup_start_scripts

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
