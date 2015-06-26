/*
# mrtg-pnsclient v1.6
#
# Compile with 
# cc -o mrtg-pnsclient -O -s mrtg-pnsclient.c
# Tested with GNU gcc under RedHat Enterprise Linux
#
# S Shipway - www.steveshipway.org
# This is released under the GNU GPL.  See nsclient.ready2run.nl
# to obtain the NetSaint client for your Windows server!
#
# C program to collect information from remote pNSclient NetSaint
# client, and output in format suitable for MRTG.
#
# Usage:
#   mrtg-pnsclient [-C] -H host [ -p port ] [ -P password ] [ -t timeout ]
#       -v <module> [ -l <options> ] [ -o <offset> ]
#       [ -v <module> ] [ -l <option> ] [ -o <offset> ] 
#
# If only one module specified, then the second value is UNKNOWN
# If the module returns more than one value then both are given
# Modules: COUNTER, DISKSPACE, SERVICE, MEMORY, PROCESS, VERSION, INSTANCES
*/
/*
   Version: 1.0 C version of original Perl version
            1.1 Fix 'UNKNWON' bug
			1.2 Support for nc_net (no chained queries, one per connect only)
            1.3 Support for nsclient++ no trailing '&' on parameterised cmds
            1.4 Try to work out why it doesnt work under gearman: more logs
            1.5 Need trailing & in some cases!
            1.6 identify remote agent - nsclient++ has no trailing & for type 8
*/

/* #undef DEBUG */

#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <errno.h>
#include <netinet/in.h>
#include <netdb.h>
#include <fcntl.h>
#include <signal.h>

#define VERSION "1.5(C)"
#define PORT    1248
#define DEFPASS "None"
#define TIMEOUT 5

#define WITHALARM
#undef  WITHNONBLOCK

#ifdef DEBUG
static char debug_id[] = "Compiled in debug mode";
#endif

char   mesg[128];
double resp[2] = {0,0};
int    unknown[2] = {1,1};
int    sock = -1;
char   host[64];
char   pass[16];
int    port;
char * arg[2] = {0,0};
int    cmd[2] = {-1,-1};
int    offset[2] = {0,0};
int    timeout = TIMEOUT;
int    ratiomode = 0;
int    debugmode = 0;
int    compatmode = 0;
char * verstr = (char*)0;

void fixstr(char *s) {
	for( ; *s ; s++ ) {
		if( *s == ',' ) { *s = '.'; continue; }
/*		if( *s == '.' ) { continue; }
		if( (*s < '0') || (*s > '9') ) { *s = '\0'; break; } */
	}
}

/*
"NONE"=>0, "CLIENTVERSION" => 1, "VERSION" =>1, "CPULOAD" =>2, "CPU" =>2,
"UPTIME"=>3, "USEDDISKSPACE"=>4, "DISKSPACE"=>4,
"SERVICESTATE"=>5, "SERVICE"=>5, "PROCSTATE"=>6,
"PROCESS"=>6, "MEMUSE"=>7, "MEMORY"=>7, "COUNTER"=>8, "FILEAGE"=>9,
"INSTANCES"=> 10
*/
int getcmd(char *s) {
	if( !strcasecmp(s,"NONE") ) { return(0); }
	if( !strncasecmp(s,"VER",3) ) { return(1); }
	if( !strncasecmp(s,"CPU",3) ) { return(2); }
	if( !strcasecmp(s,"UPTIME") ) { return(3); }
	if( !strcasecmp(s,"USEDDISKSPACE") ) { return(4); }
	if( !strncasecmp(s,"DISK",4) ) { return(4); }
/*	if( !strncasecmp(s,"SERV",4) ) { return(5); } */
/*	if( !strncasecmp(s,"PROC",4) ) { return(6); } */
	if( !strncasecmp(s,"MEM",3) ) { return(7); }
	if( !strncasecmp(s,"COUNT",5) ) { return(8); }
/*	if( !strncasecmp(s,"FILE",4) ) { return(9); } */
	if( !strcasecmp(s,"INSTANCES") ) { return(10); } 
	return(-1);
}
void outputresp() {
#ifdef DEBUG
	FILE *fp;
	fp = fopen ("/tmp/pnsclient.log","a");
	if(fp) {
		fprintf(fp,"%f\n%f\n\n%s\n",
			(unknown[0]?-1:resp[0]),
			(unknown[1]?-1:resp[1]),
			(mesg?mesg:"(null)"));
		fclose(fp);
	}
#endif
	if( unknown[0] ) { printf("UNKNOWN\n"); }
	else { printf("%f\n",resp[0]); }
	if( unknown[1] ) { printf("UNKNOWN\n"); }
	else { printf("%f\n",resp[1]); }
	printf("\n%s\n",mesg);
}
void dohelp() {
	printf("mrtg-pnsclient [-C] -H host [ -p port ] [ -P password ] [ -t timeout ]\n");
	printf("    -c <module> [ -a <option> ] [ -o <offset> ]\n");
	printf("  [ -c <module> ] [ -a <option> ] [ -o <offset> ]\n");
	printf("\n-d : Debug mode\n");
	printf("-C : Old NSclient compatibility mode\n");
	printf("-P : NSclient password (usually leave as default)\n");
	printf("-t : Timeout (default %d)\n",TIMEOUT);
	printf("-o : Offset - 0 or 1 (some commands return 2 values)\n");
	printf("-c : Command - CPU (needs average time, eg '5'), MEM, \n     DISK (needs disk letter, eg 'C'), COUNT (needs counter name, \n     eg '\\Memory\\Used Bytes' or '\\Group(instance)\\Object' )\n");
	printf("\nIf a second command is not specified then it defaults to the same as the\nfirst command.\n");
	exit(0);
}
/*
######################################################################
# command no, optional argument, where to store value
# returns 0 on success
*/
int ask(int cmd,char *s,double *rvp,int o,int r,int cached,char *msg) {
	char buf[256];
	fd_set rfd,wfd,xfd;
	struct timeval tv;
	int n;
	char *t;
	static double a,b;

	if(sock<0) { 
		sprintf(mesg,"Socket not open");
		return(1); 
	} /* socket not open */

	if(!cached || msg) {
		/* prepare the message */
		if(s) { 
			for(t=s;*t;t++){ if(*t==',') { *t='&'; } } /* remove commas */
			snprintf(buf,sizeof(buf),"%s&%d&%s%s\n",pass,cmd,s,
				(compatmode?"&":"")); 
		} else { 
			snprintf(buf,sizeof(buf),"%s&%d&\n",pass,cmd); 
		}
		n = write(sock,buf,strlen(buf));
		if( n != strlen(buf) ) { 
			sprintf(mesg,"Unable to write to socket.");
			return 1; /* write error */
		}
		if(debugmode) { printf("Sent: %s",buf);fflush(NULL); }
	
		FD_ZERO(&rfd); FD_ZERO(&wfd); FD_ZERO(&xfd);
		FD_SET(sock,&rfd);
		tv.tv_usec = 0;
		tv.tv_sec = timeout;
		n = select(sock+1,&rfd,&wfd,&xfd,&tv);
		if(!n) {
			sprintf(mesg,"Timeout on read.");
			if(debugmode) { printf("Timed out (%d).\n",timeout);fflush(NULL); }
			return( 1 ); /* timeout */
		} 
		if( n < 0 ) {
			sprintf(mesg,"Error on select.");
			if(debugmode) { printf("Select error.\n");fflush(NULL); }
			return( 1 ); 
		}
		if(debugmode) { printf("Reading data...\n");fflush(NULL); }
		n = read( sock,buf,sizeof(buf) );
		buf[n]='\0';
		if(debugmode) { printf("Read [%s]\n",buf);fflush(NULL); }
		if(!n) {
			sprintf(mesg,"No data received from host");
			return( 1 ); /* nothing received */
		}
		if(msg) {
			strncpy(msg,buf,sizeof(buf));
			return 0;
		}
		fixstr(buf); /* commas and decimal points */
		/* now, we may have 2 values here */
		t = strchr(buf,'&');
		if(t)  { *t='\0'; t++; b = atof(t); } 
		a = atof(buf); 
		if(!t) { b = a; }
	} /* cached */
	if(rvp) {
	if( r ) {
		if(a>b) { if(a>0) { *rvp = b/a*100.0; } } 
		else { if(b>0) { *rvp = a/b*100.0; } }
	} else if( o ) { *rvp = b; } 
	else { *rvp = a; }
	if(debugmode) {
		printf("Processed %f,%f: Returning %f\n",a,b,*rvp);fflush(NULL);	
	}
	}
	return(0);
}
#ifdef WITHALARM
void handler(int c) {
	printf("UNKNOWN\nUNKNOWN\n\nTimeout on connect.\n");
	exit(1);
}
#endif
/*
######################################################################
# make $sock, the socket...
*/
void makesocket() {
	struct hostent * hp;
	struct sockaddr_in ss;
	struct in_addr ia;
	int n,v;

	if(debugmode) { printf("Opening connection to host...\n");fflush(NULL);}

	hp = gethostbyname(host);
	if(!hp) {
		sprintf(mesg,"Unable to resolve %s",host);
		outputresp(); exit(1);
	}
	bzero(&ss,sizeof(ss));
	memcpy(&ss.sin_addr,hp->h_addr,sizeof(ss.sin_addr));
	ss.sin_family = AF_INET;
	ss.sin_port = htons(port);
	if(debugmode) { printf("Creating socket...\n");fflush(NULL);}
	sock = socket(PF_INET,SOCK_STREAM,0);
	if(sock<0) {
		sprintf(mesg,"Unable to create socket");
		outputresp(); exit(1);
	}
#ifdef WITHNONBLOCK
#if defined(O_NONBLOCK)
    if (-1 == (v = fcntl(sock, F_GETFL, 0)))
        v = 0;
    fcntl(sock, F_SETFL, v | O_NONBLOCK);
#else
    /* Otherwise, use the old way of doing it */
    v = 1;
    ioctl(sock, FIOBIO, &v);
#endif
#endif

	/* this can hang */
	if(debugmode) { printf("Connecting...\n");fflush(NULL);}
	n = connect(sock,(struct sockaddr *)&ss,(socklen_t)sizeof(ss));
	if(n) {
		sprintf(mesg,"Unable to connect (%d)",errno);
		outputresp(); exit(1);
	}
	if(debugmode) { printf("Setting reuseaddr...\n");fflush(NULL);}
	v = 1;
	setsockopt(sock,SOL_SOCKET,SO_REUSEADDR,&v,sizeof(v));
}
/*
######################################################################
# defaults
*/
int main(int argc, char **argv) {
int c;
int n;
int hasoffset = 0;

port = PORT;
strncpy(pass,DEFPASS,sizeof(pass));
host[0] = '\0';
resp[0] = resp[1] = 0;
unknown[0] = unknown[1] = 1;
strncpy(mesg,"Data retrieved OK",sizeof(mesg));

/* process arguments */
static struct option options[] = {
	{ "host", 1, 0, 'H' },
	{ "port", 1, 0, 'p' },
	{ "offset", 1, 0, 'o' },
	{ "module", 1, 0, 'c' },
	{ "command", 1, 0, 'c' },
	{ "cmd", 1, 0, 'c' },
	{ "arg", 1, 0, 'a' },
	{ "debug", 0, 0, 'd' },
	{ "timeout", 1, 0, 't' },
	{ "ratio", 0, 0, 'r' },
	{ "password", 1, 0, 'P' },
	{ "compat", 0, 0, 'C' }
};
while(1) {
	c = getopt_long(argc,argv,"CP:H:s:p:o:n:c:v:l:a:dt:rh",options,NULL);
	if(c == -1) break;
	switch(c) {
		case 'H':
		case 's':
			strncpy(host,optarg,sizeof(host)-1); break;
		case 'p':
			port = atoi(optarg); break;
		case 'P':
			strncpy(pass,optarg,sizeof(pass)-1); break;
		case 'o': /* offset */
		case 'n':
			n = 0; if(hasoffset || (cmd[1]>-1) || arg[1]) { n = 1; }
			offset[n] = atoi(optarg);
			hasoffset = 1;
			break;
		case 'c': /* command */
		case 'v':
			n = 0; if(cmd[n]>-1) { n = 1; }
			if(cmd[n]>-1) {
				sprintf(mesg,"You may only specify two commands.");
				outputresp();
				exit(1);
			}
			cmd[n] = getcmd(optarg);
			if(cmd[n]<0) {
				sprintf(mesg,"Invalid command [%s]",optarg);
				outputresp();
				exit(1);
			}
			break;
		case 'l': /* arg */
		case 'a':
			n = 0; if((cmd[1]>-1) || arg[0]) { n = 1; }
			arg[n] = optarg;
			break;
		case 'd':
			debugmode = 1; break;
		case 't':
			timeout = atoi(optarg);
			if(timeout < 1) { timeout = TIMEOUT; }	
			break;
		case 'r':
			ratiomode = 1; break;
		case 'h':
			dohelp(); exit(1);
		case 'C':
			compatmode = 1; break;
		default:
			sprintf(mesg,"Option was not recognised..."); 
			outputresp();
			exit(1);
	} /* switch */
} /* while loop */

if( !port || !host[0] ) {
	sprintf(mesg,"Must specify a valid port and hostname");
	outputresp();
	exit( 1 );
}

/* we need to run a second command only if the args have changed */
if((cmd[1]<0) && !arg[1] && !offset[1]) { offset[1]=1; } /* ? */
if((cmd[1]<0) && arg[1]) { cmd[1] = cmd[0]; }

if(cmd[0]<0) {
	sprintf(mesg,"No command was given.");
	outputresp(); exit(1);
}
/*
# Now we have one or two command to pass to the agent.
# We connect, and send, then listen for the response.
# Repeat for second argument if necessary
*/
#ifdef WITHALARM
/* timeout for program */
signal(SIGALRM,handler);
if(debugmode) { printf("Starting alarm for %d sec\n",timeout); fflush(NULL); }
alarm(timeout);
#endif

/* first, identify remote agent if necessary */
if((cmd[0]==8)||(cmd[1]==8)) {
    if(debugmode) { printf("Testing version\n"); fflush(NULL); }
    makesocket();
    verstr = (char *)malloc(256);
    n = ask(1,(char *)0,(double *)0,0,0,0,verstr);
    close(sock);
    if(! strcasestr(verstr,"nsclient++") ) {
    	if(debugmode) { printf("Setting compat mode\n"); fflush(NULL); }
	compatmode = 1;
    }
}

/* Connect */
if(debugmode) { printf("Starting queries\n"); fflush(NULL); }
makesocket();
n = ask(cmd[0],arg[0],&resp[0],offset[0],ratiomode,0,NULL);
close(sock);
if(n) { outputresp(); exit(0); }
else { unknown[0] = 0; }
if(cmd[1]>-1) {
	makesocket();
	n = ask(cmd[1],arg[1],&resp[1],offset[1],ratiomode,0,NULL);
	close(sock);
	if(n) { outputresp(); exit(0); }
	else { unknown[1] = 0; }
} else {
	makesocket();
	n = ask(-1,(char *)NULL,&resp[1],offset[1],ratiomode,1,NULL);
	close(sock);
	if(!n) { unknown[1] = 0; }
}
#ifdef WITHALARM
alarm(0);
#endif

sprintf(mesg,"Nagios query agent version %s",VERSION);

outputresp();
exit(0);
}
