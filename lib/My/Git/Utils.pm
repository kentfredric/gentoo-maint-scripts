package My::Git::Utils;

use strict;
use warnings;

use My::Git::Wrapper;
use My::Note qw( note );

use Exporter ();

BEGIN {
    *import = \&Exporter::import;
}

our @EXPORT_OK =
  qw( branches git branches_containing branch_contains has_branch refresh_remote copy_branch has_remote_branch );
my $cache = {};

sub git {
    return $_[0] if ref $_[0];
    return My::Git::Wrapper->new( $_[0] );
}

sub cache_key {
    ref $_[0] ? $_[0]->dir : git( $_[0] )->dir;
}

sub cached {
    my ( $repo, $cachename, $key, $compute ) = @_;
    return $compute->() if $ENV{NO_CACHE};
    $repo = cache_key($repo);
    $cache->{$repo} = {} unless exists $cache->{$repo};
    $cache->{$repo}->{$cachename} = {}
      unless exists $cache->{$repo}->{$cachename};
    return $cache->{$repo}->{$cachename}->{$key}
      if exists $cache->{$repo}->{$cachename}->{$key};
    return ( $cache->{$repo}->{$cachename}->{$key} = $compute->() );
}

sub clear_cache {
    my ( $repo, $cachename ) = @_;
    if ( not $cachename ) {
        delete $cache->{ cache_key($repo) };
        return;
    }
    delete $cache->{ cache_key($repo) }->{$cachename};
}

sub _trim_branchname {
    $_ = $_[0] if @_ > 0;
    s/\A[\t *]*//;
    s/[\t ]*\z//;
    return $_;
}

sub branches {
    my ($repo) = @_;
    return cached(
        $repo => 'branches' => 'all' => sub {

            #         note("Getting branches");
            return [ map _trim_branchname, git($repo)->branch ];
        }
    );
}

sub remote_branches {
    my ($repo) = @_;
    return cached(
        $repo => 'branches' => 'remote' => sub {

            #         note("Getting branches");
            return [ map _trim_branchname, git($repo)->branch('-r') ];
        }
    );
}

sub branches_containing {
    my ( $repo, $commitish ) = @_;
    return cached(
        $repo      => 'branches_containing',
        $commitish => sub {

            #           note("Finding branches containing $commitish");
            return [
                map _trim_branchname,
                git($repo)->branch( '-a', '--contains', $commitish )
            ];
        }
    );
}

sub has_branch {
    my ( $repo, $name ) = @_;

    #    note("Repo has branch $name?");
    for my $branch ( @{ branches($repo) } ) {
        return 1 if $branch eq $name;
    }
    return undef;
}

sub has_remote_branch {
    my ( $repo, $name ) = @_;
    for my $branch ( @{ remote_branches($repo) } ) {
        return 1 if $branch eq $name;
    }
    return undef;
}

sub branch_contains {
    my ( $repo, $source_branch, $commitish ) = @_;

    #    note("$source_branch contains $commitish?");
    local $@;
    eval {
        git($repo)
          ->RUN_DIRECT( 'merge-base', '--is-ancestor', $source_branch,
            $commitish );
        1;
    } and return 1;
    my $error = $@;
    die $error if $error->status != 1;
    return 0;

    #for my $branch ( @{ branches_containing( $repo, $commitish ) } ) {
    #    return 1 if $branch eq $source_branch;
    #}
}

sub refresh_remote {
    my ( $repo, $remote_name ) = @_;

    #    note("Refreshing remote $remote_name");
    git($repo)->RUN_DIRECT( 'remote', 'update', $remote_name );
    clear_cache($repo);
}

sub copy_branch {
    my ( $repo, $from, $to ) = @_;
    note("Copying branch $from to $to");
    git($repo)->RUN_DIRECT( 'checkout', '-B', $to, $from );
    clear_cache($repo);
}
