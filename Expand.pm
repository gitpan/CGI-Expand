package CGI::Expand;
$VERSION = 1.01;
# $Revision: 1.2 $ $Date: 2004/01/08 11:41:57 $

require Exporter;
@ISA = ('Exporter');
@EXPORT = qw(expand_cgi);
@EXPORT_OK = qw(expand_hash);

use strict;
use warnings;
use Carp qw(croak);

$CGI::Expand::Max_Array ||= 100; # limit array size

sub expand_cgi {
    my $cgi = shift; # CGI or Apache::Request
    my %args;

    # permit multiple values CGI style
    for ($cgi->param) {
        my @vals = $cgi->param($_);
        $args{$_} = @vals > 1 ? \@vals : $vals[0];
    }
    return expand_hash(\%args);
}

# Convert from { 'a.0' => 3, 'a.2' => 4, 'b.c.0' => "x", c => [2, 3], d => }
# args {'a' => ['3',undef,'4'],'b' => {'c' => ['x']},'c' => ['2','3'],'d' => ''}
# first segment is alway treated as a hash key
sub expand_hash {
    my $flat = shift;
    my $deep = {};
    for my $name (keys %$flat) {

        # These next two regexes are the escaping aware equivalent
        # to the following:
        # my ($first, @segments) = split(/\./, $name, -1);

        # m// splits on unescaped '.' chars
        $name =~ m/^ ( [^\\.]* (?: \\(?:.|$) [^\\.]* )* ) /gx; # can't fail
        my $first = $1;
        $first =~ s/\\(.)/$1/g; # remove escaping

        my (@segments) = 
                $name =~ m/\G (?:\.) ( [^\\.]* (?: \\(?:.|$) [^\\.]* )* ) /gx;

        my $box_ref = \$deep->{$first};
        for (@segments) {
            if(/^(0|[1-9]\d*)$/) { 
                croak "CGI param array limit exceeded $1 for $name=$_"
                    if($1 >= $CGI::Expand::Max_Array);
                $$box_ref = [] unless defined $$box_ref;
                croak "CGI param clash for $name=$_" 
                    unless ref $$box_ref eq 'ARRAY';
                $box_ref = \($$box_ref->[$1]);
            } else { 
                s/\\(.)/$1/g; # remove escaping
                $$box_ref = {} unless defined $$box_ref;
                croak "CGI param clash for $name=$_"
                    unless ref $$box_ref eq 'HASH';
                $box_ref = \($$box_ref->{$_});
            }    
        }
        croak "CGI param clash for $name value $flat->{$name}" 
            if defined $$box_ref;
        $$box_ref = $flat->{$name};
    }
    return $deep;
}

1;
__END__

=pod 

=head1 NAME

CGI::Expand - convert flat hash to nested data using TT2's dot convention

=head1 SYNOPSIS

    use CGI::Expand;
    use CGI; # or Apache::Request, etc.

    $args = expand_cgi( CGI->new('a.0=3&a.2=4&b.c.0=x') );
    # $args = { a => [3,undef,4], b => { c => ['x'] }, }

    # Or to catch exceptions:
    eval {
        $args = expand_cgi( CGI->new('a.0=3&a.2=4&b.c.0=x') );
    } or log_and_exit( $@ );

    #-----
    use CGI::Expand qw(expand_hash);

    $args = expand_hash({'a.0'=>77}); # $args = { a => [ 77 ] }

=head1 DESCRIPTION

Converts a CGI query into structured data using a dotted name
convention similar to TT2.  

C<expand_cgi> works with CGI.pm, Apache::Request or anything with an
appropriate "param" method.  Or you can use C<expand_hash> directly.

=head1 Motivation

The Common Gateway Interface restricts parameters to name=value pairs,
but often we'd like to use more structured data.  This module
uses a name encoding convention to rebuild a hash of hashes, arrays
and values.  Arrays can either be ordered, or from CGI's multi-valued
parameter handling.

The generic nature of this process means that the core components
of your system can remain CGI ignorant and operate on structured data.
Better for modularity, better for testing.

(This problem has appeared a few times in other forums, L<"SEE ALSO">)

=head1 DOT CONVENTION

The key-value pair "a.b.1=hi" expands to the perl structure:

  { a => { b => [ undef, "hi" ] }

The key ("a.b.1") specifies the location at which the value
("hi") is stored.  The key is split on '.' characters, the
first segment ("a") is a key in the top level hash, 
subsequent segments may be keys in sub-hashes or 
indices in sub-arrays.  Integer segments are treated
as array indices, others as hash keys.

Array size is limited by $CGI::Expand::Max_Array,
100 by default.

The backslash '\' escapes the next character in cgi parameter names
allowing '.' , '\' and digits in hash keys.  The escaping
'\' is removed.  Values are not altered.

=head2 Key-Value Examples

  # HoHoL
  a.b.1=hi ---> { a => { b => [ undef, "hi" ] }

  # HoLoH
  a.1.b=hi ---> { a => [ undef, { b => "hi" } ] }

  # top level always a hash
  9.0=hi   ---> { "9" => [ "hi" ] }

  # can backslash escape to treat digits hash as keys
  a.\0=hi     ---> { "a" => { 0 => "hi"} }

  # or to put . and \ literals in keys
  a\\b\.c=hi  ---  { 'a\\b\.c' => "hi" }

=head1 EXPORTS

C<expand_cgi> by default, C<expand_hash> upon request.

=head1 FUNCTIONS

=over 4

=item C< $args = expand_cgi ( $CGI_object_or_similer ) >

Takes a CGI object and returns a hashref for the expanded
data structure (or dies, see L<"EXCEPTIONS">).

Wrapper around expand_hash that uses the "param" method of 
the CGI object to collect the names and values.

Handles multivalued parameters as array refs
(although they can't be mixed with indexed arrays and
will have an undefined ordering).

    $query = 'a.0=3&a.2=4&b.c.0=x&c.0=2&c.1=3&d=&e=1&e=2';

    $args = expand_cgi( CGI->new($query) );

    # result:
    # $args = {
    #    a => [3,undef,4],
    #    b => { c => ['x'] },
    #    c => ['2','3'],
    #    d => '',
    #    e => ['1','2'], # order depends on CGI/etc
    # };

=item C< $args = expand_hash ( $hashref ) >

Expands the keys of the parameter hash according
to the dot convention (or dies, see L<"EXCEPTIONS">).

    $args = expand_hash({ 'a.b.1' = [1,2] });
    # $args = { a => { b => [undef, [1,2] ] } }

=back

=head1 EXCEPTIONS

B<WARNING> the USERs of your site can cause these exceptions
so you must decide how they are handled (possibly by letting
the process die).

=over 4

=item "CGI param array limit exceeded..."

If an array index exceeds $CGI::Expand::Max_Array (default: 100)
then an exception is thrown.  

=item "CGI param clash for..."

A cgi query like "a=1&a.b=1" would require the value of $args->{a}
to be both 1 and { b => 1 }.  Such type inconsistencies
are reported as exceptions.  (See test.pl for for examples)

=back

=head1 TODO 

It may be useful to provide the inverse process, to convert
a data structure back to a query string, CGI object or
set of hidden form fields.  (I do my persistence server-side
and html with TT2 so this hasn't yet come up)

Another, potentially useful option would be to remove empty
parameters.  (I think I'll leave this to another tool..)

Glob style parameters (with SCALAR, ARRAY and HASH slots)
would resolve the type clashes.  I suspect it would be ungainly
and memory hungry to use.

=head1 LIMITATIONS

The top level is always a hash.  Consequently, any digit only names
will be keys in this hash rather than array indices.

=head1 SEE ALSO

=over 4

=item *

L<HTTP::Rollup> - Replaces CGI.pm completely, no list ordering.

=item *

L<CGI::State> - Tied to CGI.pm, unclear error checking, 
has the inverse conversion.

=item *

http://template-toolkit.org/pipermail/templates/2002-January/002368.html

=item *

There's a tiny and beautiful reduce solution somewhere on perlmonks.

=back

=head1 AUTHOR

Brad Bowman E<lt>cgi-expand@bereft.netE<gt>

=cut 
