#!/bin/bash

MY_VERSION="0.11"

# ------------------------------------------------------------------------------------------
#                           -= Arno's iptables firewall =-
#               Single- & multi-homed firewall script with DSL/ADSL support
#
#                           ~ In memory of my dear father ~
#
# (C) Copyright 2001-2008 by Arno van Amersfoort
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
  printf "$1"

  while true; do
    read -s -n1 answer

    # Fallback to default
    if [ -z "$answer" ]; then
      answer="$2"
    fi

    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
      echo " Yes"
      return 0
    fi

    if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
      echo " No"
      return 1
    fi
  done
}



# main line:
AIF_VERSION="$(grep "MY_VERSION=" ./bin/arno-iptables-firewall |sed -e "s/^MY_VERSION=\"//" -e "s/\"$//")"

printf "\033[40m\033[1;32mArno's Iptables Firewall Script v$AIF_VERSION\033[0m\n"
printf "Uninstall Script v$MY_VERSION\n"
echo "-------------------------------------------------------------------------------"

sanity_check;

if get_user_yn "Continue uninstall (Y/N)? " "n"; then
  echo "*Uninstall aborted!"
  exit 1
fi

rm -fv /usr/local/sbin/arno-iptables-firewall
rm -fv /usr/local/sbin/arno-fwfilter

rm -rfv /usr/local/share/arno-iptables-firewall
rm -rfv /usr/share/arno-iptables-firewall

rm -fv /usr/local/share/man/man8/arno-iptables-firewall.8.gz
rm -fv /usr/local/share/man/man8/arno-fwfilter.1.gz
rm -fv /usr/share/man/man8/arno-iptables-firewall.8.gz
rm -fv /usr/share/man/man8/arno-fwfilter.1.gz

rm -fv /etc/init.d/arno-iptables-firewall
rm -fv /etc/rcS.d/S38arno-iptables-firewall
rm -fv /etc/rc2.d/S38arno-iptables-firewall

if get_user_yn "Also remove ALL configuration files from /etc/arno-iptables-firewall/ ? (Y/N) " "n"; then
  rm -rfv /etc/arno-iptables-firewall
else
  echo "*Skipped"
fi

echo ""
echo "** Uninstall done **"
echo ""

exit 0

