# Class::Core Wrapper System
# Version 0.01
# Copyright (C) 2012 David Helkowski & T.Rowe Price

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.  You may also can
# redistribute it and/or modify it under the terms of the Perl
# Artistic License.
  
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

package XML::Bare;

use Carp;
use strict;
use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );
require Exporter;
@ISA = qw(Exporter);

$VERSION = "0.01";

use vars qw($VERSION);

@EXPORT = qw( );
@EXPORT_OK = qw( );

=head1 NAME

Class::Core - Class wrapper system providing parameter typing, logging, and class auto-instanitation

=head1 VERSION

0.01

=cut

package Class::Core::VIRT;
use strict;
#use Data::Dumper;
use XML::Bare qw/xval forcearray/;
our $AUTOLOAD;
sub AUTOLOAD {
    my $ob = shift;
    my $tocall = $AUTOLOAD;
    $tocall =~ s/^Class::Core::VIRT:://;
    return if( $tocall eq 'DESTROY' ); # Don't bother calling a virtual destroy
    my $ref = $ob->{ $tocall }; # grab the function reference
    my $spec = $ob->{'_spec'};
    my %parms = @_;
    if( $spec ) {
        $spec = $spec->{'funcs'}{ $tocall };
        if( $spec ) {
            if( $spec->{'sig'} ) {
                # Additionally check global specs if they are set
                if( $spec->{'in'} || $spec->{'out'} || $spec->{'ret'} ) {
                    my $err = _checkspec( $ob, $spec, \%parms );
                    die $err if( $err );
                }
                my $sigs = forcearray( $spec->{'sig'} );
                my $allerr = '';
                my $ok = 0;
                for my $sig ( @$sigs ) {
                    my $err = _checkspec( $ob, $sig, \%parms );
                    if( $err ) {
                        $allerr .= "$err\n";
                    }
                    else {
                        $ok = 1;
                        if( $sig->{'set'} ) {
                            my $sets = forcearray( $sig->{'set'} );
                            for my $set ( @$sets ) {
                                my $name = xval $set->{'name'};
                                my $val = xval $set->{'val'};
                                print "Setting $name to $val\n";
                            }
                        }
                        last;
                    }
                }
                if( !$ok ) {
                    die $allerr;
                }
            }
            else {
                my $err = _checkspec( $ob, $spec, \%parms );
                die $err if( $err );
            }
        }
    }
    
    my $inner = { parms => \%parms, _spec => $spec };
    bless $inner, "Class::Core::INNER";
    my $rval = $inner->{'ret'} = &$ref( $inner, $ob );
    if( $spec ) {
        my $retspec = $spec->{'ret'};
        if( $retspec && %$retspec ) {
            my $type = $retspec->{'type'};
            my $err = _checkval( $retspec, $type, $rval );
            die "While checking return - $err" if( $err );
        }
    }
    return $inner;
}

sub _checkspec {
    my ( $ob, $spec, $parms ) = @_;
    my $state = $spec->{'state'};
    if( $state && $state ne $ob->{'_state'} ) {
        _tostate( $ob, $state );
    }
    my $ins = $spec->{'in'};
    for my $key ( keys %$ins ) {
        my $in = $ins->{ $key };
        my $type = $in->{'type'};
        my $val = $parms->{ $key };
        my $err = _checkval( $in, $type, $val );
        return "While checking $key - $err" if( $err );
    }
    return 0;
}

sub _tostate {
    my ( $ob, $dest ) = @_;
    print "Attempt to change to state $dest\n";
    $ob->{'init_'.$dest}->();
    $ob->{'_state'} = $dest;
}

sub _checkval {
    my ( $node, $type, $val ) = @_;
    my $xml = $node->{'xml'};
    if( ! defined $val ) {
        if( $xml->{'optional'} ) { return 0; }
        #my @arr = caller;
        #print Dumper( \@arr );
        return "not defined and should be a $type";
    }
    my $err = 'undefined';
    
    if( $type eq 'number' ) { $err = _checknum( $node, $val ); }
    if( $type eq 'bool' ) { $err = _checkbool( $node, $val ); }
    if( $type eq 'path' ) { $err = _checkpath( $node, $val ); }
    if( $type eq 'hash' ) { $err = _checkhash( $node, $val ); }
    return $err;
}

# Note that the 'hash' type could refer to another 'hash' type.
#   This will not actually cause loops even if referring to the same hash, because
#   a different inset set of specs will be followed. If the spec is changed to take use
#   of 'shared' signatures that can be checked in multiple functions, then loops could occur.
sub _checkhash {
    my ( $node, $val ) = @_;
    my $spec = $node->{'xml'};
    if( $spec->{'sig'} ) {
        my $sigs = forcearray( $spec->{'sig'} );
        my $allerr = '';
        my $ok = 0;
        for my $sig ( @$sigs ) {
            # Note that the first parameter to the following function is set to 0. This is ob.
            #   This is needed to be able to change the state of ob if needed based on the spec.
            #   When checking a hash, a hash does not need to change the state so this doesn't matter.
            #   Note that bad things will happen if you set the 'state' attribute on a hash signature.
            #   Don't do that.
            my $err = _checkspec( 0, $sig, $val );
            if( $err ) {
                $allerr .= "$err\n";
            }
            else {
                $ok = 1;
                # We are going to still allow setting of variables within a hash. This is likely overkill, and
                #   this code should probably be removed. Leaving it for now for parallelism.
                if( $sig->{'set'} ) {
                    my $sets = forcearray( $sig->{'set'} );
                    for my $set ( @$sets ) {
                        my $name = xval $set->{'name'};
                        my $val = xval $set->{'val'};
                        print "Setting $name to $val\n";
                    }
                }
                last;
            }
        }
        if( !$ok ) {
            return $allerr;
        }
    }
    else {
         my $err = _checkspec( 0, $spec, $val );
         return $err if( $err );
    }
    return 0;
}

sub _checkpath {
    my ( $in, $val ) = @_;
    my $clean = $val;
    $clean =~ s|//+|/|g;
    if( $clean ne $val ) { return "Path contains // - Path is \"$val\""; }
    $clean =~ s/[:?*+%<>|]//g;
    if( $clean ne $val ) { return "Path contains one of the following ':?*+\%<>|' - Path is \"$val\""; }
    my $xml =  $in->{'xml'};
    if   ( $xml->{'isdir' } && ! -d $clean ) { return "Dir  does not exist - \"$clean\""; }
    elsif( $xml->{'isfile'} && ! -f $clean ) { return "File does not exist - \"$clean\""; }
    elsif( $xml->{'exists'} && ! -e $clean ) { return "Path does not exist - \"$clean\""; }
}

sub _checkbool {
    my ( $in, $val ) = @_;
    {
        no warnings 'numeric';
        if( ($val+0 ne $val) || ( $val != 0 && $val != 1 ) ) {
            return "not a boolean ( it is $val )";
        }
    }
    return 0;
}

sub _checknum {
    my ( $in, $val ) = @_;
    {
        no warnings 'numeric';
        if( $val*1 ne $val ) {
            return "not a number ( it is \"$val\" )";
        }
    }
    my $xml = $in->{'xml'};
    if( $xml->{'min'} ) {
        my $min = xval $xml->{'min'};
        if( $val < $min ) {
            return "less than the allowed minimum of $min ( it is $val )";
        }
    }
    if( $xml->{'max'} ) {
        my $max = xval $xml->{'max'};
        if( $val > $max ) {
            return "more than the allowed maxmimum of $max ( it is $val )";
        }
    }
    return 0;
}
    
package Class::Core::INNER;
use strict;
#use Data::Dumper;
sub get {
    my ( $self, $name ) = @_;
    return $self->{'parms'}{ $name }; 
}
sub add {
    my ( $self, $name, $val ) = @_;
    
    my $spec = $self->{'_spec'};
    my $outs = $spec->{'out'};
    #print Dumper( $self );
    my $outspec = $outs->{ $name };
    
    if( $outspec ) {
       my $type = $outspec->{'type'};
       my $err = Class::Core::VIRT::_checkval( $outspec, $type, $val );
       die "While checking $name - $err" if( $err );
    }
    $self->{'parms'}{$name} = $val;
}

package Class::Core;
use strict;
#use Data::Dumper;
use XML::Bare qw/xval forcearray/;
use vars qw/@EXPORT_OK @EXPORT @ISA/;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw/wrap_class/;
@EXPORT_OK = qw/wrap_class/;
my $core = { classes => {} };
sub read_spec {
    my ( $func ) = @_;
    my ( %in, %out, %ret );
    my $func_spec = { in => \%in, out => \%out, ret => \%ret };
    
    my $ins = forcearray( $func->{'in'} );
    for my $in ( @$ins ) {
        my $name = xval $in->{'name'};
        my $type = xval $in->{'type'}, 'any';
        $in{ $name } = { type => $type, xml => $in };
    }
    
    my $outs = forcearray( $func->{'out'} );
    for my $out ( @$outs ) {
        my $name = xval $out->{'name'};
        my $type = xval $out->{'type'}, 'any';
        $out{ $name } = { type => $type, xml => $out };
    }
    
    my $ret_x = $func->{'ret'};
    if( $ret_x ) {
       my $type = xval $ret_x->{'type'};
       $ret{'type'} = $type;
       $ret{'xml'} = $ret_x;
    }
    
    if( $func->{'state'} ) {
        my $state = xval $func->{'state'};
        $func_spec->{'state'} = $state;
    }
    
    if( $func->{'set'} ) {
        $func_spec->{'set'} = $func->{'set'};
    }
    
    return $func_spec;
}
sub wrap_class {
    my $class = shift;
    no strict 'refs';
    
    my %hash = ( _class => $class, _state => '_loaded', _core => $core );
    my $classes = $core->{'classes'};
    $classes->{ $class } = \%hash;
    
    # Read in the specification setup for the passed class
    my $spectext = ${"$class\::spec"};
    if( $spectext ) {
        my ( $ob, $xml ) = new XML::Bare( text => $spectext );
        #print $ob->xml( $xml );
        my $func_specs = {};
        my %spec = ( funcs => $func_specs );
        $hash{'_spec'} = \%spec;
        my $funcs = forcearray( $xml->{'func'} );
        for my $func ( @$funcs ) {
            my $name = xval $func->{'name'};
            
            my $func_spec;
            if( $func->{'sig'} ) {
                my $sigs = forcearray( $func->{'sig'} );
                my @func_specs = ();
                for my $sig ( @$sigs ) {
                    push( @func_specs, read_spec( $sig ) );
                }
                $func_spec = { sig => \@func_specs };
            }
            else {
                $func_spec = read_spec( $func );
            }
            #print Dumper( $func_spec );
            $func_specs->{ $name } = $func_spec;
        }
    }
    #print Dumper( \%hash );
    
    # Create duplicates of all functions in the source class
    my $ref = \%{"$class\::"};
    
    for my $key ( keys %$ref ) {
        my $func_ref = \&{"$class\::$key"};
        my $fname = $key;
        $key =~ s/^$class\:://;
        $hash{ $fname } = $func_ref;
    }
    
    # Turn the hash we made into an object that is a virtual wrapper
    my $hashref = \%hash;
    bless $hashref, 'Class::Core::VIRT';
    return $hashref;
}

1;

__END__

=head1 SYNOPSIS

TestMod.pm

    package TestMod;
    use Class::Core;
    
    $spec = <<DONE;
    <func name='test'>
        <in name='input' type='number'/>
        <ret type='bool'/>
    </func>
    DONE

    sub new { return wrap_class( 'TestMod' ); }
    
    sub test {
        my ( $core, $self ) = @_;
        my $input = $core->get('input');
        return 0;
    }

Test.pl

    use TestMod;
    my $ob = new TestMod();
    $ob->test( input => '1' ); # will work fine
    $ob->test( input => 'string' ); # will cause an error

=head1 DESCRIPTION

This module is meant to provide a clean class/object system with the following features:

=over 4

=item * Wrapped functions

All class functions are wrapped and used indirectly

=item * Named parameters

Function parameters are always passed by name

    <func name='add'>
        <in name='a'/>
        <in name='b'/>
    </func>

=item * Parameter Type Checking

Function parameters are type checked based on a provided specification in XML

    <func name='add'>
        <in name='a' type='number'/>
        <in name='b' type='number'/>
    </func>

=item * Function Overloading

Functions can be overloaded by using multiple typed function "signatures"

    <func name='runhash'>
        <sig>
            <in name='recurse' type='bool' optional/>
            <in name='path' type='path' isdir/>
            <set name='mode' val='dir'/>
        </sig>
        <sig>
            <in name='path' type='path' isfile/>
            <set name='mode' val='file'/>
        </sig>
    </func>
    
Each 'sig' ( signature ) will be checked in order till one of them validates. The
first one to validate is used. The 'set' node are run on the signature that validates.

=item * Automatic Object Instantiation ( coming )

Classes are automatically instantiated when needed based on dependencies 

=item * Object States ( coming )

Classes / Objects can have multiple states 

=item * Automatic State Change ( coming )

Class methods may require their owning object to be in a specific case in order to run
 ( in which case the proper function to change states will be called automatically ) 

=back

=head2 Function Parameter Validation

=head3 Input Parameters

    <func name='add'>
        <in name='a'/>
        <in name='b'/>
    </func>

=head3 Output Parameters

    <func name='add'>
        <out name='a'/>
        <out name='b'/>
    </func>

=head3 Classic Return Type

    <func name='check_okay'>
        <ret type='bool'/>
    </func>

=head2 Parameter Types

=head3 Number

The 'number' type validates that the parameter is numerical. Note that it does this
by checked that adding 0 to the number does not affect it. Because of this trailing
zeros will cause the validation to fail. This is expected and normal behavior.

The 'min' and 'max' attributes can be used to set the allowable numerical range.

=head3 Text

The 'text' type validates that the passed parameter is a literal string of some sort.
( as opposed to being a reference of some sort )

=head3 Date ( coming )

=head3 Path

The 'path' type validates that the passed parameter is a valid pathname.

The 'exists' attribute can be added to ensure there is a directory or file
existing at the specified path.

The 'isdir' attribute can be used to check that the path is to a directory.

The 'isfile' attribute can be used to check that the path is to a file.

=head3 Boolean

The 'boolean' type validates that the passed parameter is either 0 or 1. Any
other values will not validate.

=head3 Hash

The 'hash' type vlidates that the passed paramter is a reference to a hash,
and then further validates the contents of the hash in the same way that
parameters are validated.

    <func name='do_something'>
        <in name='person' type='hash'>
            <in name='name' type='text'/>
            <in name='age' type='number'/>
        </in>
    </func>

=head1 LICENSE

  Copyright (C) 2012 David Helkowski & T.Trowe Price
  
  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 2 of the
  License, or (at your option) any later version.  You may also can
  redistribute it and/or modify it under the terms of the Perl
  Artistic License.
  
  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

=cut
