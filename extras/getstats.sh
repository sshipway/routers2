#!/bin/sh
# Get paging/CPU stats for all versions of OS

# This will run on any of the following (use 'uname' to get OS name):
#   SunOS
#   AIX
#   Linux
# OSF1 (Compaq tru64/Digital UNIX) - thanks to Guido Leenders
# SCO

# You should put this script into a secure directory, and then add the
# following entry to /etc/inetd.conf
#    stat stream tcp nowait nobody  /path/to/this/script getstats
# If you do not have a 'nobody' user on your system, use any other user.
# You will also need to add an entry in to /etc/services (or NIS if you
# use it).
#    stat 3030/tcp
# You do not have to use port 3030 if you don't want to, but it must be the
# same on all servers.

# output format:
# version OS page us sy wa users notes

version=1
os=`uname`
notes=""
page=U
user=U
system=U
wait=U
users=U
tmp=/tmp/stat.$$

PATH=$PATH:/usr/bin:/bin

# calculate 100 - params
therest()
{
r=100
for i in $*
do
	r=`expr $r - 0$i`
done
echo $r
}

# Every OS does its vmstat output differrently.  Grr.
case "$os" in
	AIX*) /usr/bin/vmstat 10 2 | tail -1 > $tmp
		read r b avm fre re pi po fr sr cy in sy cs us sy id wa junk < $tmp
		if [ "$wa" != "" ]
		then
			user=$us
			system=$sy
			wait=$wa
			page=$pi
		fi
		users=`who|wc -l`
		users=`expr 0 + $users`
		;;
	[lL]inux*) /usr/bin/vmstat 10 2 | tail -1 > $tmp
		read r b w swap free buff cac si so bi bo in cs us sy id junk < $tmp
		if [ "$id" != "" ]
		then
			user=$us
			system=$sy
			wait=`therest $us $sy $id`
			page=$si
		fi
		users=`who|wc -l`
		users=`expr 0 + $users`
		;;
#SCO by Daniel Wolk, Binara, Inc., 02/07/2003  
        SCO*) /usr/bin/vmstat 10 2 | tail -1 > $tmp  
                read r  b  w  frs dmd sw cch fil pft frp pos pif pis rso rsi sy  cs  us su id junk < $tmp  
                if [ "$id" != "" ]  
                then  
                        user=$us  
                        system=$su  
                        wait=`therest $us $su $id`  
                        page=$pis  
                fi  
                users=`who|wc -l`  
                users=`expr 0 + $users`  
                ;;  
	SunOS*|Solaris*) /usr/bin/vmstat 10 2 | tail -1 > $tmp
		read r b w swap free re mf pi po fr de sr aa dd f0 xx in sy cs us sy id junk < $tmp
		if [ "$id" != "" ]
		then
			user=$us
			system=$sy
			wait=`therest $us $sy $id`
			page=$pi
		fi
		users=`who|wc -l`
		users=`expr 0 + $users`
		;;
	OSF1)  /usr/bin/vmstat 10 2 | tail -1 > $tmp
		read r b w act free wire fault cow  zero react pi po in sy cs us sy id junk < $tmp
		if [ "$id" != ""] 
		then
			user=$us
			system=$sy
			wait=`therest $us $sy  $id`
			page=$pi
		fi
		users=`who|wc -l`
		users=`expr 0 +  $users`
		;;
	*)	notes="Operating system $os not supported"
		;;
esac


echo "$version:$os:$page:$user:$system:$wait:$users:$notes"
echo "ver:os:pa:us:sy:wa:au:not"

rm -f $tmp 2>/dev/null

exit 0
