#!perl
use strict;
use warnings;
use feature 'state';
use Test::TempDir::Tiny qw( tempdir in_tempdir );
use Test::More;
use HTTP::Tiny;

my ( $module, $old_version, $new_version ) = @ARGV;

die "$0 <module> <oldversion> <newversion>" unless 3 == @ARGV;

my $ua = HTTP::Tiny->new();

use Data::Dump qw(pp);

my $old = get_dist_version( $module, $old_version );
my $new = get_dist_version( $module, $new_version );

my ($old_bn) = $old =~ qr{([^/]+)\z}sx;
my ($new_bn) = $new =~ qr{([^/]+)\z}sx;

my $dl = tempdir('download_dir');

use Capture::Tiny qw( capture_stdout );

mirror_dist( $old, "$dl/$old_bn" );
mirror_dist( $new, "$dl/$new_bn" );

$ENV{DIFFMODE} ||= 'kdiff3';


in_tempdir "workdir" => sub {
  my $cwd = shift;
  mkdir "$cwd/a";
  warn "Extracting $dl/$old_bn to $cwd/a";
  system( 'tar', '-xf', "$dl/$old_bn", "-C", "$cwd/a", "--strip-components=1" ) == 0 or die;
  mkdir "$cwd/b";
  warn "Extracting $dl/$new_bn to $cwd/b";
  system( 'tar', '-xf', "$dl/$new_bn", "-C", "$cwd/b", "--strip-components=1" ) == 0 or die;

  if ( 'kdiff3' eq  $ENV{DIFFMODE} ) {
    return system('kdiff3','a','b');
  }
  my ( $out, $exit ) = capture_stdout {
      $ENV{LC_ALL} = 'C';
      $ENV{TZ}     = 'UTC';
      system("diff","-Nurdwp", "a", "b");
  };
  
  path('./data.patch')->spew_raw($out);

  if ( 'stat' eq $ENV{DIFFMODE} ) {
        return system("diffstat","-CK",'-T','-w','120', './data.patch');
  }

  return system("code2color", "-l", "patch", "./data.patch");
};



use Path::Tiny qw(path);

sub mirror_dist {
    my ( $path , $target_path )  = @_;
    my $mirror_file = path('/tmp/cpancache',$path);
    $mirror_file->parent->mkpath;
    if ( $mirror_file->exists ) {
      warn "[cached] Copying $mirror_file to $target_path\n";
      $mirror_file->copy($target_path);
      return;
    }
    warn "Downloading $path to $mirror_file\n";
    $ua->mirror('http://cpan.metacpan.org/authors/id/'. $path, "$mirror_file");
    warn "Copying $mirror_file to $target_path\n";
    $mirror_file->copy($target_path);
    return;
}
sub get_dist_version {
    my ( $module, $version ) = @_;
    for my $entry ( get_dists_for_version( $module, $version ) ) {
        return $entry->{dist};
    }
    die "No best dist for $module $version";
}

sub get_dists_for_version {
    my ( $module, $version ) = @_;
    my @out;
    for my $entry ( get_history($module) ) {
        next unless $entry->{version} eq $version;
        push @out, $entry;
    }
    die "No results for $module $version" unless @out;
    return @out;
}

sub get_history {
    my ($module) = @_;
    state $cache = {};
    return @{ $cache->{$module} } if exists $cache->{$module};
    my $response =
      $ua->get( 'http://cpanmetadb.plackperl.org/v1.0/history/' . $module );
    die "Failed to get history for $module" unless $response->{success};
    die "No content for $module" unless length $response->{content};
    my (@entries);
    for my $line ( split qq/\n/, $response->{content} ) {

        if ( $line =~ /\A(\S+)\s+(\S+)\s+(\S+)\z/ ) {
            unshift @entries,
              {
                version => $2,
                dist    => $3,
              };
            next;
        }
        warn "Can't parse <$line>";
    }
    $cache->{$module} = \@entries;
    return @entries;
}
