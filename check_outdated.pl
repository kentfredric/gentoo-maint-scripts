#!perl
use strict;
use warnings;

use Path::Tiny qw( path cwd );
use Capture::Tiny qw( capture_stdout );
use Data::Dump qw(pp);
use Gentoo::PerlMod::Version qw( gentooize_version );
use experimental 'signatures';
use HTTP::Tiny;
use CPAN::DistnameInfo;

# Generic Gentoo stuff here
my $cpn        = get_cpn( $ARGV[0] );
my $pn         = get_pn( $ARGV[0] );
my $latest     = get_latest( $ARGV[0] );
my $rel_latest = $latest->relative( get_pkg( $ARGV[0] ) );
die "Can't determine latest" unless defined $latest;
my $version;
if ( $rel_latest =~ /\A\Q$pn\E-(.*)\.ebuild\z/ ) {
    $version = $1;
}
warn "Latest: $pn => $version in $latest\n";
my $data = e_extract($latest);
unless ( inherits( $data, 'perl-module' ) ) {
    warn " Not perl-module\n";
    exit;
}

# Perl-module specific logic from here on
my $upstream_version = upstream_version( $data, $version );
my $upstream_distname = upstream_distname( $data, "$pn" );

warn " Local upstream version: $upstream_version\n";
my $gentooized_current = gentooize_version( $upstream_version, { lax => 1 } );
if ( $version !~ /\A\Q$gentooized_current\E(-r(\d+))?/ ) {
    warn
"\e[31m Expected $upstream_version normalized as $gentooized_current, not $version\e[0m\n";
}
if ( $upstream_distname ne "$pn" ) {
    warn "\e[31m Expected $pn shipped as $upstream_distname\e[0m\n";
}
my $freshest = get_freshest( $upstream_distname );
if ( version->parse($freshest) > version->parse($upstream_version ) ) {
  warn " \e[32m$freshest\e[0m <<<< $upstream_version\n";
}

my @trait_rules;

BEGIN {

    @trait_rules = (
        sub {
            if ( $_ =~ /\A\s*inherit\s+(.*?)\s*\z/ ) {
                my $inherited = "$1";
                push @{ $_[0]->{inherit_order} }, split /\s+/, $inherited;
                $_[0]->{inherits} = {
                    %{ $_[0]->{inherits} || {} },
                    map { $_ => 1 } split /\s+/,
                    $inherited
                };
                return 1;
            }
            return;
        },
        sub {
            for my $var (
                qw( EAPI DIST_VERSION DIST_NAME MODULE_VERSION MODULE_NAME MY_PN )
              )
            {
                next unless $_ =~ /\A\s*\Q$var\E=(.*?)\s*\z/;
                my $value = $1;
                if ( exists $_[0]->{vars}->{$var} ) {
                    die "Multiple $var assignments";
                }
                $_[0]->{vars}->{$var} = unquote( $var, $value );
                return 1;
            }
            return;
        },
    );
}

sub inherits ( $data, $class ) {
    return unless exists $data->{inherits};
    return exists $data->{inherits}->{$class};
}

sub is_eapi ( $data, $version ) {
    return unless exists $data->{vars}->{EAPI};
    return ( ( $data->{vars}->{EAPI} || 0 ) eq $version );
}

sub upstream_version ( $data, $fallback ) {
    return unless inherits( $data, 'perl-module' );
    return $data->{vars}->{MODULE_VERSION}
      if is_eapi( $data, 5 )
      and exists $data->{vars}->{MODULE_VERSION};
    return $data->{vars}->{DIST_VERSION}
      if is_eapi( $data, 6 )
      and exists $data->{vars}->{DIST_VERSION};
    return $fallback;
}

sub upstream_distname ( $data, $fallback ) {
    return unless inherits( $data, 'perl-module' );
    return $data->{vars}->{MY_PN}
      if is_eapi( $data, 5 )
      and exists $data->{vars}->{MY_PN};
    return $data->{vars}->{DIST_NAME}
      if is_eapi( $data, 6 )
      and exists $data->{vars}->{DIST_NAME};
    return $fallback;
}

my $ua;
sub get_freshest( $distname ) {
    $ua ||= HTTP::Tiny->new();

    # Cheat, assume Module::Name -> dist-name and see where that get us
    my $module_name = $distname;
    $module_name =~ s/-/::/g;

    my $response = $ua->get('http://cpanmetadb.plackperl.org/v1.0/history/' . $module_name );
    if( $response->{success} ) {
      my (@lines) = split qq/\n/, $response->{content};
      my $newest = pop @lines;
      if ( $newest =~ /\A(\S+)\s+(\S+)\s+(.+)\s*\z/ ) {
        my ( $module, $version, $path ) = ($1,$2,$3);
        my $info = CPAN::DistnameInfo->new( 'author/id/' . $path );
        my $dist = $info->dist;
        if ( $dist ne $distname ) {
          die " \e[32mCan't resolve $distname, got $dist back\e[0m\n";
        }
        return $version;
      }
    }
    die " \e[32mCan't resolve $distname, got 404 back\e[0m\n";
}

sub unquote ( $name, $var ) {
    my $orig = $var;
    $var =~ s/\A\s*//ms;
    $var =~ s/\s*\z//ms;

    if ( q["] eq substr $var, 0, 1 ) {
        if ( q["] ne substr $var, -1, 1 ) {
            die "Unbalanced \"\" in parsing $name=$orig";
        }
        $var =~ s/\A"//;
        $var =~ s/"\z//;
        if ( $var =~ /[^\\]"/ ) {
            die "Bash interoplation unsupported in parsing $name=$orig";
        }
        $var =~ s/\\//;    # drop escapes
        if ( $var =~ /\$/ ) {
            die "Bash interoplation unsupported in parsing $name=$orig";
        }
        return $var;
    }
    if ( q['] eq substr $var, 0, 1 ) {
        if ( q['] ne substr $var, -1, 1 ) {
            die "Unbalanced '' in parsing $name=$orig";
        }
        $var =~ s/\A'//;
        $var =~ s/'\z//;
        if ( $var =~ /[^\\]'/ ) {
            die "Bash interoplation unsupported in parsing $name=$orig";
        }
        return $var;
    }
    if ( $var =~ /\$/ ) {
        die "Bash interoplation unsupported in parsing $name=$orig";
    }
    return $var;
}

sub e_extract($file) {
    my %data;
  liner: for my $line ( path($file)->lines_raw( { chomp => 1 } ) ) {
        for my $test (@trait_rules) {
            local $_ = $line;
            next liner if $test->( \%data );
        }
    }
    return \%data;
}

sub ebuilds($dir) {
    return
      grep { $_->basename ne 'skel.ebuild' }
      path($dir)->children(qr{\.ebuild$});
}

sub get_pn($pkg) {
    if ( not $pkg ) {
        $pkg = cwd;
    }
    else {
        $pkg = path($pkg);
    }
    if ( ebuilds($pkg) ) {
        return $pkg->relative( $pkg->parent );
    }
    die "No .ebuild in $pkg";
}

sub get_cpn($pkg) {
    if ( not $pkg ) {
        $pkg = cwd;
    }
    else {
        $pkg = path($pkg);
    }
    if ( ebuilds($pkg) ) {
        return $pkg->relative( $pkg->parent->parent );
    }
    die "No .ebuild in $pkg";
}

sub get_pkg($pkg) {
    if ( not $pkg ) {
        $pkg = cwd;
    }
    else {
        $pkg = path($pkg);
    }
    if ( ebuilds($pkg) ) {
        return $pkg;
    }
    die "No .ebuild in $pkg";
}

sub get_latest($dir) {
    my $pkg_dir = get_pkg($dir);
    my (@ebuilds) = $pkg_dir->children(qr{\.ebuild$});
    return unless @ebuilds;
    my $cat = $pkg_dir->parent->basename;

    my ( $best, $second, @rest ) =
      sort { atom_cmp( $a->[0], $b->[0] ) }
      map { [ "$cat/" . $_->basename('.ebuild'), $_ ] } @ebuilds;

    return path( $best->[1] )->absolute;
}

sub atom_cmp ( $left, $right ) {
    my ( $out, $ret ) = capture_stdout {
        system( "qatom", "-c", $left, $right );
    };
    if ( $out =~ /</ ) {
        return 1;
    }
    if ( $out =~ />/ ) {
        return -1;
    }
    return 0;
}

