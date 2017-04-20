#!/usr/bin/env perl
# ABSTRACT: Redo for-linux branch.

use strict;
use warnings;
use File::chdir;
use Path::Tiny 0.082 qw( path );    # working realpath

$ENV{GPG_TTY} //= qx{tty};

use constant _inc => path(
    sub { ( caller(0) )[1] }
      ->()
)->absolute->realpath->parent->child('lib')->stringify;
use lib _inc;

use My::Git::Wrapper;
use My::Note qw( note $TASK );
use My::Git::Utils
  qw( has_branch branch_contains refresh_remote copy_branch has_remote_branch );
use My::Gn2::Repo qw( show_new_since );

use constant FORCE_REBASE  => $ENV{FORCE_REBASE};
use constant LOCAL_UPDATES => $ENV{LOCAL_UPDATES};
use constant DO_ATTIC      => $ENV{ATTIC};
use constant NO_PUSH       => $ENV{NO_PUSH};
use constant NO_SYNC       => $ENV{NO_SYNC};

use constant UPSTREAM_REPO   => 'upstream';
use constant UPSTREAM_BRANCH => 'master';
use constant UPSTREAM_REF    => 'refs/remotes/'
  . UPSTREAM_REPO . '/'
  . UPSTREAM_BRANCH;

use constant MY_REPO => 'kentnl';

use constant QUEUE_BRANCH        => 'for-gentoo';
use constant QUEUE_THREAD_PREFIX => 'kentnl/';

use constant STAGING_BRANCH => 'staging-for-gentoo';

my $GW = My::Git::Wrapper->new("/usr/local/gentoo");

my (@MERGE_LIST) = (    #
);

my %NEEDS =
  ( map { ( $MERGE_LIST[$_], $MERGE_LIST[ $_ - 1 ] ) }
      ( 1 .. ( scalar @MERGE_LIST ) - 1 ) );

for my $target (@MERGE_LIST) {
    if ( not exists $NEEDS{$target} ) {
        printf "- $target => root\n";
        next;
    }
    printf "- $target => $NEEDS{$target}\n";
    next;
}

#my (@ATTIC) = ( 'perl-dist-zilla', );
#
#push @STAGING_LIST, @ATTIC if DO_ATTIC;

unless (NO_SYNC) {
    $TASK = "SYNC";

    refresh_remote( $GW, UPSTREAM_REPO ) if not LOCAL_UPDATES;
}
$TASK = "CHECK";
exit 0 unless LOCAL_UPDATES or should_rebase();

unless ( branch_contains( $GW, QUEUE_BRANCH, UPSTREAM_REF ) ) {
    show_new_since( $GW, UPSTREAM_REF, QUEUE_BRANCH );
}

unless ( NO_PUSH or LOCAL_UPDATES ) {
    unless (
        branch_contains(
            $GW, UPSTREAM_REF, 'refs/remotes/' . MY_REPO . '/master'
        )
      )
    {
        upload( UPSTREAM_REF . ':master' );
    }
}

# All branches in @MERGE_LIST are also in
#   ref/braches/QUEUE_THREAD_PREFIX/<BRANCHNAME>
#
# All are designed to track "UPSTREAM_REF", ie:
#
#    upstream/master .. kentnl/topicname
#
# This rebases all "kentnl/topicname" onto "upstream/master" when upstream/master changes.

my $needs_reconstruct;

item: for my $target (@MERGE_LIST) {
    $TASK = "Reparent $target";
    my $real_name = real_name($target);
    my $ready     = is_ready($target);

    next unless LOCAL_UPDATES xor $ready;

  fixup: {
        if ( branch_contains( $GW, UPSTREAM_REF, $real_name ) ) {
            note( $real_name . ' is ahead of ' . UPSTREAM_REF, ['green'] );
            last fixup unless FORCE_REBASE;
        }

        rebase_preferred( $target, UPSTREAM_REF ) if LOCAL_UPDATES xor $ready;
        $needs_reconstruct = 1;

        next item unless $ready;
    }

    next item if LOCAL_UPDATES;

    if ( has_remote_branch( $GW, MY_REPO . '/' . $real_name ) ) {
        next item
          if branch_contains( $GW, $real_name,
            'refs/remotes/' . MY_REPO . '/' . $real_name );
    }
    upload($real_name) unless NO_PUSH;
    $needs_reconstruct = 1;
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

if ( not LOCAL_UPDATES and $needs_reconstruct ) {
    $TASK = "Union Queue";

    copy_branch( $GW, UPSTREAM_REF, QUEUE_BRANCH );

    for my $target (@MERGE_LIST) {
        $TASK = "Union <$target>";
        my $real_name = real_name($target);
        my $ready     = is_ready($target);
        next unless $ready;
        merge_rebase( $real_name => QUEUE_BRANCH );
    }
    $TASK = "Push Union";
    upload(QUEUE_BRANCH) unless NO_PUSH;

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
  #  rebase_preferred( $_ => UPSTREAM_REF ) for @STAGING_LIST;
    copy_branch( $GW, QUEUE_BRANCH, STAGING_BRANCH );

    for my $target (@MERGE_LIST) {
        my $real_name = real_name($target);
        my $ready     = is_ready($target);
        next if $ready;
        note( "Staging: " . $real_name, ['green'] );
        if ( branch_contains( $GW, $real_name, STAGING_BRANCH ) ) {
            note( $real_name . ' is ahead of ' . STAGING_BRANCH, ['green'] );
            next unless FORCE_REBASE;
        }
        merge_rebase( $real_name => STAGING_BRANCH );

    }

}

sub should_rebase {
    return 1 if FORCE_REBASE;
    return 1 unless branch_contains( $GW, QUEUE_BRANCH, UPSTREAM_REF );
    note( QUEUE_BRANCH . ' is ahead of ' . UPSTREAM_REF, ['red'] );
    for my $branchname ( map { QUEUE_THREAD_PREFIX . $_ } @MERGE_LIST ) {
        return 1 unless branch_contains( $GW, $branchname, UPSTREAM_REF );
        note( $branchname . ' is ahead of ' . UPSTREAM_REF, ['red'] );
    }
    return 0;
}

sub remote_names { $GW->remote() }

sub real_name {
    my ($branchname) = @_;

    return $branchname if has_branch( $GW, $branchname );
    return QUEUE_THREAD_PREFIX . $branchname
      if has_branch( $GW, QUEUE_THREAD_PREFIX . $branchname );

    die "Cant resolve $branchname";
}

sub is_ready {
    my ($branchname) = @_;
    return ( ( QUEUE_THREAD_PREFIX . $branchname ) eq real_name($branchname) );
}

sub rebase_preferred {
    my ( $branchname, $default_onto ) = @_;
    if ( exists $NEEDS{$branchname} ) {
        note( "Rebasing $branchname onto $NEEDS{$branchname}", ['yellow'] );
        show_new_since( $GW, real_name( $NEEDS{$branchname} ),
            real_name($branchname) );
        return rebase( real_name($branchname),
            real_name( $NEEDS{$branchname} ) );
    }
    note( "Rebasing $branchname onto $default_onto", ['yellow'] );
    show_new_since( $GW, real_name($branchname), $default_onto );

    return rebase( real_name($branchname), $default_onto );
}

sub upload {
    my ($branch) = @_;
    note( "Uploading $branch to " . MY_REPO, ['magenta'] );
    $GW->RUN_DIRECT( 'push', '-f', MY_REPO, $branch );
}

sub rebase {
    my ( $what, $onto ) = @_;
    note( "Rebase $what onto $onto", ['cyan'] );

    #   git says "$what" is "upstream" and "$onto" is "branch"
    #   .... Not confusing at all<!>
    $GW->RUN_DIRECT( 'checkout', $what );
    $GW->RUN_DIRECT( 'rebase',   $onto );
}

sub merge_rebase {
    my ( $what, $onto ) = @_;
    my ( $sha1, ) = $GW->rev_parse($what);
    note( "Fastforward $onto to cherry-pick $what", ['green'] );

    #note( "Rebase $sha1 onto $onto for $what", ['cyan'] );
    $GW->RUN_DIRECT( 'checkout', '-q', $sha1 );

    #    note( "...", ['cyan'] );
    $GW->RUN_DIRECT( 'rebase', '-q', $onto );
    my ( $new_sha, ) = $GW->rev_parse('HEAD');

    #   note( "FF $onto -> $new_sha for $what", ['yellow'] );
    $GW->RUN_DIRECT( 'checkout', '-q', $onto );

    #    note( "...", ['yellow'] );
    $GW->RUN_DIRECT( 'merge', '--ff-only', '-n', $new_sha );
}

sub proto_merge_rebase {
    my ( $what, $onto ) = @_;
    $GW->RUN_DIRECT( 'checkout',    $onto );
    $GW->RUN_DIRECT( 'cherry-pick', '..' . $what );
}
