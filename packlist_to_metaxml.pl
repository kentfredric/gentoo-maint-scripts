#!/usr/bin/env perl
# FILENAME: packlist_to_metadata.pl
# CREATED: 08/03/16 02:53:52 by Kent Fredric (kentnl) <kentfredric@gmail.com>
# ABSTRACT: Turn a .packlist into a <upstream> list

use strict;
use warnings;

use ExtUtils::Packlist;
use Module::Metadata;
use Path::Tiny qw( path );
use Carp qw( croak );

no warnings 'redefine';

BEGIN {
    *Module::Metadata::provides = sub {
        my $class = shift;

        croak "provides() requires key/value pairs \n" if @_ % 2;
        my %args = @_;

        croak "provides() takes only one of 'dir' or 'files'\n"
          if $args{dir} && $args{files};

        croak "provides() requires a 'version' argument"
          unless defined $args{version};

        croak "provides() does not support version '$args{version}' metadata"
          unless grep { $args{version} eq $_ } qw/1.4 2/;

        $args{prefix} = 'lib' unless defined $args{prefix};

        my $p;
        if ( $args{dir} ) {
            $p = $class->package_versions_from_directory( $args{dir} );
        }
        else {
            croak "provides() requires 'files' to be an array reference\n"
              unless ref $args{files} eq 'ARRAY';
            $p =
              $class->package_versions_from_directory( '/var/empty',
                $args{files} );
        }

        # Now, fix up files with prefix
        if ( length $args{prefix} ) {    # check in case disabled with q{}
            $args{prefix} =~ s{/$}{};
            for my $v ( values %$p ) {
                $v->{file} = "$args{prefix}/$v->{file}";
            }
        }

        return $p;
    };
}

if ( not $ARGV[0] ) {
  die "Must pass a packlist\n";
}
if ( not -e $ARGV[0] ) {
  die "Packlist $ARGV[0] does not exist";
}

my $pl       = ExtUtils::Packlist->new( $ARGV[0] );
my $pfx      = "/nfs-mnt/amd64-root/";
my @files;

for my $file ( sort keys %{$pl} ) {
  unless (  -e $file or -e "$pfx/$file" ) {
    warn "$file (or $pfx/$file) not found, skipping\n";
    next;
  }
  if ( $file =~ /\.bin$/ ) {
    warn "$file matches blacklist, skipping\n";
    next;
  }
  push @files, -e $file ? $file : "$pfx/$file";
}
my $provides = Module::Metadata->provides(
    version => 2,
    files   => \@files,
);

my $content = path('metadata.xml')->slurp_raw;
my $prefix;
if ( $content =~ /^(\s+)<remote-id\s+type="cpan-module">/msx ) {
    $prefix = "$1";
}
else {
    die "Can't determine prefix for metadata.xml";
}

my $lines = "";
for my $entry ( sort keys %{$provides} ) {
    $lines .= "$prefix<remote-id type=\"cpan-module\">$entry</remote-id>\n";
}
$content =~
s{  (?:^\s+<remote-id\s+type=\"cpan-module\">[^<]+</remote-id>\s*\n)+ }{ $lines }msex;
path('metadata.xml')->spew_raw($content);
