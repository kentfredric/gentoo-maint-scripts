#!/usr/bin/env perl
# ABSTRACT: Redo for-linux branch.

use strict;
use warnings;
use Git::Wrapper ();
use File::chdir;

$ENV{GPG_TTY} = qx{tty};

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

for my $local_branch ( local_branches() ) {
  if ( needs_merge( $local_branch, UPSTREAM_REF ) ) {
    info("$local_branch current", [ 'red' ]);
    next;
  }
  info("$local_branch merged", [ 'green' ]);
  $GW->branch('-d', $local_branch);
}

my @to_delete;
for my $remote_branch ( remote_branches('kentnl') ) {
  if ( needs_merge( "remotes/kentnl/$remote_branch", UPSTREAM_REF ) ) {
    info("kentnl/$remote_branch current", [ 'red' ]);
    next;
  }
  push @to_delete, ":$remote_branch";
  info("kentnl/$remote_branch merged", [ 'green' ]);
}
if ( @to_delete ) {
  $GW->push('kentnl', @to_delete );
}
use Term::ANSIColor qw( colored );

sub info {
  print STDERR $_[1] ? colored( $_[1], " * " ) : " * ";
  print STDERR "$_[0]\n";
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

sub needs_merge {
    my ( $branch, $upstream ) = @_;
    my ($upstream_sha,) = $GW->rev_parse($upstream);
    my ($branch_sha,)  = $GW->rev_parse($branch);
    if ( $upstream_sha eq $branch_sha ) {
      info( "$branch sha eq $upstream sha");
      return;
    }
    # Find all branches containing this branch
    for my $head ( $GW->branch('-a', '--contains', $branch_sha ) ) {
      next unless $head =~ /\A\s*\*?\s*(\S+)\s*\z/;
      my $head_name= $1;
      # if upstream is found containing us, return "undef", we're merged.
      my ($head_sha,) = $GW->rev_parse($head_name);
      return if $head_sha eq $upstream_sha;
    }
    return 1;
}
sub x_aheadof_y {
    my ( $branch, $upstream ) = @_;
   
    for my $ahead_branch ( $GW->branch( '-a', '--contains', $upstream ) ) {
        return 1 if $ahead_branch =~ /\A\s*\*?\s*\Q$branch\E\s*\z/;
    }
    return;
}

sub local_branches {
    my @branches;
    my $thread_prefix = QUEUE_THREAD_PREFIX;

    for my $branch ( $GW->branch() ) {
      next unless $branch =~ /\A\s*\*?\s*(\S+)\z/;
      my $branch_name = $1;
      next unless $branch_name =~ /\A\Q$thread_prefix\E/;
      push @branches, $branch_name;
    }
    return @branches;
}
sub remote_branches {
    my ( $remote ) = @_;
    my @branches;
    my $thread_prefix = QUEUE_THREAD_PREFIX;
    for my $branch ( $GW->branch('-a') ) {
      next unless $branch =~ qr{\A \s* \*? \s* remotes/\Q$remote\E/(\S+) \s* \z}x;
      my $branch_name = $1;
      next unless $branch_name =~ /\A\Q$thread_prefix\E/;
      push @branches, $branch_name;
    }
    return @branches;

}

