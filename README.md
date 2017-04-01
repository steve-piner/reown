# Reown - change file and directory ownership

This script is for updating files and directories, updating the
ownership and group membership to correspond to the current
/etc/passwd and /etc/group.

The previous version of /etc/passwd and /etc/group is used to map from
the old user or group id/name to the new id.

The intended scenario for use is the case where a disk volume is
transferred from an old system to a new system. The old /etc/passwd
and /etc/group are still available, but the user/group ids no longer
match.

## Requirements

- Perl v5.20 or later (tested with v5.22, not verified with v5.20)
- Unix - this program only supported Unix style ownership.

## Usage

`reown.pl [options] files-or-directories`

| Options              | Description                                         |
| -------------------- | --------------------------------------------------- |
| `--passwd-file`      | Specify the passwd file to use                      |
| `--group-file`       | Specify the group file to use                       |
| `--[no-]update-uids` | Should UIDs be updated (default: true)              |
| `--[no-]update-gids` | Should GIDs be updated (default: true)              |
| `--missing-only`     | Only update missing users and groups                |
| `--dry-run`          | Go through the process, but do not change any files |
| `--backup-file`      | Save changes to the specified file                  |
| `--restore-file`     | Restore changes from a saved backup file            |
| `--verbose`          | Print each action to STDOUT before doing it         |
| `--help`             | A usage message                                     |

The most important options are the `--passwd-file` and `--group-file`
to use. These must specify the user and group that the ids are mapped
to, before they are mapped to the current user and group.

`--update-uids` and `--update-gids` are for specifying whether UIDs or
GIDs will be updated. If neither is specified then both are assumed.

If `--missing-only` is specified, only the files or directories which
do not have either a user name or a group name or both will be be
updated. This option is mostly of use when the filesystem has already
been partially updated.

When `--dry-run` is specified, the ownership/group membership is not
actually changed, and the 'chown' command is printed to standard
error.

`--backup-file` and `--restore-file` cause a backup file to be created
or loaded, to allow a mistake to be undone.

The backup is a text file with each line representing a record, each
record being three comma-delimited fields. The fields are in order the
UID, the GID, then the file or directory. The UID and GID are numeric,
and a value less than zero indicates no change. The file name has
unusual characters replaced with a tilde ('~') followed by the
two-digit hexidecimal byte representation.

The `--verbose` option displays found files or directories, the user
and group, and what they would map to.
