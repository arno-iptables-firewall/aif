#!/bin/bash

MY_VERSION="1.0c"

# ------------------------------------------------------------------------------------------
#                           -= Arno's iptables firewall =-
#               Single- & multi-homed firewall script with DSL/ADSL support
#
#                           ~ In memory of my dear father ~
#
# (C) Copyright 2001-2015 by Arno van Amersfoort
# Homepage              : http://rocky.eld.leidenuniv.nl/
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

check_command()
{
  local path IFS

  IFS=' '
  for cmd in $*; do
    if [ -n "$(which "$cmd" 2>/dev/null)" ]; then
      return 0
    fi
  done

  return 1
}


sanity_check()
{
  # root check
  if [ "$(id -u)" != "0" ]; then
    printf "\033[40m\033[1;31mERROR: Root check FAILED (you MUST be root to use this script)! Quitting...\033[0m\n" >&2
    exit 1
  fi
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


# main line:
AIF_VERSION="$(grep "MY_VERSION=" ./bin/arno-iptables-firewall |sed -e "s/^MY_VERSION=\"//" -e "s/\"$//")"

printf "\033[40m\033[1;32mArno's Iptables Firewall Script v$AIF_VERSION\033[0m\n"
printf "Uninstall Script v$MY_VERSION\n"
echo "-------------------------------------------------------------------------------"

sanity_check;

if ! get_user_yn "Continue uninstall" "n"; then
  echo "*Uninstall aborted!"
  exit 1
fi

rm -fv /usr/local/sbin/arno-iptables-firewall
rm -fv /usr/local/sbin/arno-fwfilter
rm -fv /usr/local/bin/arno-fwfilter

rm -rfv /usr/local/share/arno-iptables-firewall

rm -fv /usr/local/share/man/man8/arno-iptables-firewall.8.gz
rm -fv /usr/local/share/man/man8/arno-fwfilter.1.gz

rm -fv /usr/local/share/doc/arno-iptables-firewall/README

# Check for insserv. Used for dependency based booting
if check_command update-rc.d; then
  update-rc.d -f arno-iptables-firewall remove
elif check_command chkconfig; then
  chkconfig --del arno-iptables-firewall
fi

rm -fv /etc/init.d/arno-iptables-firewall

# Remove leftovers:
rm -fv /etc/rc.d/rc*.d/*arno-iptables-firewall
rm -fv /etc/rc*.d/*arno-iptables-firewall
rm -fv /usr/lib/systemd/system/arno-iptables-firewall.service

if get_user_yn "Also remove ALL configuration files from /etc/arno-iptables-firewall/" "n"; then
  rm -rfv /etc/arno-iptables-firewall
else
  echo "* Skipped"
fi

echo ""
echo "** Uninstall done **"
echo ""

exit 0
