#!/usr/bin/perl -w

use strict;
use Test::More tests => 39;
use Test::Exception;

BEGIN { use_ok( 'CGI::Expand' ); }

my $query = 'a.0=3&a.2=4&b.c.0=x&c.0=2&c.1=3&d=';
my $flat = {
    'a.0' => 3, 'a.2' => 4, 'b.c.0' => "x", c => [2, 3], d => '',
};
my $deep = {
    a => [3,undef,4],
    b => { c => ['x'] },
    c => ['2','3'],
    d => '',
};

is_deeply( CGI::Expand::expand_hash($flat), $deep, 'expand_hash');

sub Fake::param {
    shift;
    return keys %$flat unless @_;
    return $flat->{$_[0]};
}

# only uses param interface
is_deeply( expand_cgi(bless []=>'Fake'), $deep, 'param interface');

CGI::Expand->import('expand_hash');
is_deeply( expand_hash($flat), $deep, 'import');

isa_ok(expand_hash({1,2}), 'HASH');
is_deeply(expand_hash({'1.0',2}), {1=>[2]}, 'top level always hash (digits)');
is_deeply(expand_hash(), {}, 'top level always hash (empty)');

my @array_99;
$array_99[99] = 1;

is_deeply(expand_hash({'a.99',1}), {a=>\@array_99}, ' < 100 array' );
throws_ok { expand_hash({'a.100',1}) } qr/^CGI param array limit exceeded/;
is_deeply(expand_hash({'a.\100',1}), {a=>{100=>1}}, ' \100 hash' );

{
    # Limit adjustable
    local $CGI::Expand::Max_Array = 200;
    my @array_199;
    $array_199[199] = 1;

    is_deeply(expand_hash({'a.199',1}), {a=>\@array_199}, ' < 200 array' );
    throws_ok { expand_hash({'a.200',1}) } qr/^CGI param array limit exceeded/;
    is_deeply(expand_hash({'a.\200',1}), {a=>{200=>1}}, ' \200 hash' );
}

throws_ok { expand_hash($_) } qr/^CGI param clash/
    for (   {'a.1',1,'a.b',1},
            {'a.1',1,'a',1},
            {'a.b',1,'a',1},
        );

# escaping and weird cases
my $ds = "\\\\";
is_deeply(expand_hash({'a.\0'=>1}), {a=>{0=>1}}, '\digit' );
is_deeply(expand_hash({'a.\0\\'=>1}), {a=>{'0\\'=>1}}, '\ at end' );
is_deeply(expand_hash({'a\.0'=>1}), {'a.0'=>1}, '\dot' );
is_deeply(expand_hash({'\a.0'=>1}), {'a'=>[1]}, '\ first alpha' );
is_deeply(expand_hash({'a\a.0'=>1}), {'aa'=>[1]}, '\ other alpha' );
is_deeply(expand_hash({"$ds.0"=>1}), {'\\'=>[1]}, '\ only first' );
is_deeply(expand_hash({"a.$ds.0"=>1}), {a=>{'\\'=>[1]}}, '\ only other' );
is_deeply(expand_hash({"${ds}a"=>1}), {'\\a'=>1}, 'double \ to one' );
is_deeply(expand_hash({"a$ds.0"=>1}), {'a\\'=>[1]}, 'double \ dot to one' );
is_deeply(expand_hash({'.a.'=>1}), {''=>{a=>{''=>1}}}, 'dot start end' );
is_deeply(expand_hash({'a..0'=>1}), {a=>{''=>[1]}}, 'dot dot middle' );
is_deeply(expand_hash({'a..'=>1}), {a=>{''=>{''=>1}}}, 'dot dot end' );
is_deeply(expand_hash({'.'=>1}), {''=>{''=>1}}, 'dot only' );
is_deeply(expand_hash({''=>1}), {''=>1}, 'empty key' );


SKIP: {
    skip "No CGI module", 9 unless eval 'use CGI; 1';

    is_deeply( expand_cgi(CGI->new($query)), $deep, 'expand_cgi');

    ok(eq_set( ( expand_cgi(CGI->new('a=1&a=2')) )->{a}, [2, 1]), 
                                                    'cgi multivals');

    throws_ok { expand_cgi(CGI->new($_)) } qr/^CGI param clash/
        for (  
            'a.0=3&a.c=4',
            'a.c=3&a.0=4',
            'a.0=3&a=b',
            'a.a=3&a=b',
            'a=3&a.0=b',
            'a=3&a.a=b',
            'a=3&a=4&a.b=1',
        );
}
