#!/usr/bin/perl

use strict;

my $prefix="/dev/disk/by-id";
my @partitions=("usb-CREATIVE_ZEN_Stone_Plus_F03A092D62B24C19-0:0-part1",
                "usb-Multi_Flash_Reader_058F0O1111B1-0:0-part1",
		"usb-Sony_DSC-W115_D395A071B042-part1");
my @mountpoints=("/media/zenstone", "/media/kartenleser", "/media/cybershot");
my @mounttime;
my @mypartition;
my $daemon_timeout=15;
my $inactive_timeout=600;
my $debug=1;
my $logfile="automounter.log";
my $logto="file";

sub debug {
    my $message = shift;
    my $hlogfile;
    if ($debug) {
	if ($logto =~ /file/)
	{
	    open($hlogfile, ">>", $logfile) or die "Cannot open logfile $logfile for writing";
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
    debug("Check if anything is mounted to $mountpoints[$pindex]");
    open($MOUNTP,"/bin/mount|") or die "could not execute mount command";
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
    if ($#mountpoints != $#partitions) {
	debug("[FATAL] Number of mountpoints doesn't match number of partitions");
	exit(1);
    }
    # each partitions needs an entry in @mounttime
    # partitions that are already mounted are considered non of my business
    foreach $index (0..$#partitions) {
	$mountflag=partition_is_not_mounted($index);
	push @mounttime, 0;
	push @mypartitions, $mountflag;
	if ($mountflag) {
	    debug("[INFO] Partition $partitions[$index] is already mounted at startup and will not be considered");
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
    open($LSOFPIPE, "/usr/bin/lsof|") or die "could not execute lsof";
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
