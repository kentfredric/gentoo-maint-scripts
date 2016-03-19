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
use Parallel::ForkManager;
use Capture::Tiny qw( capture_stdout );

my $git = Git::Wrapper->new('/usr/local/gentoo');

sub parse_treeline {
    my ($line) = @_;
    $line =~ /\A(.*)\t(.*)\z/;
    return ( $1, $2 );
}

my %OK;

my %packages;

my $pm = Parallel::ForkManager->new( 10 );

for my $file ( diff() ) {
    my ( $meta, $file_path ) = parse_treeline($file);
    if ( $file_path =~ qr{\A([^/]+)/([^/]+)/(.*\z)} ) {
        my ( $cat, $pn, $fn ) = ( "$1", "$2", "$3" );
        my $package = "$cat/$pn";
        next if exists $packages{$package};
        $packages{$package} = 1;
        my $whatever = path(REPO)->child( $cat, $pn );
        recheck($whatever);
        depcheck($package);
        next;
    }
    if ( $file_path =~ qr{\A([^/]+)/([^/]+)\z} ) {
        my ( $cat, $fn ) = ( "$1", "$2" );
        my $package = "$cat/$fn";
        next if exists $packages{$package};
        $packages{$package} = 1;
        my $whatever = path(REPO)->child( $cat );
        recheck($whatever);
        next;
    }

}
$pm->wait_all_children;

sub diff {
    my ($path) = @_;
    my (@args) = ();
    if ( TRACK eq 'HEAD' ) {
        return $git->diff_index( '--cached', UPSTREAM, ( $path ? $path : () ) );
    }
    $path = ($path) ? ":$path" : "";
    return $git->diff_tree( '-r', UPSTREAM . $path, TRACK . $path );
}
sub recheck { 
  my ( $path ) = @_;
  my $pid = $pm->start and return;
  print STDERR "\e[31m \* Checking:\e[0m$path\n";
  chdir $path;
  system("repoman","full");
  $pm->finish;
}
sub depcheck {
  my ( $package ) = @_;
  my $pid = $pm->start and return;
  print STDERR "\e[31m \* Getting deps on for:\e[0m$package\n";
  chdir $path;

  system("equery","-q","d","-a", $package);
  $pm->finish;

}
