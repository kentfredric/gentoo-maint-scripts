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
    if ( $ENV{FIND_MISSING} ) {
        eval {
          my $data = get_fedver($package);
          1;
      } and next;
      say " \e[31;1m* $package\e[0m Not on Anitya/Release-Monitoring";
      say for grep { $_=~ /remote-id/ } path('.',$package,'metadata.xml')->lines_raw({ chomp => 1 });
      next;
    }
    eval {
        my $data = get_fedver($package);
        say " Latest: \e[32m$data->{version}\e[0m";
        say " Homepage: $data->{homepage}";
        1;
    } || do {
        say " \e[31;1m*\e[0m Not on Anitya/Release-Monitoring";
    };
    say " Gentoo:";
    for my $version ( package_versions($package) ) {
      say " \e[31;1m- \e[0m$version";
    }
    say "";
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
