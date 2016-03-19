#!/usr/bin/env perl
# ABSTRACT: Redo for-linux branch.

use strict;
use warnings;
use Git::Wrapper ();
use File::chdir;

$ENV{GPG_TTY} = qx{tty};

use constant FORCE_REBASE  => $ENV{FORCE_REBASE};
use constant LOCAL_UPDATES => $ENV{LOCAL_UPDATES};
use constant DO_ATTIC      => $ENV{ATTIC};

use constant UPSTREAM_REPO   => 'upstream';
use constant UPSTREAM_BRANCH => 'master';
use constant UPSTREAM_REF    => 'refs/remotes/'
  . UPSTREAM_REPO . '/'
  . UPSTREAM_BRANCH;

use constant MY_REPO => 'kentnl';

use constant QUEUE_BRANCH        => 'for-gentoo';
use constant QUEUE_THREAD_PREFIX => 'kentnl/';

use constant STAGING_BRANCH => 'staging-for-gentoo';

my $GW = Git::Wrapper->new("/usr/local/gentoo");

my (@MERGE_LIST) = (    #
    'bump-PDF-Create',
    'fix-Period-names',
    'bump-Perl-Critic',
);

my %NEEDS = (           #

);
my (@STAGING_LIST) = (    #
);
my (@ATTIC) = ( 'perl-dist-zilla', );

push @STAGING_LIST, @ATTIC if DO_ATTIC;

refresh_remote(UPSTREAM_REPO) if not LOCAL_UPDATES;

unless ( should_rebase() ) {
    print '* ' . QUEUE_BRANCH . ' is ahead of ' . UPSTREAM_REF . " stopping\n";
    exit 0;
}

if ( not LOCAL_UPDATES ) {
    upload( UPSTREAM_REF . ':master' );

# All branches in @MERGE_LIST are also in
#   ref/braches/QUEUE_THREAD_PREFIX/<BRANCHNAME>
#
# All are designed to track "UPSTREAM_REF", ie:
#
#    upstream/master .. kentnl/topicname
#
# This rebases all "kentnl/topicname" onto "upstream/master" when upstream/master changes.

    for my $target (@MERGE_LIST) {
        rebase_preferred( $target, UPSTREAM_REF );
        upload( real_name($target) );
    }

# All these topic branches are then played out in linear order
# on top of each other and upstream/master, creating a new branch "for-gentoo" ( QUEUE_BRANCH )
#
# so
#
#      - upstream/master .. kentnl/a
#      - upstream/master .. kentnl/b
#
# becomes:
#
#      - upstream/master .. kentnl/a .. kentnl/b

    copy_branch( UPSTREAM_REF, QUEUE_BRANCH );

    merge_rebase( QUEUE_THREAD_PREFIX . $_ => QUEUE_BRANCH ) for @MERGE_LIST;

    upload(QUEUE_BRANCH);
}
if (LOCAL_UPDATES) {

  # This is the same logic as above, but for a secondary class of branches
  # which are only "Staging" quality, and are thus absent from the upload queue.
  #
  # They merge into a second branch "STAGING BRANCH"
  # which is itself, fast-forward from QUEUE_BRANCH
  #
  # resulting in:
  #
  #   upstream/master
  #     ... ( lots of branches )
  #       ... for-gentoo
  #         ... ( more branches )
  #            ... staging-for-gentoo
  #
    rebase_preferred( $_ => UPSTREAM_REF ) for @STAGING_LIST;
    copy_branch( QUEUE_BRANCH, STAGING_BRANCH );
    merge_rebase( $_ => STAGING_BRANCH ) for @STAGING_LIST;
}

sub Git::Wrapper::RUN_DIRECT {
    my ( $self, $cmd, @args ) = @_;
    my ( $parts, $stdin ) = Git::Wrapper::_parse_args( $cmd, @args );
    my (@cmd) = ( $self->git, @{$parts} );
    local $CWD = $self->dir unless $cmd eq 'clone';
    system(@cmd);
    if ($?) {
        die Git::Wrapper::Exception->new(
            output => [],
            error  => [],
            status => $? >> 8,
        );
    }
    return $?;
}

sub should_rebase {
    return 1 if FORCE_REBASE;
    return 1 if LOCAL_UPDATES;
    return 1 unless x_aheadof_y( QUEUE_BRANCH, UPSTREAM_REF );
    return 0;
}

sub remote_names { $GW->remote() }

sub real_name {
    my ($branchname) = @_;
    if ( grep { $_ eq $branchname } @MERGE_LIST ) {
        return QUEUE_THREAD_PREFIX . $branchname;
    }
    if ( grep { $_ eq $branchname } @STAGING_LIST ) {
        return $branchname;
    }
    die "Cant resolve $branchname";
}

sub note {
    print STDERR "\e[32m * \e[0m @_\n";
}

sub rebase_preferred {
    my ( $branchname, $default_onto ) = @_;
    if ( exists $NEEDS{$branchname} ) {
        note("Rebasing $branchname onto $NEEDS{$branchname}");
        return rebase( real_name($branchname),
            real_name( $NEEDS{$branchname} ) );
    }
    note("Rebasing $branchname onto $default_onto");

    return rebase( real_name($branchname), $default_onto );
}

sub x_aheadof_y {
    my ( $branch, $upstream ) = @_;
    for my $ahead_branch ( $GW->branch( '-a', '--contains', $upstream ) ) {
        return 1 if $ahead_branch =~ /\A\s*\*?\s*\Q$branch\E\s*\z/;
    }
    return;
}

sub refresh_remote {
    my ($remote_name) = @_;
    $GW->RUN_DIRECT( 'remote', '-v', 'update', $remote_name );
}

sub upload {
    my ($branch) = @_;
    $GW->RUN_DIRECT( 'push', '-f', MY_REPO, $branch );
}

sub copy_branch {
    my ( $from, $to ) = @_;
    note("Copying $from to $to");

    $GW->RUN_DIRECT( 'checkout', '-B', $to, $from );
}

sub rebase {
    my ( $what, $onto ) = @_;
    note("Rebase $what onto $onto");

    #   git says "$what" is "upstream" and "$onto" is "branch"
    #   .... Not confusing at all<!>
    $GW->RUN_DIRECT( 'checkout', $what );
    $GW->RUN_DIRECT( 'rebase',   $onto );
}

sub merge_rebase {
    my ( $what, $onto ) = @_;
    my ( $sha1, ) = $GW->rev_parse($what);
    note("Rebase $sha1 onto $onto for $what");
    $GW->RUN_DIRECT( 'checkout', $sha1 );
    $GW->RUN_DIRECT( 'rebase',   $onto );
    my ( $new_sha, ) = $GW->rev_parse('HEAD');
    note("FF $onto -> $new_sha for $what");
    $GW->RUN_DIRECT( 'checkout', $onto );
    $GW->RUN_DIRECT( 'merge', '--ff-only', $new_sha );
}

sub proto_merge_rebase {
    my ( $what, $onto ) = @_;
    $GW->RUN_DIRECT( 'checkout',    $onto );
    $GW->RUN_DIRECT( 'cherry-pick', '..' . $what );
}
