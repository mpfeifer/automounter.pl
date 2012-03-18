#!/usr/bin/perl

use strict;

my $configfile=".automounter";
my $prefix="/dev/disk/by-id";
my @partitions;
my @mountpoints;
my @mounttime;
my @mypartitions;
my $daemon_timeout=10;
my $inactive_timeout=600;
my $debug=1;
my $logfile="automounter.log";
my $logto="stderr";

sub debug {
    my $message = shift;
    my $hlogfile;
    if ($debug) {
	if ($logto =~ /file/)
	{
	    open($hlogfile, ">>", $logfile);
	    if (not defined($hlogfile)) {
		print STDERR "$message\n";
		print STDERR "[FATAL] Cannot open logfile $logfile for writing\n";
		exit(1);
	    }
	    print $hlogfile "$message\n";
	    close($hlogfile);
	}
	elsif ($logto =~ /stderr/) {
	    printf STDERR "$message\n";
	}
    }
}

sub daemonize {
    my $pid = fork(); # 0 for child process
    if (defined($pid)) {
	debug("Daemon forked successfully");
    }
    if ($pid > 0) {
	debug("Parent process exiting. Child-pid=$pid");
	exit(0);
    }
    umask(0750);
    chdir("/tmp");
    close(STDIN);
    close(STDOUT);
    close(STDERR);
}

# returns 1 if partition is not mounted
# returns 0 if partition is     mounted
sub partition_is_not_mounted
{
    my $pindex=shift;
    my $mountoutput;
    my $MOUNTP;
    my $mountflag=1;
    debug("[INFO] Check if anything is mounted to $mountpoints[$pindex]");
    open($MOUNTP,"/bin/mount|");
    if (not defined $MOUNTP) {
	debug("[FATAL] could not execute mount command");
	exit(1);
    }
    while (<$MOUNTP>) {
	if (m/$mountpoints[$pindex]/)
	{
	    debug("Already mounted. mountflag=0");
	    $mountflag=0;
	    last;
	}
    }
    close($MOUNTP);
    return $mountflag;
}

sub initialize() {
    my $index;
    my $mountflag;
    my $hconfigf;
    my $partition;
    my $mountpoint;
    my $index=0;
    my $cf="$ENV{HOME}/$configfile";

    open($hconfigf, "<", $cf);
    if (not defined($hconfigf)) {
	debug("[FATAL] Could not open configuration file $configfile");
	exit(1);
    }
    while (<$hconfigf>) {
	if (m/^PART=([:a-zA-Z0-9_-]+) ([a-zA-Z0-9\/_-]+)$/) {
	    $partition=$1;
	    $mountpoint=$2;
	    push @partitions, $partition;
	    push @mountpoints, $mountpoint;
	    print "[$1][$2]\n";
	    if (! -d $mountpoint) {
		debug("[FATAL] invalid mountpoint \"$mountpoint\"");
		exit(1);
	    }
	    # each partitions needs an entry in @mounttime
	    # partitions that are already mounted are considered non of my business
	    push @mounttime, 0;
	    $mountflag=partition_is_not_mounted($index);
	    push @mypartitions, $mountflag;
	    if (! $mountflag) {
		debug("[INFO] Partition $partitions[$index] is already mounted at startup and will not be considered");
	    }
	    $index=$index+1;
	}
    }
}

sub unmount_inactive_partition {
    my $LSOFPIPE;
    my $pindex=shift;
    my $mountpoint = $mountpoints[$pindex];
    my $mounted=0;
    # now compare every line of lsof with $mounpoint
    # if any mach is found the partition will not be unmounted now
    open($LSOFPIPE, "/usr/bin/lsof|");
    if (not defined($LSOFPIPE)) {
	debug("[FATAL]could not execute lsof");
	exit(1);
    }
	
    while (<$LSOFPIPE>) {
	if (m/$mountpoint/) {
	    debug("[INFO] Partition $mountpoint is still in use");
	    $mounted=1;
	    last;
	}
    }
    close($LSOFPIPE);
    if ($mounted==0) {
	system("umount $mountpoint");
	$mounttime[$pindex]=0;
    }
}

initialize();
daemonize();

# main infinite loop
# 1. see if sysfs-entry for known device exists
# 2. if so check if device is not mounted and then mount
# 3. after some time of inactivity unmount the device

while (1)
{
    my $pindex=0;
    my $now = time();
    foreach $pindex (0..$#partitions)
    {
	unless ($mypartitions[$pindex]) {
	    next;
	}
	    
	debug("[INFO] Check if device node exists for $partitions[$pindex]");
	if ( -e "$prefix/$partitions[$pindex]")
	{
	    debug("[INFO] device node exists");
	    if ( partition_is_not_mounted($pindex))
	    {
		debug("[INFO] going to mount partition $mountpoints[$pindex].");
		system("mount $mountpoints[$pindex]");
		$mounttime[$pindex]=$now;
	    }
	}
	else { debug("[INFO] no device node found."); }
	if (($mounttime[$pindex] > 0) && ($now > ($mounttime[$pindex]+$inactive_timeout))) {
	    debug("[INFO] unmounting partition $mountpoints[$pindex]");
	    unmount_inactive_partition($pindex);
	}
    }
    debug("[INFO] daemon needs some rest...");
    sleep($daemon_timeout);
}

exit 0;
