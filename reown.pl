#!/usr/bin/perl
use v5.22;
use strict;
use warnings;
use autodie;

use constant PASSWD_FILE => '/mnt/root-old/etc/passwd';
use constant GROUP_FILE  => '/mnt/root-old/etc/group';

use feature 'signatures';
no warnings 'experimental::signatures';
use Getopt::Long 'GetOptions';
use File::Basename 'basename';
use File::Find 'find';

sub help {
    my $name = basename $0;
    print << "HELP";
$name: Reapply user and group ownership from external passwd and group files

Usage:
  $name [options] files-or-directories

Options
  --passwd-file       Specify the passwd file to use.
  --group-file        Specify the group file to use
  --[no-]update-uids  Should UIDs be updated (default: true)
  --[no-]update-gids  Should GIDs be updated (default: true)
  --missing-only      Only update missing users and groups
  --dry-run           Go through the process, but do not change any files
  --backup-file       Save changes to the specified file
  --restore-file      Restore changes from a saved backup file
  --verbose           Print each action to STDOUT before doing it
  --help              This usage message

If neither --update-uids nor --update-gids is specified then it is treated as
if both were specified.
HELP
}

sub read_file($file, $fields, @indexes) {
    my @records;
    my %indexes;
    open my $fh, '<', $file;
    while (<$fh>) {
        chomp $_;
        my $record = { };
        @$record{@$fields} = split ':', $_;
        push @records, $record;
        $indexes{$_}{$record->{$_}} = $record for @indexes;
    }
    close $fh;
    return \@records, \%indexes;
}

sub escape_line($uid, $gid, $file) {
    my $escaped = $file;
    $escaped =~ s/([~\0-\037])/sprintf '~%02X', ord $1/ge;
    return join ',', $uid, $gid, $escaped;
}

sub unescape_line($line) {
    chomp $line;
    my ($uid, $gid, $escaped) = split ',', $line, 3;
    my $file = $escaped;
    $file =~ s/~([0-9A-F]{2})/chr hex $1/ge; 
    return $uid, $gid, $file;
}

sub dry_run_chown($uid, $gid, $file) {
    say STDERR "chown $uid, $gid, $file";
    return {};
}

sub perform_chown($uid, $gid, $file) {
    my $status = {};
    chown $uid, $gid, $file or do {
        $status->{error} = "$file: $!";
    };
    return $status;
}

sub backup_wrapper($chown, $backup_fh) {
    return sub {
        say {$backup_fh} escape_line(@_);
        my $status = $chown->(@_);
    };
}

my $passwd_file = PASSWD_FILE;
my $group_file  = GROUP_FILE;
my $update_uids = 0;
my $update_gids = 0;
my $missing     = 0;
my $dry_run     = 0;
my $verbose     = 0;
my $help        = 0;
my $backup_file;
my $restore_file;

my $ok = GetOptions(
    'passwd-file=s'  => \$passwd_file,
    'group-file=s'   => \$group_file,
    'update-uids!'   => \$update_uids,
    'update-gids!'   => \$update_gids,
    'missing-only!'  => \$missing,
    'dry-run!'       => \$dry_run,
    'backup-file=s'  => \$backup_file,
    'restore-file=s' => \$restore_file,
    'verbose!'       => \$verbose,
    'help'           => \$help,
);

$help = 1 unless $ok;

if ($help) {
    help;
    exit 1;
}

unless ($update_uids or $update_gids) {
    $update_uids = $update_gids = 1;
}

my $chown = $dry_run ? \&dry_run_chown : \&perform_chown;
my $backup_fh;

if (defined $backup_file) {
    open $backup_fh, '>', $backup_file;
    $chown = backup_wrapper $chown, $backup_fh;
}

if (defined $restore_file) {
    open my $fh, '<', $restore_file;
    my $status = 0;
    while (<$fh>) {
        my ($uid, $gid, $file) = unescape_line $_;
        if (-e $file) {
            my $status = $chown->($uid, $gid, $file);
            if ($status->{error}) {
                say STDERR $status->{error};
                $status = 1;
            };
        }
        else {
            say STDERR "'$file' not found";
            $status = 1;
        }
    }
    close $fh;
    exit $status;
}

my ($users, $user_indexes) = read_file($passwd_file,
    [qw(user password uid gid comment home shell)],
    qw(user uid),
);

my ($groups, $group_indexes) = read_file($group_file,
    [qw(group password gid members)],
    qw(group gid),
);

my (%uid, %gid, %user, %group);

my $wanted = sub {
    my ($uid, $gid) = (stat $_)[4, 5];

    my $current_user  = $uid{$uid} //= getpwuid($uid);
    my $current_group = $gid{$gid} //= getgrgid($gid);

    my $old_user  = $user_indexes->{uid}{$uid}{user};
    my $old_group = $group_indexes->{gid}{$gid}{group};

    my $new_old_uid = $user{$old_user}   //= getpwnam($old_user);
    my $new_old_gid = $group{$old_group} //= getgrnam($old_group);

    if ($verbose) {
        say STDERR $File::Find::name;

        say STDERR "User:  $uid, current: ",
            $current_user || '(unknown)',
            ', former: ', $old_user || '(unknown)',
            ' ', $new_old_uid ? "(now $new_old_uid)" : '-';
        say STDERR "Group: $gid, current: ",
            $current_group || '(unknown)',
            ', former: ', $old_group || '(unknown)',
            ' ', $new_old_gid ? "(now $new_old_gid)" : '-';
    }

    my ($old_uid, $old_gid) = (-1, -1);

    for (1) {
        next unless $update_uids;
        next unless $new_old_uid;

        next if $current_user and $missing;

        $old_uid = $new_old_uid;
    }

    for (1) {
        next unless $update_gids;
        next unless $new_old_gid;

        next if $current_group and $missing;

        $old_gid = $new_old_gid;
    }

    unless ($old_uid < 0 and $old_gid < 0) {
        $chown->($old_uid, $old_gid, $File::Find::name);
    }
};

find ($wanted, @ARGV);
