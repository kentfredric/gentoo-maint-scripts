#!perl
use strict;
use warnings;

use feature 'say';
use HTTP::Tiny;
use JSON::MaybeXS;
use Data::Dump qw( pp );
use Path::Tiny qw( path );
use List::UtilsBy qw( bundle_by );
use Capture::Tiny qw( capture_stdout );
use Gentoo::PerlMod::Version qw( gentooize_version );

use constant PORTAGE_ROOT => ( path('.')->realpath->stringify );

BEGIN {
    unless ( path( PORTAGE_ROOT, 'dev-perl' )->exists ) {
        die "Expected to be run in a portage repo with dev-perl, sorry";
    }
}

my ( $category, $page, $pagesize ) = @ARGV;

die "Pass a letter" unless defined $category and length $category;

$page     = 1  unless defined $page;
$pagesize = 20 unless defined $pagesize;

my $interested =
  [ bundle_by { \@_ } $pagesize, all_perl_category($category) ]->[ $page - 1 ];

my $ua = HTTP::Tiny->new();
my $json = JSON::MaybeXS->new( utf8 => 1 );

for my $package ( @{$interested} ) {
    say "$package:";
    my $lv_gentoo;
    if ( $ENV{FIND_MISSING} ) {
        say for describe_missing($package);
        next; 
    }
    if ( $ENV{FIND_OUTDATED} ) {
      say for describe_stale($package);
      next;
    }
    say for describe_status($package);
    next;
}

sub describe_missing {
    my ($package) = @_;
    my (@out);
    eval { my $data = get_fedver($package); 1 } and return @out;
    return (
        " \e[31;1m* $package\e[0m Not on Anitya/Release-Monitoring",

        grep { $_ =~ /remote-id/ }
          path( PORTAGE_ROOT, $package, 'metadata.xml' )
          ->lines_raw( { chomp => 1 } )
    );
}

sub describe_status {
    my ($package) = @_;
    my (@out);
    my ($data);
    my ($lv_gentoo);
    eval { $data = get_fedver($package); 1 } or return (
        " \e[31;1m* $package\e[0m Not on Anitya/Release-Monitoring",
    );
    @out = (
        " Latest: \e[32m$data->{version}\e[0m",
        " Homepage: $data->{homepage}",
        " Gentoo:",
    );
    eval { $lv_gentoo = gentooize_version( $data->{version}, { lax => 1 });  };
    my $has_match;
    
    for my $version ( package_versions($package) ) {
        my $con  = "";
        my $coff = "";
        if ( defined $lv_gentoo and "$version" =~ /\A\Q$lv_gentoo\E(|-r.*)\z/ )
        {
            $con  = " \e[32;1m";
            $coff = "\e[0m";
            $has_match++;
        }
        push @out, " \e[31;1m- \e[0m${con}${version}${coff}";
    }
    if ( !$has_match ) {
        push @out, "\e[31;1m- out of date\e[0m";
    }
    return (@out,'');
}

sub describe_stale {
    my ($package) = @_;
    my (@out);
    my ($data);
    my ($lv_gentoo);
    eval { $data = get_fedver($package); 1 } or return (
        " \e[31;1m* $package\e[0m Not on Anitya/Release-Monitoring",
    );
    @out = (
        " Latest: \e[32m$data->{version}\e[0m",
        " Homepage: $data->{homepage}",
        " Gentoo:",
    );
    eval { $lv_gentoo = gentooize_version( $data->{version}, { lax => 1 });  };
    my $has_match;
    
    for my $version ( package_versions($package) ) {
        my $con  = "";
        my $coff = "";
        if ( defined $lv_gentoo and "$version" =~ /\A\Q$lv_gentoo\E(|-r.*)\z/ )
        {
            $con  = " \e[32;1m";
            $coff = "\e[0m";
            $has_match++;
        }
        push @out, " \e[31;1m- \e[0m${con}${version}${coff}";
    }
    return () if $has_match;
    push @out, "\e[31;1m- out of date\e[0m";
    return (@out,'');
}

sub all_perl_category {
    my ($letter) = @_;
    my $re = uc($letter) . lc($letter);
    my ( $lines, $exit ) = capture_stdout {
        system(
            'eix',             '--only-names',
            '--in-overlay',    'gentoo',
            '--pure-packages', 'dev-perl/[' . $re . ']'
        );
    };
    $exit == 0 or die "eix died";
    return split /\n/, $lines;
}

sub get_fedver {
    my ($package) = @_;
    return unwrap(
        $ua->get(
            'https://release-monitoring.org/api/project/Gentoo/' . $package
        )
    );
}

sub unwrap {
    my ($res) = @_;
    die "Request failed: $res->{status} $res->{reason}" unless $res->{success};
    die "Got no content"                                unless $res->{content};
    my $data = $json->decode( $res->{content} );
    return $data;
}

sub package_versions {
    my ($package) = @_;
    my ( $lines, $exit ) = capture_stdout {
        system( 'eix', '--format', '<availableversions:NAMEVERSION>',
            '--pure-packages', '--in-overlay', 'gentoo', '-e', $package );
    };
    $exit == 0 or die "eix died";
    return map {
        $_ =~ s/^\Q$package\E-//;
        $_
    } split /\n/, $lines;
}
