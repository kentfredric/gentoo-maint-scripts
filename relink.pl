#!/usr/bin/env perl

# ABSTRACT: Relink diffs

use strict;
use warnings;

use Git::Wrapper;
use PIR;
use constant REPO       => '/usr/local/gentoo';
use constant UPSTREAM   => 'upstream/master';
use constant TRACK      => 'HEAD';
use constant WRITE_TREE => '/usr/local/portage';
use Path::Tiny qw( path );

my $git = Git::Wrapper->new('/usr/local/gentoo');

sub parse_treeline {
    my ($line) = @_;
    $line =~ /\A(.*)\t(.*)\z/;
    return ( $1, $2 );
}

my %OK;

my %packages;

for my $file ( diff() ) {
    my ( $meta, $file_path ) = parse_treeline($file);
    if ( $file_path =~ qr{\A([^/]+)/([^/]+)/(.*\z)} ) {
        my ( $cat, $pn, $fn ) = ( "$1", "$2", "$3" );
        my $package = "$cat/$pn";
        next if exists $packages{$package};
        $packages{$package} = 1;
        path(WRITE_TREE)->child($cat)->mkpath;

        #        next;
        my $symlink = mk_symlink( $cat, $pn );
        $OK{$symlink} = $symlink;
        next;
    }
    if ( $file_path =~ qr{\A([^/]+)/([^/]+)\z} ) {
        my ( $cat, $fn ) = ( "$1", "$2" );
        my $package = "$cat/$fn";
        next if exists $packages{$package};
        $packages{$package} = 1;
        path(WRITE_TREE)->child($cat)->mkpath;

        #        next;
        my $symlink = mk_symlink( $cat, $fn );
        $OK{$symlink} = $symlink;
        next;
    }
    if ( $file_path =~ qr{\A([^/]+)\z} ) {
        my ( $cat, ) = ("$1");
        next if exists $packages{$cat};
        $packages{$cat} = 1;
        print "- $cat\n";

        #        next;
        my $symlink = mk_symlink($cat);
        $OK{$symlink} = $symlink;
        next;
    }

}

sub mk_symlink {
    my (@path) = @_;
    my $symlink = path( WRITE_TREE, @path )->absolute;
    my $target  = path( REPO,       @path )->absolute;

    my $message = "";

    lstat $symlink;
    $message = "$symlink \e[31m!-l\e[0m" if !-l _;
    $message = "$symlink \e[31m!-e\e[0m" if !-l _ and !-e _;
    $message = "$symlink \e[31m!->\e[0m $target"
      if -l _
      and -e _
      and path( readlink($symlink) )->absolute ne $target;

    if ( not length $message ) {
        print "$symlink \e[32mok\e[0m\n";
        return $symlink;
    }
    if ( ( symlink "$target", "$symlink" ) == 1 ) {
        print "$message\e[32m -> \e[0m$target\n";
        return $symlink;
    }
    my $error = "$!";
    print "$message\e[31m -> failed: \e[0m$target\n";
    warn "Cant write symlink $symlink, $error";
    return $symlink;
}

sub diff {
    my ($path) = @_;
    my (@args) = ();
    if ( TRACK eq 'HEAD' ) {
        return $git->diff_index( '--cached', UPSTREAM, ( $path ? $path : () ) );
    }
    $path = ($path) ? ":$path" : "";
    return $git->diff_tree( '-r', UPSTREAM . $path, TRACK . $path );
}
my $PIR = PIR->new();
$PIR->symlink;
my $iter = $PIR->iter(WRITE_TREE);
while ( my $item = $iter->() ) {
    next if exists $OK{ path($item)->absolute };
    print "$item \e[31mremoved\e[0m\n";
    path($item)->absolute->remove;
}

