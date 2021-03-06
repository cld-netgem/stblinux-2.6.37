#!/usr/bin/perl -w

#
# STB Linux build system v2.1
# Copyright (C) 2011 Broadcom Corporation
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#
# usage: tools/config.pl defaults <target>
#
# <target> examples:
#   7335b0
#   7335b0_be
#   7335b0_be-opf
#   7335b0-kgdb
#   7335b0_be-small
#   7335b0-small-nohdd
#
use strict;
use warnings;
use File::Copy;
use POSIX;

my %linux = ( );
my %uclibc = ( );
my %busybox = ( );
my %vendor = ( );

my $topdir = getcwd();

my $uclibc_defaults = "defaults/config.uClibc";
my $busybox_defaults = "defaults/config.busybox";
my $vendor_defaults = "defaults/config.vendor";
my $arch_defaults_le = "defaults/config.arch-le";
my $arch_defaults_be = "defaults/config.arch-be";
my $linux_defaults = "";

my $linux_config = "linux-2.6.x/.config";
my $uclibc_config = "lib/uClibc/.config";
my $busybox_config = "user/busybox/.config";
my $vendor_config = "config/.config";
my $arch_config = "config.arch";

my @patchlist = ("lttng", "android", "newubi");
my %use_patch = ( );

my %defsuf = (
	"7118"	=> "-docsis",
	"7125"	=> "-docsis",
	"7400"	=> "-docsis",
	"7401"	=> "-docsis",
	"7403"	=> "-docsis",
	"7405"	=> "-docsis",
	"7420"	=> "-docsis",
);

my ($tgt, $chip, $be, $suffix) = ("","","","");

sub read_cfg($$)
{
	my($file, $h) = @_;

	open(F, "<${file}") or die "can't open ${file}: $!";
	while(<F>) {
		if(m/^# (\S+) is not set/) {
			$$h{$1} = "n";
		} elsif(m/^(\w+)=(.+)$/) {
			$$h{$1} = $2;
		}
	}
	close(F);
}

sub write_cfg($$$)
{
	my($in, $out, $h) = @_;
	my @outbuf = ( );

	open(IN, "<${in}") or die "can't open ${in}: $!";

	while(<IN>) {
		if(m/^# (\S+) is not set/ || m/^(\w+)=(.+)$/) {
			my $var = $1;
			my $val = $$h{$var};

			if(defined($val)) {
				if($val eq "n") {
					push(@outbuf, "# $var is not set\n");
				} else {
					push(@outbuf, "${var}=${val}\n");
				}
				$$h{$var} = undef;
			} else {
				push(@outbuf, $_);
			}
		} else {
			push(@outbuf, $_);
		}
	}
	close(IN);

	unlink($out);
	open(OUT, ">${out}") or die "can't open ${out}: $!";

	foreach my $x (@outbuf) {
		print OUT $x;
	}

	foreach my $var (sort { $a cmp $b } keys(%$h)) {
		my $val = $$h{$var};

		if(! defined($val)) {
			next;
		}

		if($val eq "n") {
			print OUT "# $var is not set\n";
		} else {
			print OUT "${var}=${val}\n";
		}
	}
	close(OUT);
}

sub whitelist_cfg($$)
{
	my($cfg, $whitelist) = @_;

	foreach my $x (keys(%$cfg)) {
		if(defined($$cfg{$x})) {
			if($$cfg{$x} eq "y") {
				if(! defined($$whitelist{$x})) {
					$$cfg{$x} = "n";
				}
			} elsif($$cfg{$x} eq "n") {
				if(defined($$whitelist{$x}) &&
						$$whitelist{$x} eq "y") {
					$$cfg{$x} = "y";
				}
			}
			$$whitelist{$x} = undef;
		}
	}
	foreach my $var (sort { $a cmp $b } keys(%$whitelist)) {
		my $val = $$whitelist{$var};

		if(defined($val)) {
			$$cfg{$var} = $val;
		}
	}
}

sub override_cfg($$)
{
	my($cfg, $newcfg) = @_;

	foreach my $x (keys(%$cfg)) {
		if(defined($$cfg{$x}) && defined($$newcfg{$x})) {
			$$cfg{$x} = $$newcfg{$x};
			$$newcfg{$x} = undef;
		}
	}
	foreach my $var (sort { $a cmp $b } keys(%$newcfg)) {
		my $val = $$newcfg{$var};

		if(defined($val)) {
			$$cfg{$var} = $val;
		}
	}
}

sub def($$$)
{
	my($cfg, $name, $val) = @_;

	if(! defined($$cfg{$name})) {
		$$cfg{$name} = $val;
	}
}

sub get_tgt($)
{
	($tgt) = (@_);

	if(! defined($tgt)) {
		die "no target specified";
	}

	if($tgt !~ m/^([0-9]+[a-z][0-9])(_be)?(-\S+)?$/) {
		die "invalid target format: $tgt";
	}
	($chip, $be, $suffix) = ($1, defined($2) ? 1 : 0,
		defined($3) ? $3 : "");

	$linux_defaults = "linux-2.6.x/arch/mips/configs/bcm${chip}_defconfig";
	if(! -e $linux_defaults) {
		print "\n";
		print "ERROR: No Linux configuration for $chip\n";
		print "Attempted to open: $linux_defaults\n";
		print "\n";
		exit 1;
	}
}

################################################
# sub expand_modifiers($implies, $list)
#
# DESCRIPTION:
#   Expands modifiers according to the rules given
#   by the %implies.  Eliminates duplicate modifiers.
# PARAMS:
#   $implies is a hash ref of implied modifier actions.
#   $list is a hyphenated string of successive modifiers.
# RETURNS:
#   Final hyphenated string of modifiers.
################################################
sub expand_modifiers($$)
{
	my $implies = shift;
	my $t = shift;
	my @a = split /-/, $t;
	my ($nsubs, $iters, $MAX_ITERS) = (0,0,15);

	# Expand out modifiers.
	do {
		$nsubs = 0;
		for (my $i=$#a; $i>=0; $i--) {
			my $v = $a[$i];
			if ($implies->{$v}) {
				splice(@a,$i,1,@{$implies->{$v}},uc($v));
				$nsubs++;
			}
		}
	} while ($nsubs && $iters++ < $MAX_ITERS);

	die "Error: modifiers have a mutually recursive definition; fix \%implies!"
		if ($iters >= $MAX_ITERS);

	# Now we uniquify elements while preserving order from right.
	my @aa = reverse map { lc } @a;
	@a = ();
	my %h;
	while (@aa) {
		my $x = shift @aa;
		next if $h{$x};
		$h{$x} = 1;
		unshift @a, $x;
	}
	return join('-',@a);
}

sub get_chiplist()
{
	my @defs = glob("linux-2.6.x/arch/mips/configs/bcm*_defconfig");
	my @out = ( );

	foreach (@defs) {
		if(m/bcm([0-9]+[a-z][0-9])_defconfig/) {
			push(@out, $1);
		}
	}
	return(@out);
}

sub set_opt($$)
{
	my($file, $settings) = @_;
	my %h;

	read_cfg($file, \%h);

	foreach my $x (@$settings) {
		if($x !~ /^(\w+)=(.+)$/) {
			die "Invalid setting: $x";
		}
		my($key, $val) = ($1, $2);
		if(defined($h{$key})) {
			if($h{$key} eq $val) {
				print "$key: no change\n";
			} else {
				print "$key: change from '$h{$key}' to ".
					"'$val'\n";
			}
		} else {
			print "$key: add new option with value '$val'\n";
		}
		$h{$key} = $val;
	}

	write_cfg($file, $file, \%h);
}

sub test_opt($$)
{
	my($file, $settings) = @_;
	my %h;
	my $result = 0;

	read_cfg($file, \%h);

	foreach my $key (@$settings) {
		if(!defined($h{$key}) || ($h{$key} eq 'n')) {
			$result = 1;
		}
	}

	exit $result;
}

#
# MAIN
#

my $cmd = shift @ARGV;
if(! defined($cmd)) {
	die "usage: config.pl <cmd>\n";
}
if($cmd eq "defaults" || $cmd eq "quickdefaults") {
	my $quick = $cmd eq "quickdefaults";

	get_tgt(shift @ARGV);

	read_cfg($linux_defaults, \%linux);
	read_cfg($uclibc_defaults, \%uclibc);
	read_cfg($busybox_defaults, \%busybox);
	read_cfg($vendor_defaults, \%vendor);

	# basic hardware support

	if(defined($linux{"CONFIG_BRCM_MOCA"})) {
		$vendor{"CONFIG_USER_NONFREE_MOCA"} = "y";
		$vendor{"CONFIG_USER_NONFREE_MOCA_GEN1"} = "n";
		$vendor{"CONFIG_USER_NONFREE_MOCA_GEN2"} = "n";
		$vendor{"CONFIG_USER_NONFREE_MOCA_GEN3"} = "n";

		if(defined($linux{"CONFIG_BRCM_HAS_MOCA_11"})) {
			$vendor{"CONFIG_USER_NONFREE_MOCA_GEN1"} = "y";
		} elsif(defined($linux{"CONFIG_BRCM_HAS_MOCA_11_LITE"})) {
			$vendor{"CONFIG_USER_NONFREE_MOCA_GEN1"} = "y";
		} elsif(defined($linux{"CONFIG_BRCM_HAS_MOCA_11_PLUS"})) {
			$vendor{"CONFIG_USER_NONFREE_MOCA_GEN2"} = "y";
		} elsif(defined($linux{"CONFIG_BRCM_HAS_MOCA_20"})) {
			$vendor{"CONFIG_USER_NONFREE_MOCA_GEN3"} = "y";
		}
	}

	if(defined($linux{"CONFIG_BRCM_PM"}) ||
			defined($linux{"CONFIG_BRCM_CPU_DIV"})) {
		$vendor{"CONFIG_USER_BRCM_PM"} = "y";
	}

	# set default modifiers for each chip

	my $shortchip = $chip;
	$shortchip =~ s/[^0-9].*//;

	if(defined($defsuf{$shortchip})) {
		$suffix = $defsuf{$shortchip}.$suffix;
	}

	# The %implies hash indicates what modifiers imply other modifiers.
	# If X implies Y-Z, then the modications will be applied in this
	# order: Y,Z,X.
	my %implies = ('pal' => 'small-nonet-nousb-nohdd',
		       'ikos' => 'small-kdebug-nousb-nomtd-nohdd',
		       'kgdb' => 'kdebug',
		       'android' => 'ipv6',
	    );

	# Munge the '%implies' hash so that its values become array refs.
	map { $_ = [split /-/] } values %implies;

	my $old_suffix = $suffix;
	$suffix = expand_modifiers(\%implies, $suffix);

	# print "info: '$old_suffix' expanded to '$suffix'.\n";

	my (%vendor_w, %busybox_w, %linux_o, %vendor_o, %busybox_o);

	# allow stacking more than one modifier (e.g. -small-nohdd-nousb)
	while(defined($suffix) && ($suffix ne "")) {
		if($suffix !~ m/^-([^-]+)(-\S+)?/) {
			print "\n";
			print "ERROR: Invalid modifier '$suffix' in '$tgt'\n";
			print "\n";
			exit 1;
		}
		(my $mod, $suffix) = ($1, $2);

		if($mod eq "small") {

			# reduced footprint (-small builds)

			$uclibc{"PTHREADS_DEBUG_SUPPORT"} = "n";
			$uclibc{"DODEBUG"} = "n";
			$uclibc{"DOSTRIP"} = "y";

			# disable all but a few features

			read_cfg("defaults/whitelist.vendor-small",
				\%vendor_w);
			read_cfg("defaults/whitelist.busybox-small",
				\%busybox_w);

			whitelist_cfg(\%vendor, \%vendor_w);
			whitelist_cfg(\%busybox, \%busybox_w);

			$linux{"CONFIG_NETWORK_FILESYSTEMS"} = "n";
			$linux{"CONFIG_INPUT"} = "n";
			$linux{"CONFIG_VT"} = "n";
		} elsif($mod eq "ikos") {

			# IKOS pre-tapeout emulation (internal Broadcom use)
			# 'ikos' implies '-small-kdebug-nousb-nomtd-nohdd'

			$linux{"CONFIG_BRCM_DEBUG_OPTIONS"} = "y";
			$linux{"CONFIG_BRCM_IKOS"} = "y";
			$linux{"CONFIG_BRCM_IKOS_DEBUG"} = "y";
			$linux{"CONFIG_BRCM_FORCED_DRAM0_SIZE"} = "32";
			$linux{"CONFIG_BRCM_FORCED_DRAM1_SIZE"} = "0";
			$linux{"CONFIG_BRCM_PM"} = "n";
			$vendor{"CONFIG_USER_BRCM_PM"} = "n";
		} elsif($mod eq "kgdb") {

			# KGDB debugging (implies -kdebug)
			# 'kgdb' implies '-kdebug'

			$linux{"CONFIG_KGDB"} = "y";
			$linux{"CONFIG_KGDB_SERIAL_CONSOLE"} = "y";
			$linux{"CONFIG_KGDB_TESTS"} = "n";
			$linux{"CONFIG_KGDB_LOW_LEVEL_TRAP"} = "n";
			$linux{"CONFIG_KGDB_KDB"} = "n";
		} elsif($mod eq "gdb") {

			# Native GDB CLI on target (warning: GPLv3 code)

			$vendor{"CONFIG_USER_GDB_GDB"} = "y";
		} elsif($mod eq "opf") {

			# Oprofile - non-debug kernel with CONFIG_OPROFILE set

			$linux{"CONFIG_PROFILING"} = "y";
			$linux{"CONFIG_OPROFILE"} = "y";
			$linux{"CONFIG_JBD2_DEBUG"} = "n";
			$linux{"CONFIG_MARKERS"} = "n";
			$linux{"CONFIG_NET_DROP_MONITOR"} = "n";
			$linux{"CONFIG_FTRACE_STARTUP_TEST"} = "n";

			$vendor{"CONFIG_USER_PROFILE_OPROFILE"} = "y";
		} elsif($mod eq "kdebug") {

			# Kernel debug info + extra sanity checks

			read_cfg("defaults/override.linux-kdebug", \%linux_o);
			override_cfg(\%linux, \%linux_o);
			def(\%linux, "CONFIG_BRCM_IKOS", "n");
			def(\%linux, "CONFIG_KGDB", "n");
		} elsif($mod eq "netfilter") {

			# Enable netfilter and iptables

			read_cfg("defaults/override.linux-netfilter",
				\%linux_o);
			override_cfg(\%linux, \%linux_o);
			$vendor{"CONFIG_USER_IPTABLES_IPTABLES"} = "y";
		} elsif($mod eq "ipv6") {

			# Enable IPv6

			read_cfg("defaults/override.linux-ipv6",
				\%linux_o);
			override_cfg(\%linux, \%linux_o);

			# FIXME: missing dependencies
			# $vendor{"CONFIG_USER_DHCPCV6_DHCPCV6"} = "y";

			$uclibc{"UCLIBC_HAS_IPV6"} = "y";
			$busybox{"CONFIG_FEATURE_IPV6"} = "y";
			$busybox{"CONFIG_PING6"} = "y";
		} elsif($mod eq "docsis") {

			# enable tftp server for DOCSIS firmware download

			$busybox{"CONFIG_UDPSVD"} = "y";
			$busybox{"CONFIG_TFTPD"} = "y";
		} elsif($mod eq "nousb") {
			$linux{"CONFIG_USB"} = "n";
		} elsif($mod eq "nomtd") {
			$vendor{"CONFIG_USER_MTDUTILS"} = "n";
			$linux{"CONFIG_MTD"} = "n";
			# JFFS2, UBIFS depend on CONFIG_MTD
			$linux{"CONFIG_SQUASHFS"} = "n";
		} elsif($mod eq "nohdd") {

			# Disable all hard disk support (SATA or USB)

			$busybox{"CONFIG_MKSWAP"} = "n";
			$busybox{"CONFIG_SWAPONOFF"} = "n";
			$busybox{"CONFIG_FDISK"} = "n";
			$vendor{"CONFIG_USER_GDISK_GDISK"} = "n";
			$vendor{"CONFIG_USER_E2FSPROGS_E2FSCK_E2FSCK"} = "n";
			$vendor{"CONFIG_USER_E2FSPROGS_MISC_MKE2FS"} = "n";
			$vendor{"CONFIG_USER_E2FSPROGS_MISC_TUNE2FS"} = "n";
			$linux{"CONFIG_ATA"} = "n";
			$linux{"CONFIG_SCSI"} = "n";

			# disable all non-MTD filesystems
			$linux{"CONFIG_EXT4_FS"} = "n";
			$linux{"CONFIG_JBD2"} = "n";
			$linux{"CONFIG_FUSE_FS"} = "n";
			$linux{"CONFIG_ISO9660_FS"} = "n";
			$linux{"CONFIG_UDF_FS"} = "n";
			$linux{"CONFIG_FAT_FS"} = "n";
			$linux{"CONFIG_VFAT_FS"} = "n";
			$linux{"CONFIG_MSDOS_FS"} = "n";
			$linux{"CONFIG_NLS"} = "n";
		} elsif($mod eq "nonet") {
			# busybox compile fails with no brctl
			# $busybox{"CONFIG_BRCTL"} = "n";
			$busybox{"CONFIG_FTPGET"} = "n";
			$busybox{"CONFIG_FTPPUT"} = "n";
			$busybox{"CONFIG_HOSTNAME"} = "n";
			$busybox{"CONFIG_IFCONFIG"} = "n";
			$busybox{"CONFIG_IP"} = "n";
			$busybox{"CONFIG_NETSTAT"} = "n";
			$busybox{"CONFIG_PING"} = "n";
			$busybox{"CONFIG_ROUTE"} = "n";
			$busybox{"CONFIG_TELNET"} = "n";
			$busybox{"CONFIG_TELNETD"} = "n";
			$busybox{"CONFIG_TFTP"} = "n";
			$busybox{"CONFIG_UDHCPC"} = "n";
			$busybox{"CONFIG_VCONFIG"} = "n";
			$busybox{"CONFIG_WGET"} = "n";
			$busybox{"CONFIG_ZCIP"} = "n";
			$linux{"CONFIG_NET"} = "n";
			$vendor{"CONFIG_USER_NONFREE_MOCA"} = "n";
		} elsif($mod eq "lttng") {

			# Enable LTTng

			$use_patch{'lttng'} = 1;

			read_cfg("defaults/override.linux-lttng", \%linux_o);
			override_cfg(\%linux, \%linux_o);

			$vendor{"CONFIG_USER_LTT_CONTROL"} = "y";
			
			$busybox{"CONFIG_FEATURE_FIND_PRUNE"} = "y";
			$busybox{"CONFIG_FEATURE_FIND_PATH"} = "y";
		} elsif($mod eq "android") {

			# Enable Android

			$use_patch{'android'} = 1;

			read_cfg("defaults/override.linux-android", \%linux_o);
			override_cfg(\%linux, \%linux_o);
		} elsif($mod eq "newubi") {

			# UBI/UBIFS backport from the mainline MTD tree

			$use_patch{'newubi'} = 1;
		} elsif($mod eq "lxc") {

			# Enable LXC containers

			read_cfg("defaults/override.linux-lxc", \%linux_o);
			override_cfg(\%linux, \%linux_o);

			$vendor{"CONFIG_USER_LXC_LXC"} = "y";
			$vendor{"CONFIG_LIB_LIBCAP"} = "y";

			$busybox{"CONFIG_GETOPT"} = "y";
			$busybox{"CONFIG_FEATURE_GETOPT_LONG"} = "y";
			$busybox{"CONFIG_ID"} = "y";
		} elsif($mod eq "xfs") {

			# Enable XFS file system

			$linux{"CONFIG_XFS_FS"} = "y";
			$linux{"CONFIG_XFS_QUOTA"} = "n";
			$linux{"CONFIG_XFS_POSIX_ACL"} = "y";
			$linux{"CONFIG_XFS_RT"} = "y";
			$linux{"CONFIG_XFS_DEBUG"} = "n";
			$vendor{"CONFIG_USER_XFS_XFSPROGS"} = "y";
		} else {
			print "\n";
			print "ERROR: Unrecognized suffix '$mod' in '$tgt'\n";
			print "\n";
			exit 1;
		}
	}

	# overrides based on endian setting

	if($be == 0) {
		$linux{"CONFIG_CPU_LITTLE_ENDIAN"} = "y";
		$linux{"CONFIG_CPU_BIG_ENDIAN"} = "n";

		$uclibc{"ARCH_LITTLE_ENDIAN"} = "y";
		$uclibc{"ARCH_WANTS_LITTLE_ENDIAN"} = "y";
		$uclibc{"ARCH_BIG_ENDIAN"} = "n";
		$uclibc{"ARCH_WANTS_BIG_ENDIAN"} = "n";
		$uclibc{"CROSS_COMPILER_PREFIX"} = '"mipsel-linux-"';

		$busybox{"CONFIG_CROSS_COMPILER_PREFIX"} = '"mipsel-linux-"';
	} else {
		$linux{"CONFIG_CPU_LITTLE_ENDIAN"} = "n";
		$linux{"CONFIG_CPU_BIG_ENDIAN"} = "y";

		$uclibc{"ARCH_LITTLE_ENDIAN"} = "n";
		$uclibc{"ARCH_WANTS_LITTLE_ENDIAN"} = "n";
		$uclibc{"ARCH_BIG_ENDIAN"} = "y";
		$uclibc{"ARCH_WANTS_BIG_ENDIAN"} = "y";
		$uclibc{"CROSS_COMPILER_PREFIX"} = '"mips-linux-"';

		$busybox{"CONFIG_CROSS_COMPILER_PREFIX"} = '"mips-linux-"';
	}

	# misc

	$busybox{"CONFIG_PREFIX"} = "\"$topdir/romfs\"";

	my $CC = $be ? "mips-linux-gcc" : "mipsel-linux-gcc";
	my $sysroot = `$CC --print-sysroot`;
	if(WEXITSTATUS($?) != 0) {
		die "can't invoke $CC to find sysroot";
	}
	$sysroot =~ s/\s//g;
	$uclibc{"KERNEL_HEADERS"} = "\"$sysroot/usr/include\"";

	# clean up the build system if switching targets
	# "quick" mode (skip distclean) is for testing only
	if(-e ".target" && ! $quick) {
		open(F, "<.target") or die "can't read .target";
		my $oldtgt = <F>;
		close(F);

		$oldtgt =~ s/[\r\n]//g;
		if($tgt ne $oldtgt) {
			print "\n";
			print "Switching from target $oldtgt to $tgt\n";
			print "\n";
			print "Forcing distclean in 5 seconds - ".
				"HIT ^C NOW TO ABORT.\n";
			print "\n";
			sleep(5);
			system("make distclean");
		}
		unlink(".target");
	}

	# apply/reverse kernel patches

	my $cwd = getcwd();
	chdir("linux-2.6.x") or die;

	foreach my $x (@patchlist) {
		if(defined($use_patch{$x})) {
			if(! -e "patch/.applied-$x") {
				system("patch -p2 < patch/$x.patch");

				my $ret = WEXITSTATUS($?);
				if($ret != 0) {
					die "patch exited with code $ret";
				}
				open(F, ">patch/.applied-$x") or die;
				close(F);
			}
		} else {
			if(-e "patch/.applied-$x") {
				system("patch -R -p2 < patch/$x.patch");

				my $ret = WEXITSTATUS($?);
				if($ret != 0) {
					die "patch exited with code $ret";
				}
				unlink("patch/.applied-$x") or die;
			}
		}
	}
	chdir($cwd) or die;

	open(F, ">.target") or die "can't write .target";
	print F "$tgt\n";
	close(F);

	# write out the new configuration
	write_cfg($linux_defaults, $linux_config, \%linux);
	write_cfg($uclibc_defaults, $uclibc_config, \%uclibc);
	write_cfg($busybox_defaults, $busybox_config, \%busybox);
	write_cfg($vendor_defaults, $vendor_config, \%vendor);

	unlink($arch_config);
	copy($be ? $arch_defaults_be : $arch_defaults_le, $arch_config) or
		die "can't create $arch_config";
} elsif($cmd eq "save_defaults") {
	get_tgt(shift @ARGV);

	read_cfg($linux_config, \%linux);
	read_cfg($uclibc_config, \%uclibc);
	read_cfg($busybox_config, \%busybox);
	read_cfg($vendor_config, \%vendor);

	write_cfg($linux_config, $linux_defaults, \%linux);
	write_cfg($uclibc_config, $uclibc_defaults, \%uclibc);
	write_cfg($busybox_config, $busybox_defaults, \%busybox);
	write_cfg($vendor_config, $vendor_defaults, \%vendor);
} elsif($cmd eq "initramfs") {
	read_cfg($linux_config, \%linux);

	$linux{"CONFIG_BLK_DEV_INITRD"} = "y";

	$linux{"CONFIG_BLK_DEV_RAM"} = "y";
	$linux{"CONFIG_BLK_DEV_RAM_COUNT"} = "16";
	$linux{"CONFIG_BLK_DEV_RAM_SIZE"} = "8192";
	$linux{"CONFIG_BLK_DEV_RAM_BLOCKSIZE"} = "1024";
	$linux{"CONFIG_BLK_DEV_XIP"} = "n";
	$linux{"CONFIG_PROBE_INITRD_HEADER"} = "n";

	$linux{"CONFIG_INITRAMFS_SOURCE"} = "\"$topdir/romfs ".
		"$topdir/misc/initramfs.dev\"";
	$linux{"CONFIG_INITRAMFS_ROOT_UID"} = getuid();
	$linux{"CONFIG_INITRAMFS_ROOT_GID"} = getgid();

	$linux{"CONFIG_INITRAMFS_COMPRESSION_NONE"} = "y";
	$linux{"CONFIG_INITRAMFS_COMPRESSION_GZIP"} = "n";
	$linux{"CONFIG_INITRAMFS_COMPRESSION_BZIP2"} = "n";
	$linux{"CONFIG_INITRAMFS_COMPRESSION_LZMA"} = "n";
	$linux{"CONFIG_INITRAMFS_COMPRESSION_LZO"} = "n";

	write_cfg($linux_config, $linux_config, \%linux);
} elsif($cmd eq "noinitramfs") {
	read_cfg($linux_config, \%linux);

	$linux{"CONFIG_INITRAMFS_SOURCE"} = '""';

	write_cfg($linux_config, $linux_config, \%linux);
} elsif($cmd eq "chiplist") {
	foreach (get_chiplist()) {
		print "$_\n";
	}
} elsif($cmd eq "buildlist") {
	foreach (get_chiplist()) {
		print "$_\n";
		# 73xx, 74xx generally need BE builds
		# 70xx, 71xx, 72xx generally do not
		if(m/^7[34]/ || m/^7038/) {
			print "${_}_be\n";
		}
	}
} elsif($cmd eq "linux") {
	set_opt($linux_config, \@ARGV);
} elsif($cmd eq "busybox") {
	set_opt($busybox_config, \@ARGV);
} elsif($cmd eq "uclibc") {
	set_opt($uclibc_config, \@ARGV);
} elsif($cmd eq "vendor") {
	set_opt($vendor_config, \@ARGV);
} elsif($cmd eq "test_linux") {
	test_opt($linux_config, \@ARGV);
} elsif($cmd eq "test_busybox") {
	test_opt($busybox_config, \@ARGV);
} elsif($cmd eq "test_uclibc") {
	test_opt($uclibc_config, \@ARGV);
} elsif($cmd eq "test_vendor") {
	test_opt($vendor_config, \@ARGV);
} else {
	die "unrecognized command: $cmd";
}
